import logging
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Optional, AsyncGenerator
import httpx
import json
import asyncio
from datetime import datetime, timezone, timedelta

from app.database import get_db, CursorWrapper, background_tasks
from app.core.config import settings
from app.core.security import get_current_user
from app.core.limiter import limiter
from app.services.web_search import _should_search, search_web, format_search_results

router = APIRouter(prefix="/ai", tags=["ai"])

logger = logging.getLogger(__name__)


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


async def _get_household_id(user_id: int, db) -> Optional[int]:
    """Get the household ID for a user, or None if not in a household."""
    cursor = await db.execute(
        "SELECT household_id FROM household_members WHERE user_id = ?",
        (user_id,),
    )
    row = await cursor.fetchone()
    return row["household_id"] if row else None


async def _build_context(user_id: int, db, question: str = "") -> dict:
    """Build financial context for the AI advisor prompt.

    Includes household-level data (all members) when the user is in a household.
    """
    # User info
    cursor = await db.execute("SELECT display_name FROM users WHERE id = ?", (user_id,))
    user = await cursor.fetchone()
    user_name = user["display_name"] if user else f"User #{user_id}"

    # Household info
    household_id = await _get_household_id(user_id, db)

    # Household members
    cursor = await db.execute(
        """SELECT u.display_name, hm.role
           FROM household_members hm
           JOIN users u ON hm.user_id = u.id
           WHERE hm.household_id = (SELECT household_id FROM household_members WHERE user_id = ?)""",
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
        # All household members' user IDs
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
        f"""SELECT t.category_name, t.type, t.amount, u.display_name as owner, t.date, t.description
           FROM transactions t
           JOIN users u ON t.user_id = u.id
           WHERE t.user_id IN ({placeholders})
             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) BETWEEN ? AND ?
           ORDER BY t.date DESC""",
        (*member_ids, d_from, d_to),
    )
    all_txns = await cursor.fetchall()

    # Category summary
    cat_map = {}  # category_key -> {total, count, members: set}
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
    cat_stats = {}  # category_key -> {"avg": int, "top3": list}
    for t in all_txns:
        key = f"{t['category_name']} ({t['type']})"
        if key not in cat_stats:
            cat_stats[key] = {"amounts": []}
        cat_stats[key]["amounts"].append(t["amount"])

    cat_extra_parts = []
    for cat_name in sorted(cat_stats.keys(), key=lambda k: -sum(cat_stats[k]["amounts"])):
        amounts = sorted(cat_stats[cat_name]["amounts"], reverse=True)
        avg_val = sum(amounts) // len(amounts)
        top3_str = ", ".join(f"Rp{a:,}" for a in amounts[:3])
        cat_extra_parts.append(f"• {cat_name}: rata-rata Rp{avg_val:,}/transaksi | termahal: {top3_str}")

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
    from calendar import monthrange
    for i in range(5, -1, -1):
        # Navigate to the month that is i months ago
        y = now.year
        m = now.month - i
        while m < 1:
            m += 12
            y -= 1
        # Use the 15th of that month as the anchor date for get_cycle_range
        from datetime import date
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
    projection = await get_projection(
        db, user_id, cycle_start_day, d_from, d_to
    )
    proj_lines = []
    for cat in projection["categories"]:
        icon_map = {"healthy": "✅", "warning": "⚠️", "at_risk": "🔴", "exhausted": "❌"}
        label_map = {"healthy": "Aman", "warning": "Hati-hati", "at_risk": "Berisiko", "exhausted": "Habis"}
        icon = icon_map.get(cat["health"], "❓")
        label = label_map.get(cat["health"], "")
        proj_lines.append(
            f"• {cat['category_name']}: Rp{cat['actual_spent']:,} / Rp{cat['budget_amount']:,} "
            f"({cat['percentage']:.0f}%) {icon} {label}"
        )
        if cat["health"] in ("at_risk", "warning") and cat["projected_end"] > cat["budget_amount"]:
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
    si_saved = 0        # expense → uang masuk (saving)
    si_withdrawn = 0    # income Penarikan → uang ditarik
    si_returns = 0      # income Hasil Investasi → return
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
            # Legacy: old income tx still use "Tabungan & Investasi" name
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
    if question and _should_search(question):
        results = await search_web(question)
        if results:
            search_text = format_search_results(results)

    # ── Debt summary ──
    cursor = await db.execute(
        """SELECT COALESCE(SUM(
            CASE WHEN cm.current_month <= 1 THEN ks.total_loan
            ELSE (
                SELECT kms.remaining_balance
                FROM kpr_monthly_schedules kms
                WHERE kms.simulation_id = ks.id
                AND kms.month_number = cm.current_month - 1
            ) END
        ), 0) AS total_kpr
        FROM kpr_simulations ks
        CROSS JOIN LATERAL (
            SELECT LEAST(
                (EXTRACT(YEAR FROM CURRENT_DATE) - ks.start_year) * 12
                + (EXTRACT(MONTH FROM CURRENT_DATE) - ks.start_month) + 1,
                ks.tenor_months
            ) AS current_month
        ) cm
        WHERE ks.user_id = ?""",
        (user_id,),
    )
    row = await cursor.fetchone()
    total_kpr = int(row["total_kpr"]) if row else 0

    cursor = await db.execute(
        "SELECT COUNT(*) AS cnt FROM kpr_simulations WHERE user_id = ?",
        (user_id,),
    )
    row = await cursor.fetchone()
    kpr_count = row["cnt"] if row else 0

    cursor = await db.execute(
        """SELECT
               COALESCE(SUM(cct.amount), 0) AS total_txns
           FROM credit_card_transactions cct
           JOIN credit_cards cc ON cc.id = cct.card_id
           WHERE cc.user_id = ? AND cct.is_installment = 0""",
        (user_id,),
    )
    row = await cursor.fetchone()
    total_cc_txns = int(row["total_txns"]) if row else 0

    cursor = await db.execute(
        """SELECT COUNT(*) AS total_active,
                  COALESCE(SUM(cci.monthly_amount * cci.remaining_months), 0) AS total_installments
           FROM credit_card_installments cci
           JOIN credit_cards cc ON cc.id = cci.card_id
           WHERE cc.user_id = ? AND cci.remaining_months > 0""",
        (user_id,),
    )
    row = await cursor.fetchone()
    total_cc_installments = int(row["total_installments"]) if row else 0
    cc_count = row["total_active"] if row else 0
    total_cc = total_cc_txns + total_cc_installments
    total_debt = total_kpr + total_cc

    debt_parts = []
    if kpr_count > 0:
        debt_parts.append(f"• KPR: Rp{total_kpr:,} ({kpr_count} simulasi)")
    if cc_count > 0:
        debt_parts.append(f"• Kartu Kredit: Rp{total_cc:,} (transaksi Rp{total_cc_txns:,} + cicilan Rp{total_cc_installments:,})")
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


