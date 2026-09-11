"""
AI Advisor service layer — business logic extracted from app.routers.ai_advisor.

Contains context building, model API calls, chat persistence, and streaming.
No FastAPI dependency — all functions accept CursorWrapper as parameter.
FastAPI-adjacent concerns (HTTPException, Depends, Request) belong in the router.
"""

from __future__ import annotations

import asyncio
import json
import logging
from calendar import monthrange
from datetime import date, datetime, timezone, timedelta
from typing import AsyncGenerator, Optional

import httpx

from pydantic import BaseModel

from app.core.config import settings
from app.database import CursorWrapper, background_tasks

logger = logging.getLogger(__name__)


# ── Pydantic Models ──────────────────────────────────────────────────


class HistoryItem(BaseModel):
    role: str  # "user" | "assistant"
    content: str


class AdviseRequest(BaseModel):
    question: str
    model: str = "flash"  # "flash" | "advanced"  (legacy: "opus")
    history: list[HistoryItem] = []


class AdviseResponse(BaseModel):
    answer: str
    model_used: str


class ChatRequest(BaseModel):
    question: str
    model: str = "flash"
    history: list[HistoryItem] = []
    retry_parent_id: Optional[int] = None


class ChatResponse(BaseModel):
    user_message_id: int
    ai_message_id: int


class ChatMessageResponse(BaseModel):
    id: int
    role: str
    content: str
    status: str
    model: str
    parent_message_id: Optional[int] = None
    created_at: str


# ── System Prompt ─────────────────────────────────────────────────────

SYSTEM_PROMPT = """Kamu adalah asisten keuangan keluarga yang berpengalaman untuk {user_name}. 
Kamu membantu {user_name} dan pasangannya mengelola keuangan rumah tangga secara cerdas.
Percakapan ini bersifat personal — hanya {user_name} yang sedang berbicara denganmu.

─── SAPAAN (WAJIB, SATU REGISTER) ───
• Panggil lawan bicara **kamu**. Boleh sebut nama depan persis: {user_name}.
• Dilarang gelar/sapaan: kak, kang, mas, mbak, mba, bu, pak, bang, bro, sis, sob, nda, dek, gan.
• Jangan campur sapaan. Dari pesan pertama sampai terakhir di thread ini, register-nya sama.
• Kalau history lama ada kak/kang/mas, abaikan — tetap kamu.

**Ringkasan percakapan sebelumnya:**
{chat_summary}

━━━ DATA TERKINI — {current_datetime_wib} ━━━

**Siklus Keuangan:** {cycle_label}
**Anggota Keluarga:** {members}

**Ringkasan Keuangan Keluarga:**
• Pemasukan: Rp{income:,}
• Pengeluaran: Rp{expense:,}
• Saldo Bersih: Rp{balance:,}
• Rasio Pengeluaran: {expense_ratio:.1f}% dari pemasukan
• Rata-rata Pengeluaran Harian: Rp{avg_daily_expense:,}

**Ringkasan Per Kategori:**
{category_breakdown}

**Statistik Per Kategori:**
{cat_stats}

**Aktivitas Per Anggota:**
{member_summary}

**Transaksi Terbaru:**
{recent_transactions}

**Anggaran vs Realisasi:**
{budgets}

**Kesehatan Anggaran & Proyeksi:**
{health_context}

**Tren 6 Siklus Terakhir (Pemasukan | Pengeluaran):**
{trend}

**Catatan Kategori Khusus:**
Pengguna memiliki dua kategori khusus:
• Penarikan Tabungan & Investasi / Savings & Investment Disbursed — pemasukan saat menarik dana tabungan/investasi.
• Hasil Investasi / Savings & Investment Return — pemasukan dari dividen, capital gain, bunga, dll.
• Dana Darurat / Emergency Funds — dicatat sebagai pengeluaran saat menyisihkan, pemasukan saat menggunakan dana.
{all_time_balances}

**Total Utang:**
{debt_context}

{search_results}

─── CARA MENGANALISIS ───
Gunakan kerangka analisis berikut secara konsisten:

1. **Kesehatan Anggaran** — Bandingkan realisasi vs anggaran per kategori. Kategori mana yang over budget? Mana yang masih aman? Hitung sisa anggaran. Gunakan data proyeksi untuk memperingatkan jika tren pengeluaran saat ini akan menyebabkan over budget sebelum akhir siklus.

2. **Pola Pengeluaran** — Identifikasi kategori dengan pengeluaran tertinggi. Apakah ada anomali (lonjakan tidak wajar)? Bandingkan dengan siklus sebelumnya dari data tren.

3. **Rasio Keuangan** — Hitung: (a) savings rate = saldo ÷ pemasukan, (b) proporsi per kategori terhadap total pengeluaran, (c) rata-rata harian.

4. **Rekomendasi Kontekstual** — Berdasarkan data nyata, beri saran spesifik: "Kamu bisa hemat RpX dari kategori Y dengan cara Z." Jangan memberi saran umum tanpa data.

─── ATURAN ───
• Bahasa Indonesia natural, hangat tapi profesional.
• Sertakan angka spesifik dari data — jangan generalisasi.
• Sebut nama anggota keluarga jika relevan dengan konteks transaksi (misal "Nahda belanja kebutuhan bayi").
• Jika hanya sapaan, balas ramah + tawarkan analisis keuangan.
• Jika ditanya di luar keuangan, arahkan kembali.
• Jika ada [Hasil Pencarian Web], gunakan sebagai referensi dengan menyebut sumbernya singkat.
• Jangan sebut diri sebagai AI — cukup "saya" atau "asisten keuangan".
• Jangan rekomendasikan aplikasi AI keuangan, budgeting, atau platform finansial lain.
• FORMAT BACAAN: jangan pakai tabel markdown (kolom | pipa). Pakai daftar berpoin per baris, misalnya \"Kategori Gaji: Rp12.000.000\" atau bullet. Kalau perlu sajikan banyak nilai, pakai per baris, bukan tabel."""


