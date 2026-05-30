# Improvement Plan — AI Advisor & OCR

**Status:** ✅ Phase 1 completed 2026-05-30
**Last updated:** 2026-05-30

---

## Overview

This plan covers improvements to two P4/P5 features — AI Financial Advisor and OCR Scanner — across backend, mobile, testing, and docs layers. Prioritization based on impact vs effort.

---

## Legend

| Prio | Meaning |
|------|---------|
| P0 | Bug — broken in production |
| P1 | Major UX/quality gap — users hit it regularly |
| P2 | Quality of life — noticeable but not blocking |
| P3 | Nice to have — polish / internals |

---

## Part 1: AI Financial Advisor

### Priority Map

| # | Area | Description | Prio | Effort | Layer |
|---|------|-------------|------|--------|-------|
| 1.1 | Backend | **`current_user["role"]` KeyError crash** — `get_current_user()` returns `{id, username}` only, but `ai_advisor.py:329,353` checks `current_user["role"]`. Opus model toggle crashes at runtime for non-admin users. | **P0** | ~10 min | Backend |
| 1.2 | Backend | **Duplicated model resolution logic** — `_call_model()` and `_resolve_model()` + `_call_model_stream()` maintain independent copies of the same API key/URL mapping. One gets out of sync, the other breaks. | **P2** | ~20 min | Backend |
| 1.3 | Backend | **Hardcoded SYSTEM_PROMPT** — 28-line prompt embedded in `ai_advisor.py`. No prompt versioning, no environment-specific overrides, no way to A/B test. | **P2** | ~30 min | Backend |
| 1.4 | Backend | **6-month trend is calendar-month based, not cycle-aware** — `_build_context()` calculates trends using `monthrange()` calendar months. If user has cycle_start_day=17, trend data doesn't align with cycle-based summaries elsewhere. | **P1** | ~30 min | Backend |
| 1.5 | Backend | **Hardcoded history limit** — `req.history[-10:]` at line 308 instead of using a configurable limit. | **P3** | ~5 min | Backend |
| 1.6 | Backend | **No context caching** — Every request re-queries DB (balance, trends, budgets, cycle range). For consecutive questions within the same session, this is wasteful. | **P3** | ~1 hr | Backend |
| 1.7 | Mobile | **No dedicated Riverpod provider** — Chat state (`_messages`, `_isLoading`, `_useAdvancedModel`) is inline in `AiAdvisorScreen` as `setState`. No separation of concerns, can't test send flow independently. | **P1** | ~1 hr | Mobile |
| 1.8 | Mobile | **Hardcoded user id == 1 for advanced model** — `ref.watch(authProvider).user?.id == 1` instead of checking backend response. Broke for any user who isn't Filla. | **P1** | ~10 min | Mobile |
| 1.9 | Mobile | **No retry on stream failure** — Failed streaming call shows an error message and stops. No "retry" button or auto-retry. | **P2** | ~20 min | Mobile |
| 1.10 | Mobile | **`LocalChatStorage` is not a true singleton** — Each screen creates `LocalChatStorage()` instance. `_loaded` flag is per-instance, causing re-reads from disk. | **P2** | ~15 min | Mobile |
| 1.11 | Mobile | **No proper typing indicator** — Shows static "typing..." text instead of animated dots or shimmer. | **P3** | ~20 min | Mobile |
| 1.12 | Test | **Missing role-based access test** — No test that non-admin getting 403 for opus model. | **P1** | ~10 min | Test |
| 1.13 | Test | **Missing web search context test** — No test verifying web results are injected into the system prompt. | **P2** | ~15 min | Test |
| 1.14 | Test | **Mobile send flow untested** — Tests only check UI elements exist, not the actual send → stream → display flow. | **P1** | ~1 hr | Test |
| 1.15 | Test | **LocalChatStorage tests are thin** — Only 2 tests for empty state. No test for `addMessage()`, `clear()`, persistence round-trip, or corrupted file recovery. | **P2** | ~20 min | Test |
| 1.16 | Backend | **`_call_model()` unused param — `api_key` is passed but ignored** — Line 198 accepts `api_key` parameter, but line 209-216 retrieves it from `settings` directly. Confusing API. | **P3** | ~5 min | Backend |

---

### 1.1 [P0] `current_user["role"]` KeyError Crash

**Problem:**
`get_current_user()` in `security.py` returns only `{id, username}`. The AI advisor endpoints check `current_user["role"] != "admin"` (lines 329, 353). This causes a `KeyError` at runtime for any user who is not the first user (who gets role=admin default).

