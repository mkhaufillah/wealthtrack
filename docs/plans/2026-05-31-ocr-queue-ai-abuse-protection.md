# OCR Queue & AI Advisor Abuse Protection

> Implementation date: 2026-05-31

## Problem

### 1. OCR Burst Rate Limiting
Uploading multiple invoices quickly caused 429 errors from OpenCode Go API. The existing retry (3 attempts, fixed backoff) wasn't enough because concurrent requests hit the burst limit simultaneously.

### 2. AI Advisor Double-Send Cost
`_isLoading` was reset to `false` as soon as the POST `/ai/chat` returned, but the AI was still processing in the background (polling). Users could send a second message → trigger a second AI call → double cost.

## Solution

### OCR — 2-Layer Protection

```python
# Layer 1: Per-user queue (database check)
cursor = await db.execute(
    "SELECT COUNT(*) FROM ocr_jobs WHERE user_id = ? AND status = 'processing'",
    (user_id,),
)
# → 429 if count > 0

# Layer 2: System semaphore
_ocr_semaphore = asyncio.Semaphore(2)  # module-level

# In background task:
async with _ocr_semaphore:
    # Vision API call with 5 retries + jitter
```

### AI Advisor — Extended Loading State

| Before | After |
|--------|-------|
| `_isLoading = false` right after POST returns | `_isLoading` stays `true` until polling detects completion |
| TextField always enabled | `enabled: !_isLoading` |
| Button disabled only during POST | Button + TextField disabled until AI finishes |
| On session resume with processing message, input active | `_isLoading = true` + polling resumes automatically |

## Files Changed

| File | Change |
|------|--------|
| `backend/app/routers/ocr.py` | Per-user DB check, `asyncio.Semaphore(2)`, jittered retry 5 attempts |
| `backend/app/routers/transactions.py` | `DELETE` ocr_jobs instead of `SET NULL` |
| `backend/app/routers/auth.py` | `DELETE` ocr_jobs on account deletion |
| `mobile/lib/features/ai/ui/ai_advisor_screen.dart` | `_isLoading` stay true until polling done, `enabled: !_isLoading`, `_isLoading = true` on resume |
| `mobile/lib/features/transactions/ui/transaction_list_screen.dart` | Immediate OCR load, reload on ANY completion (`next < previous`) |
| `mobile/lib/features/home/ui/home_screen.dart` | Same OCR fixes |
| `mobile/lib/features/transactions/ui/add_transaction_screen.dart` | Trigger OCR load before navigation |

## Verification

- [x] Backend 189 tests pass
- [x] Flutter 250 tests pass
- [x] `DELETE FROM ocr_jobs` works (no FK error)
- [x] Per-user queue: upload 2nd image while 1st is processing → 429
- [x] System semaphore: 3 concurrent users → 2 process, 1 waits
- [x] AI Advisor: send → input disabled → response done → input re-enabled
- [x] AI Advisor: error → input re-enabled + retry available
- [x] AI Advisor: open screen with processing message → input locked + polling