# ── Private Helpers ───────────────────────────────────────────────────


async def _get_household_id(user_id: int, db: CursorWrapper) -> Optional[int]:
    """Get the household ID for a user, or None if not in a household."""
    cursor = await db.execute(
        "SELECT household_id FROM household_members WHERE user_id = ?",
        (user_id,),
    )
    row = await cursor.fetchone()
    return row["household_id"] if row else None


# ── Context Building ──────────────────────────────────────────────────


async def build_context(user_id: int, db: CursorWrapper, question: str = "") -> dict:
    """Build financial context for the AI advisor prompt.

    Includes household-level data (all members) when the user is in a household.
    """
    # User info
    cursor = await db.execute(
        "SELECT display_name FROM users WHERE id = ?", (user_id,)
    )
    user = await cursor.fetchone()
    user_name = user["display_name"] if user else f"User #{user_id}"

    # Household info
    household_id = await _get_household_id(user_id, db)

    # Household members
    cursor = await db.execute(
        """SELECT u.display_name, hm.role
           FROM household_members hm
           JOIN users u ON hm.user_id = u.id
           WHERE hm.household_id = (
               SELECT household_id FROM household_members WHERE user_id = ?
           )""",
        (user_id,),
    )
    member_list = []
    async for r in cursor:
        member_list.append(f"{r['display_name']} ({r['role']})")
    members = ", ".join(member_list) or "Sendiri"

    # Current cycle
    now = datetime.now(timezone(timedelta(hours=7)))
    current_datetime = now.strftime("%A, %d %B %Y %H:%M WIB")

    cursor = await db.execute(
        "SELECT COALESCE(cycle_start_day, 1) as cycle_start_day FROM users WHERE id = ?",
        (user_id,),
    )
    row = await cursor.fetchone()
    cycle_start_day = row["cycle_start_day"] if row else 1

    from app.utils.cycle import get_cycle_range

    d_from_date, d_to_date = get_cycle_range(now.date(), cycle_start_day)
    d_from = d_from_date.isoformat()
    d_to = d_to_date.isoformat()
    cycle_label = f"{d_from_date.strftime('%d %b')} – {d_to_date.strftime('%d %b %Y')}"

    # ── Household-level financial summary ──
    if household_id:
        cursor = await db.execute(
            "SELECT user_id FROM household_members WHERE household_id = ?",
            (household_id,),
        )
        member_ids = [r["user_id"] async for r in cursor]
    else:
        member_ids = [user_id]

    placeholders = ",".join("?" * len(member_ids))

    # Income / Expense summary for household
    cursor = await db.execute(
        f"""SELECT type, COALESCE(SUM(amount_ord), 0) as total
           FROM transactions WHERE user_id IN ({placeholders})
             AND COALESCE(date, LEFT(created_at::text, 10)) BETWEEN ? AND ?
           GROUP BY type""",
        (*member_ids, d_from, d_to),
    )
    income = 0
    expense = 0
    async for r in cursor:
        if r["type"] == "income":
            income = r["total"]
        else:
            expense = r["total"]
    balance = income - expense

    # Derived metrics
    expense_ratio = (expense / income * 100) if income > 0 else 0.0
    cycle_days = (d_to_date - d_from_date).days or 1
    avg_daily_expense = expense / cycle_days if cycle_days > 0 else 0

    # ── Per-category breakdown (household, with owner info) ──
    cursor = await db.execute(
        f"""SELECT t.vault_blob, t.type, t.date, u.display_name as owner
           FROM transactions t
           JOIN users u ON t.user_id = u.id
           WHERE t.user_id IN ({placeholders})
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) BETWEEN ? AND ?
           ORDER BY t.date DESC""",
        (*member_ids, d_from, d_to),
    )
    all_txns = await cursor.fetchall()
    from app.core.vault_row import open_row

    all_txns = [open_row(dict(t)) for t in all_txns]

    # Category summary
    cat_map = {}
    for t in all_txns:
        key = f"{t['category_name']} ({t['type']})"
        if key not in cat_map:
            cat_map[key] = {"total": 0, "count": 0, "members": set()}
        cat_map[key]["total"] += t["amount"]
        cat_map[key]["count"] += 1
        cat_map[key]["members"].add(t["owner"])

    cat_parts = []
    for cat_name in sorted(cat_map.keys(), key=lambda k: -cat_map[k]["total"]):
        info = cat_map[cat_name]
        members_str = ", ".join(sorted(info["members"]))
        cat_parts.append(
            f"• {cat_name}: Rp{info['total']:,} ({info['count']} transaksi oleh {members_str})"
        )
    category_breakdown = "\n".join(cat_parts) if cat_parts else "Belum ada transaksi"

    # ── Per-category stats: avg per transaction + top 3 most expensive ──
    cat_stats = {}
    for t in all_txns:
        key = f"{t['category_name']} ({t['type']})"
        if key not in cat_stats:
            cat_stats[key] = {"amounts": []}
        cat_stats[key]["amounts"].append(t["amount"])

    cat_extra_parts = []
    for cat_name in sorted(
        cat_stats.keys(), key=lambda k: -sum(cat_stats[k]["amounts"])
    ):
        amounts = sorted(cat_stats[cat_name]["amounts"], reverse=True)
        avg_val = sum(amounts) // len(amounts)
        top3_str = ", ".join(f"Rp{a:,}" for a in amounts[:3])
        cat_extra_parts.append(
            f"• {cat_name}: rata-rata Rp{avg_val:,}/transaksi | termahal: {top3_str}"
        )

    # ── Per-member totals ──
    member_totals = {}
    for t in all_txns:
        owner = t["owner"]
        if owner not in member_totals:
            member_totals[owner] = {"income": 0, "expense": 0, "count": 0}
        member_totals[owner][t["type"]] += t["amount"]
        member_totals[owner]["count"] += 1

    member_parts = []
    for name in sorted(member_totals.keys()):
        m = member_totals[name]
        member_parts.append(
            f"• {name}: {m['count']} transaksi | pemasukan Rp{m['income']:,} | pengeluaran Rp{m['expense']:,}"
        )

    # ── Recent transactions (last 15, with owner) ──
    recent = all_txns[:15]
    txn_parts = []
    for t in recent:
        label = "pemasukan" if t["type"] == "income" else "pengeluaran"
        txn_parts.append(
            f"• {t['date']} | {t['owner']} | {label} | {t['category_name']} | Rp{t['amount']:,} | {t['description'] or '-'}"
        )
    recent_transactions = "\n".join(txn_parts) if txn_parts else "Belum ada transaksi"

    # ── 6-cycle trend (cycle-aware) ──
    trend_parts = []
    for i in range(5, -1, -1):
        y = now.year
        m = now.month - i
        while m < 1:
            m += 12
            y -= 1
        anchor = date(y, m, min(15, monthrange(y, m)[1]))
        c_from, c_to = get_cycle_range(anchor, cycle_start_day)
        c_from_s = c_from.isoformat()
        c_to_s = c_to.isoformat()
        cycle_range_str = f"{c_from.strftime('%d/%m')}-{c_to.strftime('%d/%m')}"

        cursor = await db.execute(
            f"""SELECT type, COALESCE(SUM(amount_ord), 0) as total
               FROM transactions WHERE user_id IN ({placeholders})
                 AND COALESCE(date, LEFT(created_at::text, 10)) BETWEEN ? AND ?
               GROUP BY type""",
            (*member_ids, c_from_s, c_to_s),
        )
        inc = 0
        exp = 0
        async for r in cursor:
            if r["type"] == "income":
                inc = r["total"]
            else:
                exp = r["total"]
        trend_parts.append(f"{cycle_range_str} | I=Rp{inc:,} | E=Rp{exp:,}")
    trend = " | ".join(trend_parts)

    from app.utils.budget_ai import get_projection

    projection = await get_projection(db, user_id, cycle_start_day, d_from, d_to)
    budgets_list = []
    for cat in projection["categories"]:
        pct = cat["percentage"]
        remaining = cat["remaining"]
        status = "✅" if remaining >= 0 else "🔴"
        budgets_list.append(
            f"• {cat['category_name']}: Rp{cat['actual_spent']:,} / Rp{cat['budget_amount']:,} ({pct:.0f}%) — sisa Rp{remaining:,} {status}"
        )
    budgets = "\n".join(budgets_list) if budgets_list else "Belum ada anggaran"

    # ── Budget health & projection ──
    proj_lines = []
    for cat in projection["categories"]:
        icon_map = {
            "healthy": "✅",
            "warning": "⚠️",
            "at_risk": "🔴",
            "exhausted": "❌",
        }
        label_map = {
            "healthy": "Aman",
            "warning": "Hati-hati",
            "at_risk": "Berisiko",
            "exhausted": "Habis",
        }
        icon = icon_map.get(cat["health"], "❓")
        label = label_map.get(cat["health"], "")
        proj_lines.append(
            f"• {cat['category_name']}: Rp{cat['actual_spent']:,} / Rp{cat['budget_amount']:,} "
            f"({cat['percentage']:.0f}%) {icon} {label}"
        )
        if cat["health"] in ("at_risk", "warning") and cat["projected_end"] > cat[
            "budget_amount"
        ]:
            proj_lines.append(
                f"  ↳ Proyeksi akhir siklus: Rp{cat['projected_end']:,} "
                f"(kelebihan Rp{cat['projected_remaining'] * -1:,})"
            )

    health_context_lines = [
        f"**Kesehatan Anggaran:** (Hari ke-{projection['days_elapsed']} dari {projection['total_days']} hari — {projection['cycle_progress_pct']:.0f}% siklus)",
    ]
    if proj_lines:
        health_context_lines.extend(proj_lines)
    else:
        health_context_lines.append("Tidak ada data anggaran.")
    health_context = "\n".join(health_context_lines)

    # ── All-time category balances (S&I, Dana Darurat) ──
    cursor = await db.execute(
        f"""SELECT vault_blob, type FROM transactions
           WHERE user_id IN ({placeholders})""",
        (*member_ids,),
    )
    from app.core.vault_row import open_row

    si_saved = 0
    si_withdrawn = 0
    si_returns = 0
    emergency_bal = 0
    for r in await cursor.fetchall():
        d = open_row(dict(r))
        cat, typ, total = d.get("category_name") or "", d.get("type"), int(d.get("amount") or 0)
        if cat == "Tabungan & Investasi" and typ == "expense":
            si_saved += total
        elif cat == "Penarikan Tabungan & Investasi" and typ == "income":
            si_withdrawn += total
        elif cat == "Hasil Investasi" and typ == "income":
            si_returns += total
        elif cat == "Dana Darurat" and typ == "expense":
            emergency_bal += total
        elif cat == "Dana Darurat" and typ == "income":
            emergency_bal -= total
        elif cat == "Tabungan & Investasi" and typ == "income":
            si_withdrawn += total

    si_bal = si_saved - si_withdrawn
    breakdown_parts = []
    if si_saved:
        breakdown_parts.append(f"Tabungan Rp{si_saved:,}")
    if si_withdrawn:
        breakdown_parts.append(f"Penarikan Rp{si_withdrawn:,}")
    if si_returns:
        breakdown_parts.append(f"Return Rp{si_returns:,}")
    breakdown_str = " • ".join(breakdown_parts) if breakdown_parts else ""

    all_time_balances = (
        f"• Saldo Tabungan & Investasi: Rp{si_bal:,}\n"
        + (f"  ({breakdown_str})\n" if breakdown_str else "")
        + f"• Saldo Dana Darurat: Rp{emergency_bal:,}\n"
        f"(Balance positif = saldo terkumpul, negatif = defisit)"
    )

    # ── Web search (if question triggers it) ──
    search_text = ""
    if question:
        from app.services.web_search import _should_search, search_web, format_search_results

        if _should_search(question):
            results = await search_web(question)
            if results:
                search_text = format_search_results(results)

    # ── Debt summary (household-aware) ──
    total_kpr = 0

    # KPR per-simulation details with owner
    hh_where = "ks.user_id = ? OR ks.household_id IN (SELECT household_id FROM household_members WHERE user_id = ?)"
    cursor = await db.execute(
        f"""SELECT ks.id, ks.vault_blob, ks.interest_type, ks.tenor_months,
                  ks.start_month, ks.start_year, ks.due_date, ks.user_id,
                  u.display_name AS owner,
                  CASE WHEN ks.user_id = ? THEN 0 ELSE 1 END AS is_member,
                  COALESCE((SELECT COUNT(*) FROM kpr_extra_payments kep WHERE kep.simulation_id = ks.id), 0) AS extra_payments
           FROM kpr_simulations ks
           JOIN users u ON u.id = ks.user_id
           WHERE {hh_where}
           ORDER BY ks.display_order ASC, ks.created_at DESC""",
        (user_id, user_id, user_id),
    )
    from app.core.vault_row import open_row

    kpr_details = [open_row(dict(r)) for r in await cursor.fetchall()]
    kpr_count = len(kpr_details)

    # Per-member KPR breakdown
    kpr_member_map = {}
    for k in kpr_details:
        ow = k["owner"]
        if ow not in kpr_member_map:
            kpr_member_map[ow] = {"count": 0, "types": set()}
        kpr_member_map[ow]["count"] += 1
        kpr_member_map[ow]["types"].add(k["interest_type"])

    # CC transactions this month (household-aware)
    cc_hh_where = "cc.user_id = ? OR cc.household_id IN (SELECT household_id FROM household_members WHERE user_id = ?)"
    cc_hh_params = (user_id, user_id)

    cursor = await db.execute(
        f"""SELECT COALESCE(SUM(cct.amount_ord), 0) AS total_txns
           FROM credit_card_transactions cct
           JOIN credit_cards cc ON cc.id = cct.card_id
           WHERE ({cc_hh_where}) AND cct.is_installment = 0
               AND EXTRACT(YEAR FROM cct.transaction_date::date) = EXTRACT(YEAR FROM CURRENT_DATE)
               AND EXTRACT(MONTH FROM cct.transaction_date::date) = EXTRACT(MONTH FROM CURRENT_DATE)""",
        cc_hh_params,
    )
    row = await cursor.fetchone()
    total_cc_txns = int(row["total_txns"]) if row else 0

    # CC installments (household-aware)
    cursor = await db.execute(
        f"""SELECT cci.vault_blob, cci.total_months, cci.start_month
           FROM credit_card_installments cci
           JOIN credit_cards cc ON cc.id = cci.card_id
           WHERE ({cc_hh_where})""",
        cc_hh_params,
    )
    total_cc_installments = 0
    cc_count = 0
    today_ai = date.today()
    now_m = today_ai.year * 12 + today_ai.month
    for r in await cursor.fetchall():
        sm = str(r["start_month"] or "0000-00")
        start_m = int(sm[:4]) * 12 + int(sm[5:7] or 0)
        months = max(0, int(r["total_months"] or 0) - (now_m - start_m))
        if months <= 0:
            continue
        cc_count += 1
        total_cc_installments += int(open_row(dict(r)).get("monthly_amount") or 0) * months

    # CC per-card details with owner
    cursor = await db.execute(
        f"""SELECT cc.id, cc.billing_date, cc.due_date, cc.vault_blob,
                  cc.user_id, u.display_name AS owner,
                  CASE WHEN cc.user_id = ? THEN 0 ELSE 1 END AS is_member
           FROM credit_cards cc
           JOIN users u ON u.id = cc.user_id
           WHERE {cc_hh_where}
           ORDER BY cc.display_order ASC, cc.created_at DESC""",
        (user_id, user_id, user_id),
    )
    cc_details = await cursor.fetchall()

    inst_by_card: dict[int, list] = {}
    cursor = await db.execute(
        f"""SELECT cci.card_id, cci.vault_blob, cci.total_months, cci.remaining_months
           FROM credit_card_installments cci
           JOIN credit_cards cc ON cc.id = cci.card_id
           WHERE ({cc_hh_where}) AND cci.remaining_months > 0
           ORDER BY cci.id ASC""",
        cc_hh_params,
    )
    for row in await cursor.fetchall():
        inst_by_card.setdefault(int(row["card_id"]), []).append(open_row(dict(row)))

    spend_by_card: dict[int, int] = {}
    cursor = await db.execute(
        f"""SELECT cct.card_id, COALESCE(SUM(cct.amount_ord), 0) AS spent
           FROM credit_card_transactions cct
           JOIN credit_cards cc ON cc.id = cct.card_id
           WHERE ({cc_hh_where}) AND cct.is_installment = 0
               AND EXTRACT(YEAR FROM cct.transaction_date::date) = EXTRACT(YEAR FROM CURRENT_DATE)
               AND EXTRACT(MONTH FROM cct.transaction_date::date) = EXTRACT(MONTH FROM CURRENT_DATE)
           GROUP BY cct.card_id""",
        cc_hh_params,
    )
    for row in await cursor.fetchall():
        spend_by_card[int(row["card_id"])] = int(row["spent"])

    today = date.today()
    type_label = {
        "fixed": "Tetap",
        "floating": "Mengambang",
        "graduated": "Bertahap",
        "mix": "Campur",
    }

    total_cc = total_cc_txns + total_cc_installments
    total_debt = total_kpr + total_cc

    debt_parts = []
    if kpr_count > 0:
        debt_parts.append(f"• KPR keluarga: Rp{total_kpr:,} ({kpr_count} simulasi)")
        for k in kpr_details:
            elapsed = (
                (today.year * 12 + today.month)
                - (int(k["start_year"]) * 12 + int(k["start_month"]))
                + 1
            )
            tenor = int(k["tenor_months"] or 1)
            elapsed = max(1, min(elapsed, tenor))
            cur = await db.execute(
                """SELECT vault_blob FROM kpr_monthly_schedules
                   WHERE simulation_id = ? AND month_number = ?""",
                (k["id"], elapsed),
            )
            sch_row = await cur.fetchone()
            sch = open_row(dict(sch_row)) if sch_row else {}
            cicilan = int(sch.get("payment") or 0)
            sisa = int(sch.get("remaining_balance") or k.get("total_loan") or 0)
            total_kpr += sisa
            rate = float(sch.get("interest_rate") if sch.get("interest_rate") is not None else k.get("base_interest_rate") or 0)
            rate_pct = rate * 100 if rate <= 1 else rate
            itype = type_label.get(k["interest_type"] or "fixed", k["interest_type"])
            due = f", jatuh tempo tgl {k['due_date']}" if k["due_date"] else ""
            extra_n = int(k.get("extra_payments") or 0)
            extra_sum = 0
            extra_txt = f", extra payment {extra_n}x Rp{extra_sum:,}" if extra_n else ""
            debt_parts.append(
                f"  - {k['name'] or 'Simulasi KPR'} ({k['owner']}): "
                f"rumah Rp{int(k['property_price'] or 0):,}, DP Rp{int(k['down_payment'] or 0):,}, "
                f"pinjaman Rp{int(k['total_loan'] or 0):,}, bunga {itype} {rate_pct:.2f}%, "
                f"tenor {tenor} bln mulai {int(k['start_month']):02d}/{k['start_year']}{due}, "
                f"bulan ke-{elapsed}, cicilan Rp{cicilan:,}, sisa pokok Rp{sisa:,}{extra_txt}"
            )
    if cc_details:
        debt_parts.append(
            f"• Kartu kredit: outstanding Rp{total_cc:,} "
            f"(belanja bulan ini Rp{total_cc_txns:,} + sisa cicilan Rp{total_cc_installments:,})"
        )
        for c in cc_details:
            cid = int(c["id"])
            card = open_row(dict(c))
            last4 = (card.get("card_number_last4") or "").strip()
            tail = f" *{last4}" if last4 else ""
            spent = spend_by_card.get(cid, 0)
            debt_parts.append(
                f"  - {card.get('name') or 'Kartu'}{tail} ({c['owner']}): limit Rp{int(card.get('credit_limit') or 0):,}, "
                f"tagihan tgl {c['billing_date']}, tempo tgl {c['due_date']}, "
                f"belanja bulan ini Rp{spent:,}"
            )
            for inst in inst_by_card.get(cid, []):
                debt_parts.append(
                    f"      cicilan {inst['description'] or 'tanpa nama'}: "
                    f"Rp{int(inst['monthly_amount'] or 0):,}/bln, "
                    f"{int(inst['remaining_months'] or 0)}/{int(inst['total_months'] or 0)} bln tersisa, "
                    f"pokok Rp{int(inst['total_amount'] or 0):,}"
                )
    if debt_parts:
        debt_context = "\n".join(debt_parts)
        debt_context += f"\n• **Total utang (KPR sisa pokok + CC): Rp{total_debt:,}**"
    else:
        debt_context = "Tidak ada utang aktif saat ini."

    return {
        "user_name": user_name,
        "current_datetime_wib": current_datetime,
        "cycle_label": cycle_label,
        "members": members,
        "income": income,
        "expense": expense,
        "balance": balance,
        "expense_ratio": expense_ratio,
        "avg_daily_expense": avg_daily_expense,
        "category_breakdown": category_breakdown,
        "cat_stats": "\n".join(cat_extra_parts) if cat_extra_parts else "",
        "member_summary": "\n".join(member_parts) if member_parts else "",
        "recent_transactions": recent_transactions,
        "trend": trend,
        "budgets": budgets,
        "health_context": health_context,
        "all_time_balances": all_time_balances,
        "debt_context": debt_context,
        "search_results": search_text,
    }


