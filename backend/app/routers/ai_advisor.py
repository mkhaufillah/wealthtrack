from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Optional
import httpx
import json
from datetime import datetime

from app.database import get_db
from app.core.config import settings
from app.core.security import get_current_user

router = APIRouter(prefix="/ai", tags=["ai"])


class AdviseRequest(BaseModel):
    question: str
    model: str = "flash"  # "flash" | "opus"


class AdviseResponse(BaseModel):
    answer: str
    model_used: str


SYSTEM_PROMPT = """Kamu adalah asisten keuangan pribadi yang membantu {user_name} mengelola keuangan rumah tangga.

Data Keuangan Bulan {month}:
- Saldo: Rp{balance:,}
- Total Pemasukan: Rp{income:,}
- Total Pengeluaran: Rp{expense:,}
- Pengeluaran per kategori: {category_breakdown}

Tren 6 Bulan Terakhir: {trend}

Anggaran: {budgets}

Anggota Household: {members}

Berikan saran yang personal, relevan, dan actionable berdasarkan data di atas.
Gunakan bahasa Indonesia yang natural.
Sertakan angka spesifik dari data yang tersedia.
Jika ditanya di luar topik keuangan, arahkan kembali ke pengelolaan keuangan.
Jangan menyebutkan bahwa Anda adalah AI — cukup beri saran sebagai asisten keuangan."""


async def _build_context(user_id: int, db) -> dict:
    # User info
    cursor = await db.execute("SELECT display_name FROM users WHERE id = ?", (user_id,))
    user = await cursor.fetchone()
    user_name = user["display_name"] if user else f"User #{user_id}"

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

    # Current month summary
    now = datetime.now()
    month = now.strftime("%Y-%m")
    month_display = now.strftime("%B %Y")
    d_from = f"{month}-01"
    d_to = f"{month}-31"

    cursor = await db.execute(
        """SELECT type, COALESCE(SUM(amount), 0) as total
           FROM transactions WHERE user_id = ? AND COALESCE(date, substr(created_at,1,10)) BETWEEN ? AND ?
           GROUP BY type""",
        (user_id, d_from, d_to),
    )
    income = 0
    expense = 0
    async for r in cursor:
        if r["type"] == "income":
            income = r["total"]
        else:
            expense = r["total"]
    balance = income - expense

    # Category breakdown
    cursor = await db.execute(
        """SELECT category_name, SUM(amount) as total
           FROM transactions WHERE user_id = ? AND type = 'expense'
             AND COALESCE(date, substr(created_at,1,10)) BETWEEN ? AND ?
           GROUP BY category_name ORDER BY total DESC LIMIT 5""",
        (user_id, d_from, d_to),
    )
    cat_parts = []
    async for r in cursor:
        cat_parts.append(f"{r['category_name']}: Rp{r['total']:,}")
    cat_breakdown = ", ".join(cat_parts) or "Belum ada"

    # 6-month trend
    from calendar import monthrange
    trend_parts = []
    for i in range(5, -1, -1):
        y = now.year
        m = now.month - i
        while m < 1:
            m += 12
            y -= 1
        m_str = f"{y}-{m:02d}"
        _, days = monthrange(y, m)
        cursor = await db.execute(
            """SELECT type, COALESCE(SUM(amount), 0) as total
               FROM transactions WHERE user_id = ? AND COALESCE(date, substr(created_at,1,10)) BETWEEN ? AND ?
               GROUP BY type""",
            (user_id, f"{m_str}-01", f"{m_str}-{days}"),
        )
        inc = 0
        exp = 0
        async for r in cursor:
            if r["type"] == "income":
                inc = r["total"]
            else:
                exp = r["total"]
        trend_parts.append(f"{m_str}: I=Rp{inc:,}, E=Rp{exp:,}")
    trend = " | ".join(trend_parts)

    # Budgets vs actuals
    cursor = await db.execute(
        """SELECT b.category_name, b.budget_amount,
                  COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) AS actual
           FROM budgets b
           LEFT JOIN transactions t ON t.category_id = b.category_id
               AND t.user_id = b.user_id
               AND COALESCE(t.date, substr(t.created_at,1,10)) BETWEEN ? AND ?
           WHERE b.month = ? AND b.user_id = ?
           GROUP BY b.category_name, b.budget_amount""",
        (d_from, d_to, month, user_id),
    )
    budgets_list = []
    async for r in cursor:
        pct = (r["actual"] / r["budget_amount"] * 100) if r["budget_amount"] > 0 else 0
        budgets_list.append(f"{r['category_name']}: Rp{r['actual']:,} / Rp{r['budget_amount']:,} ({pct:.0f}%)")
    budgets = "\n".join(budgets_list) if budgets_list else "Belum ada anggaran"

    return {
        "user_name": user_name,
        "month": month_display,
        "income": income,
        "expense": expense,
        "balance": balance,
        "category_breakdown": cat_breakdown,
        "trend": trend,
        "budgets": budgets,
        "members": members,
    }


async def _call_model(messages: list, api_key: str, model: str = "deepseek-v4-flash") -> str:
    model_map = {
        "flash": "deepseek-v4-flash",
        "opus": "anthropic/claude-opus-4.7",
    }
    resolved = model_map.get(model, model)

    # OpenCode Go for flash/light models
    api_url = "https://opencode.ai/zen/go/v1/chat/completions"

    # OpenRouter for premium models
    if model == "opus":
        from app.core.config import settings as cfg
        if cfg.OPENROUTER_API_KEY:
            api_key = cfg.OPENROUTER_API_KEY
            api_url = "https://openrouter.ai/api/v1/chat/completions"
        else:
            # Downgrade to flash if no OpenRouter key
            resolved = "deepseek-v4-flash"

    async with httpx.AsyncClient(timeout=60) as client:
        resp = await client.post(
            api_url,
            headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
            json={
                "model": resolved,
                "messages": messages,
                "max_tokens": 1024,
                "temperature": 0.7,
            },
        )

    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail=f"AI API error: {resp.status_code}")

    body = resp.json()
    return body["choices"][0]["message"]["content"].strip()


@router.post("/advise", response_model=AdviseResponse)
async def financial_advise(
    req: AdviseRequest,
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    api_key = settings.OPENCODE_GO_API_KEY
    if not api_key:
        raise HTTPException(status_code=500, detail="AI advisor not configured")

    # User-level access control
    if req.model == "opus" and current_user["id"] != 1:
        raise HTTPException(
            status_code=403,
            detail="Advanced model is only available for the primary account holder",
        )

    ctx = await _build_context(current_user["id"], db)
    prompt = SYSTEM_PROMPT.format(**ctx)
    full_prompt = f"{prompt}\n\nPertanyaan: {req.question}"

    answer = await _call_model(
        messages=[
            {"role": "system", "content": prompt},
            {"role": "user", "content": req.question},
        ],
        api_key=api_key,
        model=req.model,
    )

    return AdviseResponse(answer=answer, model_used=req.model)