**Fix:** Three options, choose one:

**Option A (Recommended — simplest):** Add role to JWT payload in `auth.py` and `security.py`:
```python
# security.py — create_access_token
def create_access_token(user_id: int, username: str, role: str = "user") -> str:
    payload = {"sub": str(user_id), "username": username, "role": role, "exp": ...}
    
# get_current_user
return {"id": ..., "username": ..., "role": payload.get("role", "user")}
```

Then in auth router on login/register, pass the user's role to `create_access_token`.

**Option B (Minimal DB hit):** Query role from DB in `get_current_user()`:
```python
async def get_current_user(credentials = Depends(security), db = Depends(get_db)):
    payload = decode_token(credentials.credentials)
    cursor = await db.execute("SELECT role FROM users WHERE id = ?", (int(payload["sub"]),))
    user = await cursor.fetchone()
    return {"id": ..., "username": ..., "role": user["role"] if user else "user"}
```

---

### 1.2 [P2] Duplicated Model Resolution

**Problem:**
- `_call_model()` (line 198) has its own inline model_map + OpenCode/OpenRouter routing
- `_resolve_model()` + `_call_model_stream()` (lines 240-301) duplicates the same logic
- Only stream path uses `_resolve_model()`; non-stream uses inline copy

**Fix:** Make `_call_model()` use `_resolve_model()`:
```python
async def _call_model(messages: list, model: str = "deepseek-v4-flash") -> str:
    resolved, api_url, api_key = await _resolve_model(model)
    async with httpx.AsyncClient(timeout=60) as client:
        resp = await client.post(api_url, ...)
```

---

### 1.3 [P2] Hardcoded SYSTEM_PROMPT

**Problem:** 28-line prompt embedded inline. Hard to iterate on.

**Fix:** Move prompts to `backend/app/prompts/ai_advisor.py`:
```python
SYSTEM_PROMPT = """..."""
```

Or better: use a template approach in `backend/app/prompts/` directory with one file per prompt version.

---

### 1.4 [P1] 6-Month Trend Not Cycle-Aware

**Problem:** `_build_context()` lines 131-155 compute trends using calendar month boundaries:
```python
_, days = monthrange(y, m)
cursor = await db.execute(
    "WHERE COALESCE(date, ...) BETWEEN ? AND ?",
    (user_id, f"{m_str}-01", f"{m_str}-{days}"),
)
```

If user has `cycle_start_day=17`, this trend data doesn't align with the cycle-based summary they see elsewhere.

**Fix:** Compute cycle ranges for each of the last 6 cycles instead of calendar months. Reuse `get_cycle_range()`.

---

### 1.7 [P1] No Dedicated Riverpod Provider

**Problem:** All chat state is in `AiAdvisorScreen`:
```dart
final List<_ChatMessage> _messages = [];
bool _isLoading = false;
bool _useAdvancedModel = false;
```

No separation of concerns. Can't test send flow. Can't share state.

**Fix:** Create `AiAdvisorProvider`:
```dart
// mobile/lib/features/ai/providers/ai_advisor_provider.dart
class AiAdvisorState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final bool useAdvancedModel;
  final String? error;
}

class AiAdvisorNotifier extends StateNotifier<AiAdvisorState> {
  Future<void> sendMessage(String text) async { ... }
  Future<void> loadHistory() async { ... }
  Future<void> clearChat() async { ... }
}
```

---

### 1.8 [P1] Hardcoded User ID Check

**Problem:** Line 127:
```dart
if (ref.watch(authProvider).user?.id == 1)
```

**Fix:** The backend already validates opus access. Either (a) remove the toggle entirely for non-admin users (hide the advanced button), or (b) let the backend handle it and show error 403 feedback.

Recommended: hide the toggle if user role != admin. But since role isn't in the JWT yet (see 1.1), first fix 1.1 then check:
```dart
if (ref.watch(authProvider).user?.role == 'admin')
```

---

### 1.10 [P2] LocalChatStorage Singleton

**Problem:** `LocalChatStorage` is instantiated in screen state:
```dart
final LocalChatStorage _chatStorage = LocalChatStorage();
```

`_loaded` is an instance field. Every new screen instance re-reads from disk.