async def _resolve_model(model: str) -> tuple[str, str, str]:
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


async def _call_model_stream(
    messages: list, model: str = "deepseek-v4-flash"
) -> AsyncGenerator[str, None]:
    """Call the model API with streaming. Yields token strings as they arrive."""
    resolved, api_url, api_key = await _resolve_model(model)

    async with httpx.AsyncClient(timeout=120) as client:
        async with client.stream(
            "POST",
            api_url,
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
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


async def _call_model(messages: list, model: str = "deepseek-v4-flash") -> str:
    """Call the model API without streaming. Returns full response text."""
    resolved, api_url, api_key = await _resolve_model(model)

    async with httpx.AsyncClient(timeout=60) as client:
        resp = await client.post(
            api_url,
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            json={
                "model": resolved,
                "messages": messages,
                "max_tokens": 16384,
                "temperature": 0.7,
            },
        )

    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail=f"AI API error: {resp.status_code}")

    body = resp.json()
    content = body["choices"][0]["message"]["content"]
    if not content or not content.strip():
        return "Maaf, saya tidak bisa merespons pertanyaan itu. Silakan tanya tentang keuangan Anda."
    return content.strip()


async def _build_messages(req: AdviseRequest, current_user: dict, db) -> list:
    """Build the full messages array: system → history → current question."""
    ctx = await _build_context(current_user["id"], db, question=req.question)
    prompt = SYSTEM_PROMPT.format(**ctx)
    history_msgs = [{"role": m.role, "content": m.content} for m in req.history[-10:]]
    return [
        {"role": "system", "content": prompt},
        *history_msgs,
        {"role": "user", "content": req.question},
    ]


