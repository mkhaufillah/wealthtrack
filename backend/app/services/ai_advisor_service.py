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
    model: str = "flash"  # "flash" | "opus"
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
Jangan panggil atau sebut nama anggota keluarga lain dalam sapaan.

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
• Jangan rekomendasikan aplikasi AI keuangan, budgeting, atau platform finansial lain."""


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
        f"""SELECT type, COALESCE(SUM(amount), 0) as total
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
        f"""SELECT t.category_name, t.type, t.amount, u.display_name as owner,
                  t.date, t.description
           FROM transactions t
           JOIN users u ON t.user_id = u.id
           WHERE t.user_id IN ({placeholders})
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) BETWEEN ? AND ?
           ORDER BY t.date DESC""",
        (*member_ids, d_from, d_to),
    )
    all_txns = await cursor.fetchall()

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
            f"""SELECT type, COALESCE(SUM(amount), 0) as total
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

    # ── Budgets vs actuals (user's own budgets, cycle-aware) ──
    cursor = await db.execute(
        """SELECT b.category_name, b.budget_amount,
                  COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) AS actual
           FROM budgets b
           LEFT JOIN transactions t ON t.category_id = b.category_id
               AND t.user_id = b.user_id
               AND COALESCE(t.date, LEFT(t.created_at::text, 10)) BETWEEN ? AND ?
           WHERE b.month = ? AND b.user_id = ?
           GROUP BY b.category_name, b.budget_amount""",
        (d_from, d_to, d_from_date.strftime("%Y-%m"), user_id),
    )
    budgets_list = []
    async for r in cursor:
        pct = (r["actual"] / r["budget_amount"] * 100) if r["budget_amount"] > 0 else 0
        remaining = r["budget_amount"] - r["actual"]
        status = "✅" if remaining >= 0 else "🔴"
        budgets_list.append(
            f"• {r['category_name']}: Rp{r['actual']:,} / Rp{r['budget_amount']:,} ({pct:.0f}%) — sisa Rp{remaining:,} {status}"
        )
    budgets = "\n".join(budgets_list) if budgets_list else "Belum ada anggaran"

    # ── Budget health & projection ──
    from app.utils.budget_ai import get_projection

    projection = await get_projection(db, user_id, cycle_start_day, d_from, d_to)
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
        f"""SELECT category_name, type, SUM(amount) as total
           FROM transactions
           WHERE user_id IN ({placeholders})
             AND category_name IN ('Tabungan & Investasi', 'Penarikan Tabungan & Investasi', 'Hasil Investasi', 'Dana Darurat')
           GROUP BY category_name, type""",
        (*member_ids,),
    )
    si_saved = 0
    si_withdrawn = 0
    si_returns = 0
    emergency_bal = 0
    async for r in cursor:
        cat, typ, total = r["category_name"], r["type"], (r["total"] or 0)
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
    hh_where = "ks.user_id = ? OR ks.household_id IN (SELECT household_id FROM household_members WHERE user_id = ?)"
    hh_params = (user_id, user_id)

    cursor = await db.execute(
        f"""SELECT COALESCE(SUM(
            CASE
                WHEN ks.due_date IS NOT NULL AND EXTRACT(DAY FROM CURRENT_DATE) >= ks.due_date THEN
                    COALESCE((
                        SELECT kms.remaining_balance FROM kpr_monthly_schedules kms
                        WHERE kms.simulation_id = ks.id AND kms.month_number = cm.current_month
                    ), ks.total_loan)
                ELSE
                    CASE WHEN cm.current_month <= 1 THEN ks.total_loan
                    ELSE (
                        SELECT kms.remaining_balance FROM kpr_monthly_schedules kms
                        WHERE kms.simulation_id = ks.id AND kms.month_number = cm.current_month - 1
                    ) END
            END
        ), 0) AS total_kpr
        FROM kpr_simulations ks
        CROSS JOIN LATERAL (
            SELECT LEAST(
                (EXTRACT(YEAR FROM CURRENT_DATE) - ks.start_year) * 12
                + (EXTRACT(MONTH FROM CURRENT_DATE) - ks.start_month) + 1,
                ks.tenor_months
            ) AS current_month
        ) cm
        WHERE {hh_where}""",
        hh_params,
    )
    row = await cursor.fetchone()
    total_kpr = int(row["total_kpr"]) if row else 0

    # KPR per-simulation details with owner
    cursor = await db.execute(
        f"""SELECT ks.name, ks.total_loan, ks.interest_type, ks.tenor_months,
                  ks.start_month, ks.start_year, ks.user_id, u.display_name AS owner,
                  CASE WHEN ks.user_id = ? THEN 0 ELSE 1 END AS is_member,
                  COALESCE((SELECT COUNT(*) FROM kpr_extra_payments kep WHERE kep.simulation_id = ks.id), 0) AS extra_payments
           FROM kpr_simulations ks
           JOIN users u ON u.id = ks.user_id
           WHERE {hh_where}
           ORDER BY ks.display_order ASC, ks.created_at DESC""",
        (user_id, user_id, user_id),
    )
    kpr_details = await cursor.fetchall()
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
        f"""SELECT COALESCE(SUM(cct.amount), 0) AS total_txns
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
        f"""SELECT COUNT(*) AS total_active,
                  COALESCE(SUM(cci.monthly_amount * GREATEST(0, cci.total_months - (
                      (EXTRACT(YEAR FROM CURRENT_DATE)::integer * 12 + EXTRACT(MONTH FROM CURRENT_DATE)::integer)
                      - (CAST(SUBSTR(cci.start_month, 1, 4) AS integer) * 12 + CAST(SUBSTR(cci.start_month, 6, 2) AS integer))
                  ))), 0) AS total_installments
           FROM credit_card_installments cci
           JOIN credit_cards cc ON cc.id = cci.card_id
           WHERE ({cc_hh_where})
               AND cci.total_months > (
                   (EXTRACT(YEAR FROM CURRENT_DATE)::integer * 12 + EXTRACT(MONTH FROM CURRENT_DATE)::integer)
                   - (CAST(SUBSTR(cci.start_month, 1, 4) AS integer) * 12 + CAST(SUBSTR(cci.start_month, 6, 2) AS integer))
               )""",
        cc_hh_params,
    )
    row = await cursor.fetchone()
    total_cc_installments = int(row["total_installments"]) if row else 0
    cc_count = row["total_active"] if row else 0

    # CC per-card details with owner
    cursor = await db.execute(
        f"""SELECT cc.name, cc.credit_limit, cc.user_id, u.display_name AS owner,
                  CASE WHEN cc.user_id = ? THEN 0 ELSE 1 END AS is_member
           FROM credit_cards cc
           JOIN users u ON u.id = cc.user_id
           WHERE {cc_hh_where}
           ORDER BY cc.display_order ASC, cc.created_at DESC""",
        (user_id, user_id, user_id),
    )
    cc_details = await cursor.fetchall()

    total_cc = total_cc_txns + total_cc_installments
    total_debt = total_kpr + total_cc

    # Build debt context
    debt_parts = []
    if kpr_count > 0:
        kpr_member_lines = []
        for ow, info in sorted(kpr_member_map.items()):
            types_str = "/".join(sorted(info["types"]))
            kpr_member_lines.append(f"    {ow}: {info['count']} simulasi ({types_str})")
        debt_parts.append(f"• KPR: Rp{total_kpr:,} ({kpr_count} simulasi)")
        debt_parts.extend(kpr_member_lines)
        total_extra = sum(k["extra_payments"] for k in kpr_details)
        if total_extra > 0:
            debt_parts.append(f"    *{total_extra} extra payment telah dilakukan")
    if cc_count > 0:
        cc_member_lines = []
        for c in cc_details:
            label = f"    {c['owner']}: {c['name']}"
            if c["is_member"]:
                label += " (🏠 member)"
            cc_member_lines.append(label)
        debt_parts.append(
            f"• Kartu Kredit: Rp{total_cc:,} (transaksi Rp{total_cc_txns:,} + cicilan Rp{total_cc_installments:,})"
        )
        debt_parts.extend(cc_member_lines)
    if debt_parts:
        debt_context = "\n".join(debt_parts)
        debt_context += f"\n• **Total Utang: Rp{total_debt:,}**"
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
    model_map = {
        "flash": "deepseek-v4-flash",
        "opus": "anthropic/claude-opus-4.7",
    }
    resolved = model_map.get(model, model)

    # Default: OpenCode Go
    api_url = "https://opencode.ai/zen/go/v1/chat/completions"
    api_key = settings.OPENCODE_GO_API_KEY

    if model == "opus":
        if settings.OPENROUTER_API_KEY:
            api_key = settings.OPENROUTER_API_KEY
            api_url = "https://openrouter.ai/api/v1/chat/completions"
        else:
            # No OpenRouter key — fallback to flash via OpenCode
            resolved = "deepseek-v4-flash"
    return resolved, api_url, api_key