**Fix:** Make it a proper singleton or Riverpod provider:
```dart
// Option A: Singleton
class LocalChatStorage {
  static final LocalChatStorage _instance = LocalChatStorage._internal();
  factory LocalChatStorage() => _instance;
  LocalChatStorage._internal();
}

// Option B: Riverpod provider
final localChatStorageProvider = Provider<LocalChatStorage>((ref) => LocalChatStorage());
```

---

## Part 2: OCR Scanner

### Priority Map

| # | Area | Description | Prio | Effort | Layer |
|---|------|-------------|------|--------|-------|
| 2.1 | Backend | **In-memory rate limiting** — `_user_ocr_counts` dict resets on server restart, doesn't work with multiple workers/processes. | **P2** | ~30 min | Backend |
| 2.2 | Backend | **No image validation** — Corrupted/invalid image bytes pass through to the vision API. Wasteful API calls that always fail. | **P1** | ~15 min | Backend |
| 2.3 | Backend | **No file type validation beyond MIME** — Only checks `content_type.startswith("image/")`. SVG would pass but isn't a raster image that vision models can process. | **P1** | ~10 min | Backend |
| 2.4 | Backend | **Model hardcoded to kimi-k2.6** — Line 88: `"model": "kimi-k2.6"`. Should use settings/config. | **P2** | ~5 min | **RESOLVED in v0.3.3** — Switched to `minimax-m2.7` (vision-capable, 3× higher rate limit than k2.6). Still hardcoded; config-based selection deferred. |
| 2.5 | Backend | **No confidence score returned** — OCR returns parsed fields without any confidence indicator. User can't tell if the scan was reliable. | **P3** | ~20 min | Backend |
| 2.6 | Backend | **No multi-language support** — System prompt only asks for English output. Indonesian receipts (common in Indonesia) may parse poorly. | **P2** | ~10 min | Backend |
| 2.7 | Mobile | **No OCR-specific provider/service** — `_scanReceipt()` is inline in `AddTransactionScreen` with direct `api.uploadFile()` call. Not testable in isolation. | **P1** | ~30 min | Mobile |
| 2.8 | Mobile | **No loading indicator** — `_isScanning = true` is set but no visual loading shown (spinner/progress bar) during upload + processing. | **P1** | ~10 min | Mobile |
| 2.9 | Mobile | **No image preview** — User can't see which image was selected before/after upload. Could show a thumbnail. | **P2** | ~15 min | Mobile |
| 2.10 | Mobile | **No retry on network failure** — Error is shown once; user has to re-trigger scan from scratch. | **P2** | ~15 min | Mobile |
| 2.11 | Test | **No mobile OCR upload flow test** — Tests only verify bottom sheet UI (camera/gallery options), not the actual upload + result parsing flow. | **P1** | ~45 min | Test |
| 2.12 | Docs | **No OCR documentation exists** — AI chat history has `docs/13-ai-chat-history.md`, OCR has zero docs. | **P1** | ~30 min | Docs |

---

### 2.2 [P1] No Image Validation

**Problem:** Backend accepts any bytes with `content_type` starting with `image/`. Corrupted images, empty files, or non-image binary files slip through and waste an API call.

**Fix:** Add image validation:
```python
from PIL import Image
import io

try:
    img = Image.open(io.BytesIO(image_bytes))
    img.verify()  # raises if corrupted
except Exception:
    raise HTTPException(status_code=400, detail="Invalid or corrupted image")
```

Requires `pip install Pillow` on the backend. Consider if this dependency is worth it — another option is to check file signature bytes (magic bytes):
```python
VALID_MAGIC_BYTES = {
    b'\xff\xd8\xff': 'image/jpeg',
    b'\x89PNG\r\n\x1a\n': 'image/png',
    b'RIFF': 'image/webp',
}
```

---

### 2.3 [P1] File Type Validation Beyond MIME

**Problem:** `content_type.startswith("image/")` allows SVG and other non-raster formats. Vision APIs can't process SVGs.

**Fix:** Whitelist specific MIME types:
```python
ALLOWED_MIME = {"image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"}
if file.content_type not in ALLOWED_MIME:
    raise HTTPException(status_code=400, detail=f"Unsupported image format: {file.content_type}")
```

Or use magic byte detection (more reliable since MIME can be spoofed).

---

### 2.7 [P1] Mobile OCR Provider

**Problem:** `_scanReceipt()` in `AddTransactionScreen` directly calls `api.uploadFile()`, parses the response, and populates form fields. Not reusable, not testable.

