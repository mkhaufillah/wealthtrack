# OCR Receipt Scanner

**Feature added:** 2026-05-28
**See also:** [P4 Plan](08-p4-plan.md) · [Flutter Mobile](05-flutter-mobile.md) · [Improvement Plan](15-improvement-plan-ai-ocr.md)

---

## Overview

OCR (Optical Character Recognition) extracts structured transaction data from receipt/bill images using a vision AI model. The feature is embedded in the Add Transaction screen — no separate route.

| Aspect | Detail |
|--------|--------|
| **Trigger** | "Scan Receipt" button in Add Transaction form |
| **Image source** | Camera (take photo) or Gallery (pick existing) |
| **Vision model** | `kimi-k2.5` via OpenCode Go API |
| **Rate limit** | 10 scans per day per user (in-memory) |
| **Per-user queue** | Max 1 active job per user — subsequent uploads return 429 |
| **System semaphore** | Max 2 concurrent Vision API calls across all users (`asyncio.Semaphore(2)`) |
| **Retry** | 5 attempts with jittered exponential backoff (1s×jitter → 8s×jitter, random 0.5-1.5) |
| **Image max size** | 10 MB input (auto-compressed to ~300 KB JPEG) |

---

## Architecture

```
┌──────────────────────┐     image (multipart)      ┌──────────────────┐
│  AddTransaction      │ ───────────────────────►   │  Backend         │
│  AddTransaction      │                             │  /api/v1/ocr     │
│  Screen (Flutter)    │                             │  /process        │
│                      │ ◄──── OcrResult (JSON) ──  │                  │
│  Camera/Gallery      │                             │  validate        │
│  pickImage()         │                             │  → MIME check    │
│  _scanReceipt()      │                             │  → magic bytes   │
│  _buildScanOverlay() │                             │  → size check    │
└──────────────────────┘                             │  → compress      │
                                                     │    (1200px/JPG)  │
                                                     │  → category DB   │
                                                     │  → vision API    │
                                                     └──────────────────┘
```

### Flow

1. User taps "Scan Receipt" button → bottom sheet with "Take Photo" / "Choose from Gallery"
2. User picks image source → `ImagePicker.pickImage()` (quality 70, maxWidth 1920)
3. Screen shows loading overlay (**spinner + "Processing your receipt..."**)
4. Image uploaded as multipart to `POST /api/v1/ocr/process`
5. Backend validates:
   - MIME type is one of: `image/jpeg`, `image/png`, `image/webp`, `image/heic`, `image/heif`
   - Magic bytes match JPEG/PNG/WebP header
   - File size ≤ 10 MB
6. Image auto-compressed:
   - Resized to max **1200px** on the longest side (LANCZOS)
   - Converted to **JPEG quality 85** (RGB, discards alpha)
   - Output size: ~200–500 KB (down from up to 10 MB)
7. Backend loads categories from PostgreSQL → injects them into the vision AI prompt
8. Vision AI (`kimi-k2.5`) processes the image → returns structured JSON
9. Response fields populate the form: amount, description, date, type, category, note
10. User reviews and edits before saving

---

## Implementation

### File: `backend/app/routers/ocr.py`

Single endpoint `POST /ocr/process`:

```python
@router.post("/process", response_model=OcrResult)
async def process_ocr(file: UploadFile = File(...), ...):
```

#### Image Validation

Two layers:

**MIME whitelist:**
```python
ALLOWED_MIME = {"image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"}
```

**Magic byte check** (prevents MIME spoofing):
```python
IMAGE_MAGIC = {
    b'\xff\xd8\xff': "JPEG",
    b'\x89PNG\r\n\x1a\n': "PNG",
    b'RIFF': "WEBP",
}
```

#### Category Validation from Database

Categories are loaded from PostgreSQL and injected into the vision AI prompt as valid options:
```python
Kategori Expense: Makanan & Minuman, Transportasi & Bensin, ...
Kategori Income: Gaji, Freelance, ...
```

The AI is instructed to pick EXACTLY from this list and match by type (expense categories cannot be used for income and vice versa).

#### Response Model