# ── Model Resolution & API Calls ──────────────────────────────────────


async def resolve_model(model: str) -> tuple[str, str, str]:
    """Return (resolved_model, api_url, api_key) for the given model."""
    if settings.llm_via_openrouter:
        model_map = {
            "flash": "deepseek/deepseek-v4-flash",
            "advanced": "deepseek/deepseek-v4-pro",
            "opus": "deepseek/deepseek-v4-pro",  # legacy APK
        }
    else:
        # OpenCode Go catalog
        model_map = {
            "flash": "deepseek-v4-flash",
            "advanced": "deepseek-v4-pro",
            "opus": "deepseek-v4-pro",  # legacy APK
        }
    resolved = model_map.get(model, model)
    api_url = settings.llm_api_url
    api_key = settings.llm_api_key
    return resolved, api_url, api_key


async def call_model_stream(
    messages: list, model: str = "deepseek-v4-flash"
) -> AsyncGenerator[str, None]:
    """Call the model API with streaming. Yields token strings as they arrive."""
    resolved, api_url, api_key = await resolve_model(model)

    async with httpx.AsyncClient(timeout=600) as client:
        async with client.stream(
            "POST",
            api_url,
            headers=settings.llm_headers(),
            json={
                "model": resolved,
                "messages": messages,
                "max_tokens": 16384,
                "temperature": 0.7,
                "stream": True,
            },
        ) as resp:
            if resp.status_code != 200:
                error_text = await resp.aread()
                logger.warning("AI stream HTTP %s: %s", resp.status_code, error_text[:300])
                if resp.status_code in (401, 403, 429):
                    yield "[ERROR:Layanan AI lagi kena batas pemakaian (kuota 5 jam OpenCode). Tunggu bentar atau pakai Flash.]"
                else:
                    yield f"[ERROR:{resp.status_code}]"
                return

            full_content = ""
            async for line in resp.aiter_lines():
                if not line.startswith("data: "):
                    continue
                payload = line[6:]
                if payload.strip() == "[DONE]":
                    break
                try:
                    chunk = json.loads(payload)
                except json.JSONDecodeError:
                    continue
                # Some providers emit keep-alive/empty events with no choices.
                choices = chunk.get("choices") or []
                if not choices:
                    continue
                delta = choices[0].get("delta", {})
                token = delta.get("content", "")
                if token:
                    full_content += token
                    yield token

            if not full_content or not full_content.strip():
                yield "Maaf, saya tidak bisa merespons pertanyaan itu. Silakan tanya tentang keuangan Anda."


