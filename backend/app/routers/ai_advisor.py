"""AI Advisor router — thin HTTP adapter.

Business logic (context building, model API calls, chat persistence)
lives in app.services.ai_advisor_service.
"""
import json
import logging

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse

from app.core.config import settings
from app.core.limiter import limiter
from app.core.security import get_current_user
from app.database import get_db
from app.services.ai_advisor_service import (
    AdviseRequest,
    AdviseResponse,
    ChatRequest,
    ChatResponse,
    ChatMessageResponse,
    build_messages,
    call_model,
    call_model_stream,
    start_chat,
    get_chat_messages,
    delete_chat_messages,
)

router = APIRouter(prefix="/ai", tags=["ai"])

logger = logging.getLogger(__name__)


def _check_api_key():
    """Validate that the AI API key is configured. Returns None or raises 500."""
    if not settings.OPENCODE_GO_API_KEY:
        raise HTTPException(status_code=500, detail="AI advisor not configured")


def _check_model_access(req_model: str, current_user: dict):
    """Check model access restrictions. Returns None or raises 403."""
    if req_model == "opus" and current_user["role"] != "admin":
        raise HTTPException(
            status_code=403,
            detail="Advanced model is only available for the primary account holder",
        )


# ── Non-streaming advise ──────────────────────────────────────────────


@router.post("/advise", response_model=AdviseResponse)
@limiter.limit("10/minute")
async def financial_advise(
    request: Request,
    req: AdviseRequest,
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    _check_api_key()
    _check_model_access(req.model, current_user)

    messages = await build_messages(req, current_user, db)
    try:
        answer = await call_model(messages=messages, model=req.model)
    except Exception as e:
        raise HTTPException(status_code=502, detail=str(e))

    return AdviseResponse(answer=answer, model_used=req.model)


# ── Streaming advise ──────────────────────────────────────────────────


@router.post("/advise/stream")
@limiter.limit("10/minute")
async def financial_advise_stream(
    request: Request,
    req: AdviseRequest,
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    _check_api_key()
    _check_model_access(req.model, current_user)

    messages = await build_messages(req, current_user, db)

    async def event_stream():
        async for token in call_model_stream(messages=messages, model=req.model):
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


# ── Background Async Chat (persisted, non-streaming) ──────────────────


@router.post("/chat", response_model=ChatResponse)
@limiter.limit("10/minute")
async def ai_chat(
    request: Request,
    req: ChatRequest,
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    _check_api_key()
    _check_model_access(req.model, current_user)

    user_msg_id, ai_msg_id = await start_chat(req, current_user, db)
    return ChatResponse(user_message_id=user_msg_id, ai_message_id=ai_msg_id)


@router.get("/chat/messages", response_model=list[ChatMessageResponse])
async def chat_messages(
    request: Request,
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    return await get_chat_messages(current_user["id"], db)


@router.delete("/chat/messages", status_code=204)
async def delete_messages(
    request: Request,
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    await delete_chat_messages(current_user["id"], db)