```python
class OcrResult(BaseModel):
    amount: Optional[int] = None
    description: Optional[str] = None
    date: Optional[str] = None        # YYYY-MM-DD
    category_name: Optional[str] = None
    type: Optional[str] = None        # "expense" or "income"
    note: Optional[str] = None        # Extra details (store, payment method, etc.)
    raw_text: str = ""                # Fallback when JSON parsing fails
```

---

### File: `mobile/lib/features/transactions/ui/add_transaction_screen.dart`

OCR logic is in the `_scanReceipt()` method (lines 83-166).

#### Background Processing Flow

OCR scanning utilizes a background processing architecture:

1. **Upload:** User selects an image source (Camera/Gallery) and it is uploaded to `/ocr/process-and-save`.
2. **Background Polling:** The app clears any previous OCR error banner and triggers `ocrPendingCountProvider` to poll for status.
3. **Navigation:** The user is immediately navigated back to the `/transactions` screen.
4. **Auto-Save:** The transaction is saved directly to the database by the backend upon successful processing, without requiring the user to wait and submit the form manually.

*Note: The `_buildScanOverlay()` method and `_isScanning` state (shown below) remain in the codebase as a legacy/fallback structure, but are superseded by the background flow.*

```dart
  Widget _buildScanOverlay() {
    return AbsorbPointer(
      child: Container(
        color: AppColors.textPrimary,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48, height: 48,
                child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.surface),
              ),
              const SizedBox(height: 20),
              const Text(
                'Processing your receipt...',
                style: TextStyle(color: AppColors.surface, fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'This may take a few seconds',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
```

---

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Non-image file | 400: "Unsupported image format" |
| Corrupted image | 400: "Invalid image" (magic byte check fails) |
| File > 10 MB | 400: "Image too large" |
| API key missing | 500: "OCR not configured" |
| Vision API timeout | 504: "Vision API timed out" |
| Vision API error | 502: "Vision API error: {status}" |
| Rate limit exceeded (10/day) | 429: "OCR rate limit: max 10/day" |
| Per-user queue busy | 429: "You already have an OCR job being processed..." |
| System semaphore full | Internal queue — retries automatically when slot opens |
| Non-receipt image | `raw_text` populated with AI description, structured fields remain null |
| Malformed JSON from API | `raw_text` populated with raw response text |

---

## Files

| File | Role |
|------|------|
| `backend/app/routers/ocr.py` | OCR endpoint, image validation, category DB integration |
| `mobile/lib/features/transactions/ui/add_transaction_screen.dart` | Camera/gallery integration, loading overlay, form population |
| `backend/tests/test_ocr.py` | 11 test cases covering auth, validation, parsing, errors, rate limiting |
| `mobile/test/features/add_transaction_ocr_test.dart` | Flutter widget tests for scan bottom sheet UI |

---

## Background Processing Error Banner

When OCR auto-save is used (`POST /api/v1/ocr/process-and-save`), errors are not thrown inline — instead, the backend stores the failure status and the Flutter app polls for status via `GET /api/v1/ocr/pending-count`.

### Error Display

The Home and Transactions screens show a sticky error banner (`ocr_provider.dart`) when a background OCR job fails. The banner persists until the user explicitly dismisses it by tapping the close (×) button.

### Dismiss Behavior

- **Job ID fingerprinting:** Each OCR job has a unique ID. When dismissed, the `failed_job_id` is fingerprinted (not the error text). This naturally differentiates old vs new failures — a new OCR job that fails with the same error text WILL still show because it has a different job ID.
- **Persistent across app restart:** Dismissed `failed_job_id` is saved to `SecureStorage` (`key: 'ocr_dismissed_job_id'`). App restart retains the dismissal.
- **New scan clears error display:** When user starts a new OCR scan, the visible error banner is cleared immediately (`clearError()`), but the dismissed job ID fingerprint is NOT reset. The old error stays suppressed while the new job is processing.
- **Backend expiry:** The backend only returns `has_failure: true` for failed jobs created within the last 60 seconds (`created_at > datetime('now', '-60 seconds')`). After 60 seconds, the error banner naturally stops appearing.

### Error Text

All background OCR errors use a unified message: `'OCR failed. Please try again with a clearer photo.'` — no raw technical messages (Vision API errors, JSON parse errors, etc.) are exposed to the user.