async def call_model(
    messages: list, model: str = "deepseek-v4-flash"
) -> str:
    """Call the model API without streaming. Returns full response text."""
    resolved, api_url, api_key = await resolve_model(model)

    async with httpx.AsyncClient(timeout=300) as client:
        resp = await client.post(
            api_url,
            headers=settings.llm_headers(),
            json={
                "model": resolved,
                "messages": messages,
                "max_tokens": 16384,
                "temperature": 0.7,
            },
        )

    if resp.status_code != 200:
        logger.warning("AI HTTP %s", resp.status_code)
        if resp.status_code in (401, 403, 429):
            raise Exception("Layanan AI lagi kena batas pemakaian (kuota 5 jam OpenCode). Tunggu bentar atau pakai Flash.")
        raise Exception(f"AI API error: {resp.status_code}")

    body = resp.json()
    choices = body.get("choices") or []
    if not choices:
        return "Maaf, saya tidak bisa merespons pertanyaan itu. Silakan tanya tentang keuangan Anda."
    content = choices[0].get("message", {}).get("content", "")
    if not content or not content.strip():
        return "Maaf, saya tidak bisa merespons pertanyaan itu. Silakan tanya tentang keuangan Anda."
    return content.strip()


_HISTORY_WINDOW = 12  # ~6 pasangan user+asisten utuh
_SUMMARY_MAX_CHARS = 2500