@router.post("/advise", response_model=AdviseResponse)
@limiter.limit("10/minute")
async def financial_advise(
    request: Request,
    req: AdviseRequest,
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    api_key = settings.OPENCODE_GO_API_KEY
    if not api_key:
        raise HTTPException(status_code=500, detail="AI advisor not configured")

    # User-level access control
    if req.model == "opus" and current_user["role"] != "admin":
        raise HTTPException(
            status_code=403,
            detail="Advanced model is only available for the primary account holder",
        )

    messages = await _build_messages(req, current_user, db)
    answer = await _call_model(messages=messages, model=req.model)

    return AdviseResponse(answer=answer, model_used=req.model)


@router.post("/advise/stream")
@limiter.limit("10/minute")
async def financial_advise_stream(
    request: Request,
    req: AdviseRequest,
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    api_key = settings.OPENCODE_GO_API_KEY
    if not api_key:
        raise HTTPException(status_code=500, detail="AI advisor not configured")

    if req.model == "opus" and current_user["role"] != "admin":
        raise HTTPException(
            status_code=403,
            detail="Advanced model is only available for the primary account holder",
        )

    messages = await _build_messages(req, current_user, db)

    async def event_stream():
        async for token in _call_model_stream(messages=messages, model=req.model):
            if token.startswith("[ERROR:"):
                yield f"data: {json.dumps({'error': token[7:-1]})}\n\n"
                return
            yield f"data: {json.dumps({'token': token})}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


# ── Background Async Chat (persisted, non-streaming) ──


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


@router.post("/chat", response_model=ChatResponse)
@limiter.limit("10/minute")
async def ai_chat(
    request: Request,
    req: ChatRequest,
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    api_key = settings.OPENCODE_GO_API_KEY
    if not api_key:
        raise HTTPException(status_code=500, detail="AI advisor not configured")

    if req.model == "opus" and current_user["role"] != "admin":
        raise HTTPException(
            status_code=403,
            detail="Advanced model is only available for the primary account holder",
        )

    # 1. Save user message
    cursor = await db.execute(
        "INSERT INTO ai_messages (user_id, role, content, status, model) VALUES (?, 'user', ?, 'complete', ?)",
        (current_user["id"], req.question, req.model),
    )
    user_msg_id = cursor.lastrowid
    # auto-committed

    # 2. If retry: mark old AI messages with this parent as 'error:hidden'
    if req.retry_parent_id:
        await db.execute(
            "UPDATE ai_messages SET status = 'error:hidden' WHERE parent_message_id = ? AND role = 'assistant'",
            (req.retry_parent_id,),
        )
    # auto-committed

    # 3. Save processing placeholder for AI, linked to user message via parent_message_id
    cursor = await db.execute(
        "INSERT INTO ai_messages (user_id, role, content, status, model, parent_message_id) VALUES (?, 'assistant', '', 'processing', ?, ?)",
        (current_user["id"], req.model, user_msg_id),
    )
    ai_msg_id = cursor.lastrowid
    # auto-committed

    # 4. Start background task — streams tokens progressively to DB
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

                messages = await _build_messages(
                    AdviseRequest(question=req.question, model=req.model, history=req.history),
                    current_user,
                    bg_db,
                )
                full_content = ""
                last_flush = ""
                async for token in _call_model_stream(messages=messages, model=req.model):
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
                logger.warning("Failed to update AI message error status: %s", db_err)

    task = asyncio.create_task(_process_ai())
    background_tasks.add(task)
    task.add_done_callback(background_tasks.discard)

    return ChatResponse(user_message_id=user_msg_id, ai_message_id=ai_msg_id)


@router.get("/chat/messages", response_model=list[ChatMessageResponse])
async def get_chat_messages(
    request: Request,
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    cursor = await db.execute(
        """SELECT id, role, content, status, model, parent_message_id, created_at
           FROM ai_messages
           WHERE user_id = ? AND status != 'error:hidden'
           ORDER BY created_at ASC""",
        (current_user["id"],),
    )
    rows = await cursor.fetchall()
    return [dict(row) for row in rows]


@router.delete("/chat/messages", status_code=204)
async def delete_chat_messages(
    request: Request,
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Delete all AI chat messages for the current user."""
    await db.execute(
        "DELETE FROM ai_messages WHERE user_id = ?",
        (current_user["id"],),
    )