**Fix:** Create `OcrService` or `OcrProvider`:
```dart
// mobile/lib/features/transactions/services/ocr_service.dart
class OcrService {
  final ApiClient api;
  
  Future<OcrResult> scanReceipt(String imagePath) async { ... }
}

// Or Riverpod provider
final ocrProvider = FutureProvider.family<OcrResult, String>((ref, imagePath) async {
  final api = ref.read(apiClientProvider);
  final res = await api.uploadFile('/ocr/process', imagePath);
  return OcrResult.fromJson(res.data as Map<String, dynamic>);
});
```

---

### 2.8 [P1] Scan Loading Indicator

**Problem:** `_isScanning` state is set but no loading UI is shown in the form. The user sees nothing while waiting.

**Fix:** Show a loading overlay on the form:
```dart
if (_isScanning) {
  return Stack(
    children: [
      // form fields (disabled)
      // Loading overlay
      Container(
        color: Colors.black26,
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(),
              Text('Scanning receipt...'),
            ],
          ),
        ),
      ),
    ],
  );
}
```

---

## Part 3: Cross-Cutting

| # | Description | Prio | Effort | Layer |
|---|-------------|------|--------|-------|
| 3.1 | **JWT should include `role`** — Required by 1.1, also useful for future RBAC features. | **P0** (blocker) | ~20 min | Backend |
| 3.2 | **Rate limiting should use persistent store** — Both OCR (in-memory dict) and AI (in-memory via limiter) lose data on restart. Consider Redis or SQLite-backed. | **P3** | ~2 hr | Backend |

---

## Implementation Order (Recommended)

### Phase 1 — Critical Fixes ✅ (Completed 2026-05-30)
```
1.1  + 3.1   Add role to JWT + get_current_user   [P0] ✅
1.8           Use role-based toggle on mobile       [P1] ✅
2.2  + 2.3   Image + MIME validation               [P1] ✅
1.12          Add role-based access test            [P1] ✅
```

### Extended in Phase 1 — AI Advisor Prompt Improvements
```
5.1   Cycle info in prompt                                     ✅
5.2   All household transactions (cycle, with owner)           ✅
5.3   Per-category summary (household, with owner info)        ✅
5.4   6-cycle trend (cycle-aware, not calendar-month)          ✅
5.5   Budgets with cap value, actual, and remaining             ✅
5.6   Household members list                                   ✅ (already existed)
```

### Extended in Phase 1 — OCR Improvements
```
2.13  Category validated from SQLite (not AI hallucination)    ✅
2.14  Add `note` field to OCR result                           ✅
2.15  Type-category matching enforcement via prompt             ✅
2.16  Loading indicator already exists — documented            ✅
```

### Phase 2 — Core UX (1-2 sessions, ~2-3 hr)
```
1.7           AI Advisor Riverpod provider          [P1]
2.7           OCR service provider                  [P1]
2.8           Scan loading indicator                [P1]
1.14          Mobile send flow test                 [P1]
2.11          Mobile OCR upload test                [P1]
2.12          OCR documentation                     [P1]
```

### Phase 3 — Quality (1 session, ~1.5 hr)
```
1.4           Cycle-aware trend                    [P1]
1.9           Retry on stream failure              [P2]
2.9           Image preview                        [P2]
2.10          Retry on OCR failure                 [P2]
1.10          LocalChatStorage singleton           [P2]
1.13          Web search context test              [P2]
1.15          Chat storage tests                   [P2]
```

### Phase 4 — Polish (1 session, ~1 hr)
```
1.2           Deduplicate model resolution         [P2]
1.3           Separate prompts file                [P2]
2.4           Configurable OCR model               [P2]
2.6           Multi-language OCR prompt            [P2]
2.1           Persistent rate limiting             [P2]
1.5, 1.6, 1.11, 1.16  Small cleanups              [P3]
```

---

## Estimated Total Effort

| Phase | Hours | Status |
|-------|-------|--------|
| Phase 1 — Critical | ~1 hr | ✅ Complete |
| Phase 1 — AI Prompt Rewrite | ~1 hr | ✅ Complete |
| Phase 1 — OCR Improvements | ~0.5 hr | ✅ Complete |
| Phase 2 — Core UX | ~3 hr | ⏳ Pending |
| Phase 3 — Quality | ~1.5 hr | ⏳ Pending |
| Phase 4 — Polish | ~1 hr | ⏳ Pending |
| **Total** | **~8 hr** | **~2.5 hr done** |