def _pack_ai_text(key: str, value: str) -> str:
    from app.core.vault_write import must_dek
    from app.core.vault_row import pack_money

    return pack_money(must_dek(), amount=0, extra={key: value or ""})["vault_blob"]


async def _load_chat_summary(user_id: int, db: CursorWrapper) -> tuple[str, int]:
    cursor = await db.execute(
        "SELECT covered_through_id, vault_blob FROM ai_chat_summaries WHERE user_id = ?",
        (user_id,),
    )
    row = await cursor.fetchone()
    if not row:
        return "", 0
    from app.core.vault_row import open_row

    opened = open_row(dict(row))
    return (opened.get("summary") or "").strip(), int(row["covered_through_id"] or 0)


async def _save_chat_summary(user_id: int, db: CursorWrapper, summary: str, covered_through_id: int) -> None:
    text = summary[:_SUMMARY_MAX_CHARS]
    blob = _pack_ai_text("summary", text)
    await db.execute(
        """INSERT INTO ai_chat_summaries (user_id, covered_through_id, updated_at, vault_blob)
           VALUES (?, ?, TO_CHAR(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), ?)
           ON CONFLICT (user_id) DO UPDATE SET
             covered_through_id = EXCLUDED.covered_through_id,
             updated_at = EXCLUDED.updated_at,
             vault_blob = EXCLUDED.vault_blob""",
        (user_id, covered_through_id, blob),
    )


