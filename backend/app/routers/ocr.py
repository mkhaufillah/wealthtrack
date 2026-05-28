from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from pydantic import BaseModel
from typing import Optional
import httpx
import base64
import json
import re

from app.core.config import settings
from app.core.security import get_current_user
from app.database import get_db

router = APIRouter(prefix="/ocr", tags=["ocr"])

# ── Rate limit: max 10 OCR calls per user (stored in-memory per server)
#    Sufficient for personal use; a proper Redis-backed solution can replace later.
import time
_user_ocr_counts: dict[int, list[float]] = {}

def _check_rate_limit(user_id: int):
    now = time.time()
    day_ago = now - 86400
    if user_id not in _user_ocr_counts:
        _user_ocr_counts[user_id] = []
    # Prune old entries
    _user_ocr_counts[user_id] = [t for t in _user_ocr_counts[user_id] if t > day_ago]
    if len(_user_ocr_counts[user_id]) >= 10:
        raise HTTPException(status_code=429, detail="OCR rate limit: max 10/day")
    _user_ocr_counts[user_id].append(now)


class OcrResult(BaseModel):
    amount: Optional[int] = None
    description: Optional[str] = None
    date: Optional[str] = None  # YYYY-MM-DD
    category_name: Optional[str] = None
    type: Optional[str] = None  # "expense" or "income"
    raw_text: str = ""


SYSTEM_PROMPT = """You are a receipt/transaction OCR assistant. Given an image of a receipt, bill, or transaction note, extract structured financial data.

Return ONLY valid JSON with these fields:
{
  "amount": integer (total amount in Rupiah, no decimals),
  "description": "short description of what was purchased",
  "date": "YYYY-MM-DD" (transaction date, use today if not visible),
  "type": "expense" or "income",
  "category_name": "best matching category name (e.g. Food, Transport, Shopping, Bills, Health, Entertainment, Education, Salary, Investment)"
}

If the image is not a receipt/financial document, return {"raw_text": "description of what the image contains"}.
Do NOT include markdown formatting. Return ONLY the JSON object."""


@router.post("/process", response_model=OcrResult)
async def process_ocr(
    file: UploadFile = File(...),
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Process an image through vision AI to extract transaction data."""
    _check_rate_limit(current_user["id"])

    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Only image files are accepted")

    # Read image
    image_bytes = await file.read()
    if len(image_bytes) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Image too large (max 10 MB)")

    # Encode as base64 data URL
    b64 = base64.b64encode(image_bytes).decode()
    mime = file.content_type or "image/jpeg"
    data_url = f"data:{mime};base64,{b64}"

    api_key = settings.OPENCODE_GO_API_KEY
    if not api_key:
        raise HTTPException(status_code=500, detail="OCR not configured (missing API key)")

    try:
        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(
                "https://opencode.ai/zen/go/v1/chat/completions",
                headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
                json={
                    "model": "kimi-k2.6",
                    "messages": [
                        {"role": "system", "content": SYSTEM_PROMPT},
                        {
                            "role": "user",
                            "content": [
                                {"type": "image_url", "image_url": {"url": data_url}},
                                {"type": "text", "text": "Extract transaction data from this image."},
                            ],
                        },
                    ],
                    "max_tokens": 4096,
                },
            )

        if resp.status_code != 200:
            raise HTTPException(status_code=502, detail=f"Vision API error: {resp.status_code}")

        body = resp.json()
        content = body["choices"][0]["message"]["content"].strip()

        # Clean markdown code fences if present
        content = re.sub(r"^```(?:json)?\s*", "", content)
        content = re.sub(r"\s*```$", "", content)

        try:
            parsed = json.loads(content)
        except json.JSONDecodeError:
            return OcrResult(raw_text=content)

        return OcrResult(
            amount=int(parsed["amount"]) if parsed.get("amount") else None,
            description=str(parsed.get("description", "")),
            date=str(parsed.get("date", "")),
            category_name=str(parsed.get("category_name", "")),
            type=str(parsed.get("type", "")),
            raw_text=content,
        )

    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Vision API timed out")
    except httpx.RequestError as e:
        raise HTTPException(status_code=502, detail=f"Vision API request failed: {e}")
