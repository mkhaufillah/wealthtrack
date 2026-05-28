from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Optional, AsyncGenerator
import httpx
import json
import asyncio
from datetime import datetime

from app.database import get_db
from app.core.config import settings
from app.core.security import get_current_user

router = APIRouter(prefix="/ai", tags=["ai"])


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


SYSTEM_PROMPT = """Kamu adalah asisten keuangan pribadi yang membantu {user_name} mengelola keuangan keluarga.
Percakapan ini bersifat personal — hanya {user_name} yang sedang berbicara denganmu.
Jangan panggil atau sebut nama anggota keluarga lain dalam sapaan.

Data Keuangan Bulan {month}:
- Saldo: Rp{balance:,}
- Total Pemasukan: Rp{income:,}
- Total Pengeluaran: Rp{expense:,}
- Pengeluaran per kategori: {category_breakdown}

Tren 6 Bulan Terakhir: {trend}

Anggaran: {budgets}

Anggota Keluarga (konteks data): {members}

Berikan saran yang personal, relevan, dan actionable berdasarkan data di atas.
Gunakan bahasa Indonesia yang natural.
Jika ada data yang relevan, sertakan angka spesifik.
Jika pengguna hanya menyapa (misal "halo", "hi", "pagi", "selamat siang"), balaslah dengan ramah dan tawarkan bantuan — jangan sebut nama anggota keluarga lain.
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


async def _resolve_model(model: str) -> tuple[str, str, str]:
    """Return (resolved_model, api_url, api_key) for the given model."""
    model_map = {
        "flash": "deepseek-v4-flash",
        "opus": "anthropic/claude-opus-4.7",
    }
    resolved = model_map.get(model, model)
    api_url = "https://opencode.ai/zen/go/v1/chat/completions"
    api_key = settings.OPENCODE_GO_API_KEY

    if model == "opus":
        if settings.OPENROUTER_API_KEY:
            api_key = settings.OPENROUTER_API_KEY
            api_url = "https://openrouter.ai/api/v1/chat/completions"
        else:
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


async def _build_messages(req: AdviseRequest, current_user: dict, db) -> list:
    """Build the full messages array: system → history → current question."""
    ctx = await _build_context(current_user["id"], db)
    prompt = SYSTEM_PROMPT.format(**ctx)
    history_msgs = [{"role": m.role, "content": m.content} for m in req.history[-10:]]
    return [
        {"role": "system", "content": prompt},
        *history_msgs,
        {"role": "user", "content": req.question},
    ]


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

    messages = await _build_messages(req, current_user, db)
    answer = await _call_model(messages=messages, api_key=api_key, model=req.model)

    return AdviseResponse(answer=answer, model_used=req.model)


@router.post("/advise/stream")
async def financial_advise_stream(
    req: AdviseRequest,
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    api_key = settings.OPENCODE_GO_API_KEY
    if not api_key:
        raise HTTPException(status_code=500, detail="AI advisor not configured")

    if req.model == "opus" and current_user["id"] != 1:
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