async def _summarize_overflow(old_summary: str, overflow: list[dict]) -> str:
    transcript = "\n".join(
        f"{m['role']}: {m['content'][:800]}" for m in overflow if m.get("content")
    )
    if not transcript.strip():
        return old_summary
    prompt = (
        "Kamu merangkum percakapan asisten keuangan rumah tangga. Bahasa Indonesia, padat, maksimal 12 kalimat. "
        "Jangan ulang angka saldo/transaksi/utang (itu sudah di data). "
        "Simpan: keputusan, preferensi, pantangan, perbandingan yang sudah dibuat, pertanyaan yang masih terbuka.\n\n"
        f"Ringkasan lama:\n{old_summary or '(kosong)'}\n\n"
        f"Pesan yang keluar dari jendela:\n{transcript}"
    )
    try:
        return await call_model(
            messages=[{"role": "user", "content": prompt}],
            model="flash",
        )
    except Exception:
        logger.warning("Chat summary failed; keeping previous summary")
        return old_summary


async def _prepare_chat_memory(
    user_id: int,
    db: CursorWrapper,
    client_history: list,
    before_id: Optional[int] = None,
) -> tuple[str, list[dict]]:
    """Return (summary_text, recent_history_msgs). May call Flash once on overflow."""
    skip = {"", "Mengumpulkan data keuangan..."}
    summary, covered = await _load_chat_summary(user_id, db)

    if before_id is None:
        recent = [
            {"role": m.role, "content": m.content}
            for m in list(client_history)[-_HISTORY_WINDOW:]
            if getattr(m, "content", None) and m.content.strip() not in skip
        ]
        return (summary or "Belum ada ringkasan percakapan."), recent

    cursor = await db.execute(
        """SELECT id, role, vault_blob FROM ai_messages
           WHERE user_id = ? AND status = 'complete' AND id < ?
           ORDER BY id ASC""",
        (user_id, before_id),
    )
    rows = await cursor.fetchall()
    from app.core.vault_row import open_row

    msgs = []
    for r in rows:
        if r["role"] not in ("user", "assistant"):
            continue
        opened = open_row(dict(r))
        content = (opened.get("content") or "").strip()
        if content not in skip:
            msgs.append({"id": r["id"], "role": r["role"], "content": content})
    recent_full = msgs[-_HISTORY_WINDOW:]
    overflow = msgs[:-_HISTORY_WINDOW] if len(msgs) > _HISTORY_WINDOW else []
    if overflow:
        last_overflow_id = int(overflow[-1]["id"])
        if last_overflow_id > covered:
            new_bits = [m for m in overflow if int(m["id"]) > covered]
            summary = await _summarize_overflow(summary, new_bits)
            if summary:
                await _save_chat_summary(user_id, db, summary, last_overflow_id)
    recent = [{"role": m["role"], "content": m["content"]} for m in recent_full]
    return (summary or "Belum ada ringkasan percakapan."), recent