async def call_model_stream(
    messages: list, model: str = "deepseek-v4-flash"
) -> AsyncGenerator[str, None]:
    """Call the model API with streaming. Yields token strings as they arrive."""
    resolved, api_url, api_key = await resolve_model(model)

    async with httpx.AsyncClient(timeout=120) as client:
        async with client.stream(
            "POST",
            api_url,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
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
                delta = chunk.get("choices", [{}])[0].get("delta", {})
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

    async with httpx.AsyncClient(timeout=60) as client:
        resp = await client.post(
            api_url,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": resolved,
                "messages": messages,
                "max_tokens": 16384,
                "temperature": 0.7,
            },
        )

    if resp.status_code != 200:
        raise Exception(f"AI API error: {resp.status_code}")

    body = resp.json()
    content = body["choices"][0]["message"]["content"]
    if not content or not content.strip():
        return "Maaf, saya tidak bisa merespons pertanyaan itu. Silakan tanya tentang keuangan Anda."
    return content.strip()


async def build_messages(
    req: AdviseRequest, current_user: dict, db: CursorWrapper
) -> list:
    """Build the full messages array: system -> history -> current question."""
    ctx = await build_context(current_user["id"], db, question=req.question)
    prompt = SYSTEM_PROMPT.format(**ctx)
    history_msgs = [{"role": m.role, "content": m.content} for m in req.history[-10:]]
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
        "INSERT INTO ai_messages (user_id, role, content, status, model) VALUES (?, 'user', ?, 'complete', ?)",
        (current_user["id"], req.question, req.model),
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
        "INSERT INTO ai_messages (user_id, role, content, status, model, parent_message_id) VALUES (?, 'assistant', '', 'processing', ?, ?)",
        (current_user["id"], req.model, user_msg_id),
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

    async def _process_ai():
        try:
            from app.database import get_db_bg

            bg_db = await get_db_bg()
            try:
                # Immediate feedback before context building
                await bg_db.execute(
                    "UPDATE ai_messages SET content = ? WHERE id = ?",
                    ("Mengumpulkan data keuangan...", ai_msg_id),
                )

                advise_req = AdviseRequest(
                    question=req.question, model=req.model, history=req.history
                )
                messages = await build_messages(advise_req, current_user, bg_db)
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
                            "UPDATE ai_messages SET content = ? WHERE id = ?",
                            (full_content, ai_msg_id),
                        )
                        last_flush = full_content

                # Final flush — outside the for loop
                await bg_db.execute(
                    "UPDATE ai_messages SET content = ?, status = 'complete' WHERE id = ?",
                    (full_content, ai_msg_id),
                )
            finally:
                await bg_db.close()
        except Exception as e:
            try:
                from app.database import get_db_bg

                bg_db = await get_db_bg()
                await bg_db.execute(
                    "UPDATE ai_messages SET content = ?, status = 'error' WHERE id = ?",
                    (f"Error: {e}", ai_msg_id),
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
        """SELECT id, role, content, status, model, parent_message_id, created_at
           FROM ai_messages
           WHERE user_id = ? AND status != 'error:hidden'
           ORDER BY created_at ASC""",
        (user_id,),
    )
    rows = await cursor.fetchall()
    return [ChatMessageResponse(**dict(row)) for row in rows]


async def delete_chat_messages(user_id: int, db: CursorWrapper) -> None:
    """Delete all AI chat messages for a user."""
    await db.execute(
        "DELETE FROM ai_messages WHERE user_id = ?",
        (user_id,),
    )


# ── Router helpers (moved from ai_advisor.py for clean separation) ────


def ensure_api_key_configured():
    """Check that the AI API key is configured. Returns None or raises ValueError."""
    if not settings.OPENCODE_GO_API_KEY:
        raise ValueError("AI advisor not configured")


def check_model_access(req_model: str, current_user: dict) -> None:
    """Check model access restrictions. Raises ValueError if access denied."""
    if req_model == "opus" and current_user.get("role") != "admin":
        raise ValueError(
            "Advanced model is only available for the primary account holder"
        )