async def build_messages(
    req: AdviseRequest, current_user: dict, db: CursorWrapper, before_id: Optional[int] = None
) -> list:
    """Build the full messages array: system -> history -> current question."""
    ctx = await build_context(current_user["id"], db, question=req.question)
    summary, history_msgs = await _prepare_chat_memory(
        current_user["id"], db, req.history, before_id=before_id
    )
    ctx["chat_summary"] = summary
    prompt = SYSTEM_PROMPT.format(**ctx)
    return [
        {"role": "system", "content": prompt},
        *history_msgs,
        {"role": "user", "content": req.question},
    ]


# ── Chat Persistence ──────────────────────────────────────────────────


async def start_chat(
    req: ChatRequest,
    current_user: dict,
    db: CursorWrapper,
) -> tuple[int, int]:
    """Save user message, handle retry, save AI placeholder, and start background processing.

    Returns (user_message_id, ai_message_id).
    """
    # 1. Save user message
    cursor = await db.execute(
        """INSERT INTO ai_messages (user_id, role, status, model, vault_blob)
           VALUES (?, 'user', 'complete', ?, ?)""",
        (current_user["id"], req.model, _pack_ai_text("content", req.question)),
    )
    user_msg_id = cursor.lastrowid

    # 2. If retry: mark old AI messages with this parent as 'error:hidden'
    if req.retry_parent_id:
        await db.execute(
            "UPDATE ai_messages SET status = 'error:hidden' WHERE parent_message_id = ? AND role = 'assistant'",
            (req.retry_parent_id,),
        )

    # 3. Save processing placeholder for AI, linked to user message via parent_message_id
    cursor = await db.execute(
        """INSERT INTO ai_messages (user_id, role, status, model, parent_message_id, vault_blob)
           VALUES (?, 'assistant', 'processing', ?, ?, ?)""",
        (current_user["id"], req.model, user_msg_id, _pack_ai_text("content", "")),
    )
    ai_msg_id = cursor.lastrowid

    # 4. Start background task — streams tokens progressively to DB
    _schedule_bg_ai(req, current_user, user_msg_id, ai_msg_id)

    return user_msg_id, ai_msg_id


def _schedule_bg_ai(
    req: ChatRequest,
    current_user: dict,
    user_msg_id: int,
    ai_msg_id: int,
) -> None:
    """Schedule the background AI processing task (fire-and-forget)."""

    from app.core.vault_ctx import current_dek, set_dek

    dek = current_dek()

    async def _process_ai():
        try:
            from app.database import get_db_bg

            set_dek(dek)
            bg_db = await get_db_bg()
            try:
                # Immediate feedback before context building
                await bg_db.execute(
                    "UPDATE ai_messages SET vault_blob = ? WHERE id = ?",
                    (_pack_ai_text("content", "Mengumpulkan data keuangan..."), ai_msg_id),
                )

                advise_req = AdviseRequest(
                    question=req.question, model=req.model, history=req.history
                )
                messages = await build_messages(
                    advise_req, current_user, bg_db, before_id=user_msg_id
                )
                full_content = ""
                last_flush = ""
                async for token in call_model_stream(
                    messages=messages, model=req.model
                ):
                    if token.startswith("[ERROR:"):
                        raise Exception(token[7:-1])
                    full_content += token
                    # Flush to DB every ~100 chars (~every few tokens)
                    if len(full_content) - len(last_flush) >= 100:
                        await bg_db.execute(
                            "UPDATE ai_messages SET vault_blob = ? WHERE id = ?",
                            (_pack_ai_text("content", full_content), ai_msg_id),
                        )
                        last_flush = full_content

                # Final flush — outside the for loop
                await bg_db.execute(
                    "UPDATE ai_messages SET status = 'complete', vault_blob = ? WHERE id = ?",
                    (_pack_ai_text("content", full_content), ai_msg_id),
                )
            finally:
                await bg_db.close()
        except Exception as e:
            logger.exception("AI background failed")
            try:
                from app.database import get_db_bg

                set_dek(dek)
                bg_db = await get_db_bg()
                await bg_db.execute(
                    "UPDATE ai_messages SET status = 'error', vault_blob = ? WHERE id = ?",
                    (_pack_ai_text("content", "Gagal jawab. Coba lagi ya."), ai_msg_id),
                )
                await bg_db.close()
            except Exception as db_err:
                logger.warning(
                    "Failed to update AI message error status: %s", db_err
                )

    task = asyncio.create_task(_process_ai())
    background_tasks.add(task)
    task.add_done_callback(background_tasks.discard)


async def get_chat_messages(
    user_id: int, db: CursorWrapper
) -> list[ChatMessageResponse]:
    """Get all AI chat messages for a user (excluding hidden errors)."""
    cursor = await db.execute(
        """SELECT id, role, status, model, parent_message_id, created_at, vault_blob
           FROM ai_messages
           WHERE user_id = ? AND status != 'error:hidden'
           ORDER BY created_at ASC""",
        (user_id,),
    )
    rows = await cursor.fetchall()
    from app.core.vault_row import open_row

    out = []
    for row in rows:
        d = open_row(dict(row))
        d.pop("vault_blob", None)
        d["content"] = d.get("content") or ""
        out.append(ChatMessageResponse(**d))
    return out


async def delete_chat_messages(user_id: int, db: CursorWrapper) -> None:
    """Delete all AI chat messages for a user."""
    await db.execute("DELETE FROM ai_chat_summaries WHERE user_id = ?", (user_id,))
    await db.execute(
        "DELETE FROM ai_messages WHERE user_id = ?",
        (user_id,),
    )


# ── Router helpers (moved from ai_advisor.py for clean separation) ────


def ensure_api_key_configured():
    """Check that the AI API key is configured. Returns None or raises ValueError."""
    if not settings.llm_api_key:
        raise ValueError("AI belum dikonfigurasi")


def check_model_access(req_model: str, current_user: dict) -> None:
    """Check model access restrictions. Raises ValueError if access denied."""
    if req_model in ("advanced", "opus") and current_user.get("role") != "admin":
        raise ValueError(
            "Advanced model is only available for the primary account holder"
        )
