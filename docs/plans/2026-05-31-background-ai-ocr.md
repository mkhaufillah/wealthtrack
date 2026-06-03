# Background AI Chat & OCR Auto-Save Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Two improvements — (1) AI Advisor responses persist server-side so users can navigate away mid-query and return to completed answers later; (2) OCR scans auto-save transactions without blocking the user, with a processing-status banner on transactions and home screens.

**Architecture:** Both features use the same pattern: backend persists the result (chat message or OCR transaction) asynchronously while Flutter polls for status and shows appropriate UI. Two new DB tables (`ai_messages`, `ocr_jobs`). Background LLM processing via `asyncio.create_task`.

**Tech Stack:** FastAPI + PostgreSQL (existing), Flutter/Dart + Riverpod (existing), Kimi K2.5 / DeepSeek Flash (existing AI models).

---

## A — AI Advisor Background Chat

### Task A1: Add `ai_messages` DB table to migration

|**Objective:** Create the `ai_messages` table for persisting AI chat messages server-side. `parent_message_id` enables retry — when an AI message fails (status='error'), a new AI message is created with `parent_message_id` pointing to the original user message, and the old error message is hidden.

**Files:**
- Modify: `backend/app/migrate_db.py` (add Step 19)

**Step 1: Add migration step**

Add this at the end of `run_migration()`, before `conn.commit()`:

```python
# 19. Create ai_messages table (background AI chat persistence)
conn.execute("""
    CREATE TABLE IF NOT EXISTS ai_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL REFERENCES users(id),
        role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
        content TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'processing' CHECK(status IN ('processing', 'complete', 'error')),
        model TEXT NOT NULL DEFAULT 'flash',
        parent_message_id INTEGER REFERENCES ai_messages(id),
        created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
    )
""")
conn.execute("CREATE INDEX IF NOT EXISTS idx_ai_messages_user ON ai_messages(user_id, created_at)")
print("  ✓ ai_messages table ready (with parent_message_id for retry)")
```

Also add this to `run_household_migration()` or create a new `run_ai_migration()` — simplest: just add to `run_migration()`.

**Step 2: Commit**

```bash
git add backend/app/migrate_db.py
git commit -m "feat(db): add ai_messages table for background AI chat"
```

---

### Task A2: Add `POST /ai/chat` endpoint

**Objective:** Create non-streaming async endpoint that returns immediately and processes in background.

**Files:**
- Modify: `backend/app/routers/ai_advisor.py`

**Step 1: Add Pydantic models**

Add after existing `AdviseRequest`:

```python
class ChatRequest(BaseModel):
    question: str
    model: str = "flash"
    history: list[HistoryItem] = []
    retry_parent_id: Optional[int] = None  # if retrying, the user_message_id to re-process

class ChatResponse(BaseModel):
    user_message_id: int
    ai_message_id: int
```

**Step 2: Add `POST /ai/chat` endpoint**

```python
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
    await db.commit()

    # 2. If retry: mark old AI messages with this parent as 'error:hidden'
    if req.retry_parent_id:
        await db.execute(
            "UPDATE ai_messages SET status = 'error:hidden' WHERE parent_message_id = ? AND role = 'assistant'",
            (req.retry_parent_id,),
        )
        await db.commit()

    # 3. Save processing placeholder for AI, linked to user message via parent_message_id
    cursor = await db.execute(
        "INSERT INTO ai_messages (user_id, role, content, status, model, parent_message_id) VALUES (?, 'assistant', '', 'processing', ?, ?)",
        (current_user["id"], req.model, user_msg_id),
    )
    ai_msg_id = cursor.lastrowid
    await db.commit()

    # 3. Start background task (capture db dependency via closure)
    async def _process_ai():
        try:
            # Need a new db connection for background task
            from app.database import get_db_bg
            bg_db = await get_db_bg()
            try:
                messages = await _build_messages(
                    AdviseRequest(question=req.question, model=req.model, history=req.history),
                    current_user, bg_db
                )
                answer = await _call_model(messages=messages, model=req.model)

                await bg_db.execute(
                    "UPDATE ai_messages SET content = ?, status = 'complete' WHERE id = ?",
                    (answer, ai_msg_id),
                )
                await bg_db.commit()
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
                await bg_db.commit()
                await bg_db.close()
            except Exception:
                pass

    asyncio.create_task(_process_ai())

    return ChatResponse(user_message_id=user_msg_id, ai_message_id=ai_msg_id)
```

Note: `get_db_bg()` is a helper that opens a **new** database connection (needed because FastAPI `get_db` is request-scoped and auto-closes). Will be added in next task.

**Step 3: Add error import** — make sure `asyncio` is already imported (it is, line 7).

**Step 4: Commit**

```bash
git add backend/app/routers/ai_advisor.py
git commit -m "feat(api): add POST /ai/chat async endpoint"
```

---

### Task A3: Add `get_db_bg` helper for background tasks

**Objective:** Create a standalone async database connection factory for background task use.

**Files:**
- Modify: `backend/app/database.py`

**Step 1: Add `get_db_bg` function**

Add at the end of `database.py`:

```python
async def get_db_bg() -> aiosqlite.Connection:
    """Create a standalone async DB connection for background tasks.
    
    Unlike get_db() (which is request-scoped and auto-closes),
    this returns an unbounded connection that the caller must close explicitly.
    """
    db = await aiosqlite.connect(settings.DB_PATH)
    db.row_factory = aiosqlite.Row
    await db.execute("PRAGMA journal_mode=WAL")
    await db.execute("PRAGMA foreign_keys=ON")
    return db
```

**Step 2: Commit**

```bash
git add backend/app/database.py
git commit -m "feat(db): add get_db_bg helper for background tasks"
```

---

### Task A4: Add `GET /ai/chat/messages` endpoint

**Objective:** Return persisted AI chat messages for the current user.

**Files:**
- Modify: `backend/app/routers/ai_advisor.py`

**Step 1: Add response model**

```python
class ChatMessageResponse(BaseModel):
    id: int
    role: str
    content: str
    status: str
    model: str
    parent_message_id: Optional[int] = None
    created_at: str
```

**Step 2: Add endpoint (filter out hidden error messages)**

```python
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
```

**Step 3: Commit**

```bash
git add backend/app/routers/ai_advisor.py
git commit -m "feat(api): add GET /ai/chat/messages endpoint"
```

---

### Task A5: Flutter — Update API client to support async chat

**Objective:** Add `sendChatMessage()` and `getChatMessages()` methods.

**Files:**
- Modify: Ensure `ApiClient` has the right methods. The existing `streamPost()` is kept for SSE but new `post()` and `get()` methods should already exist.

Check `api_client.dart` — if `post` and `get` with JSON body already exist, this task is just verification.

**Step 1: Verify existing methods**

Look for `api_client.dart`:
```dart
// Should already have these:
Future<ApiResponse> post(String path, {Map<String, dynamic>? data});
Future<ApiResponse> get(String path, {Map<String, dynamic>? queryParams});
```

If missing, add them in `api_client.dart`.

**Step 2: Commit** (if changes needed)

```bash
git add mobile/lib/...
git commit -m "feat(api): add post/get for async chat"
```

---

### Task A6: Flutter — Rewrite AiAdvisorScreen to use persisted chat

**Objective:** Replace SSE streaming with async POST + polling pattern.

**Files:**
- Modify: `mobile/lib/features/ai/ui/ai_advisor_screen.dart`

**Step 1: Modify `_loadHistory()` — load from server instead of local storage**

```dart
Future<void> _loadHistory() async {
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/ai/chat/messages');
    final messages = (res.data as List<dynamic>).map((m) => _ChatMessage(
      id: m['id'] as int,
      text: m['content'] as String? ?? '',
      isUser: m['role'] == 'user',
      status: m['status'] as String? ?? 'complete',
    )).toList();
    if (!mounted) return;
    setState(() {
      _messages.addAll(messages);
      _loaded = true;
    });
    _scrollToBottom();
    // Start polling if any messages are processing
    if (_messages.any((m) => m.status == 'processing')) {
      _startPolling();
    }
  } catch (e) {
    // Fallback to local storage
    await _chatStorage.load();
    if (!mounted) return;
    setState(() {
      _messages.addAll(
        _chatStorage.messages.map((m) => _ChatMessage(
          text: m.content, isUser: m.role == 'user', status: 'complete')),
      );
      _loaded = true;
    });
  }
}
```

**Step 2: Add polling logic**

```dart
Timer? _pollTimer;

void _startPolling() {
  _pollTimer?.cancel();
  _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollMessages());
}

Future<void> _pollMessages() async {
  if (!mounted) return;
  try {
    final api = ref.read(apiClientProvider);
    final res = await api.get('/ai/chat/messages');
    final serverMessages = (res.data as List<dynamic>).map((m) => ({
      'id': m['id'] as int,
      'content': m['content'] as String? ?? '',
      'role': m['role'] as String? ?? '',
      'status': m['status'] as String? ?? '',
    })).toList();

    setState(() {
      // Update existing messages with server content
      for (final sm in serverMessages) {
        final idx = _messages.indexWhere((m) => m.id == sm['id']);
        if (idx != -1) {
          _messages[idx].text = sm['content'] as String;
          _messages[idx].status = sm['status'] as String;
        }
      }
    });
    _scrollToBottom();

    // Stop polling when no more processing messages
    if (!_messages.any((m) => m.status == 'processing')) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  } catch (_) {}
}

@override
void dispose() {
  _pollTimer?.cancel();
  _msgCtrl.dispose();
  _scrollCtrl.dispose();
  super.dispose();
}
```

**Step 3: Modify `_send()` — use POST instead of SSE**

```dart
Future<void> _send() async {
  final text = _msgCtrl.text.trim();
  if (text.isEmpty || _isLoading) return;

  _msgCtrl.clear();
  final tempId = DateTime.now().millisecondsSinceEpoch;

  setState(() {
    _messages.add(_ChatMessage(id: tempId, text: text, isUser: true, status: 'complete'));
    _isLoading = true;
    _messages.add(_ChatMessage(id: tempId + 1, text: '', isUser: false, status: 'processing'));
  });
  _scrollToBottom();

  try {
    final api = ref.read(apiClientProvider);
    final history = _chatStorage.getLastExchanges(10);

    final res = await api.post('/ai/chat', data: {
      'question': text,
      'model': _useAdvancedModel ? 'opus' : 'flash',
      'history': history,
    });

    final data = res.data as Map<String, dynamic>;
    final userMsgId = data['user_message_id'] as int;
    final aiMsgId = data['ai_message_id'] as int;

    setState(() {
      // Replace temp IDs with real server IDs
      _messages[_messages.length - 2] = _ChatMessage(id: userMsgId, text: text, isUser: true, status: 'complete');
      _messages.last = _ChatMessage(id: aiMsgId, text: '', isUser: false, status: 'processing');
      _isLoading = false;
    });

    // Save user message to local storage too
    await _chatStorage.addMessage('user', text);

    // Start polling for AI response
    _startPolling();
  } catch (e) {
    setState(() {
      _messages.removeLast(); // remove temp processing message
      // Mark the user message with an error AI placeholder that shows retry
      _messages.add(_ChatMessage(
        id: tempId + 2,
        text: '',
        isUser: false,
        status: 'error',
      ));
      _isLoading = false;
    });
  }
  _scrollToBottom();
}
```

**Step 3b: Add `_retry()` method & update `_send()` for retry**

Add after `_send()`:

```dart
Future<void> _retry(_ChatMessage failedMsg) async {
  final userIdx = _messages.lastIndexWhere((m) => m.isUser && m.id < failedMsg.id);
  if (userIdx == -1) return;
  final userMsg = _messages[userIdx];
  final originalId = userMsg.id;
  setState(() => _messages.removeWhere((m) => m.id == failedMsg.id));
  _msgCtrl.text = userMsg.text;
  await _send(retryParentId: originalId);
  _msgCtrl.clear();
}
```

Update `_send()` signature to accept optional retryParentId:

```dart
Future<void> _send({int? retryParentId}) async {
```

And update the POST body inside `_send()` to include retry_parent_id:

```dart
    final res = await api.post('/ai/chat', data: {
      'question': text,
      'model': _useAdvancedModel ? 'opus' : 'flash',
      'history': history,
      if (retryParentId != null) 'retry_parent_id': retryParentId,
    });
```

**Step 4: Update `_ChatMessage` model**

```dart
class _ChatMessage {
  final int id;
  String text;
  final bool isUser;
  String status; // 'processing', 'complete', 'error'

  _ChatMessage({required this.id, required this.text, required this.isUser, this.status = 'complete'});
}
```

**Step 5: Update `_buildMessage()` — show spinner for processing, retry button for error**

```dart
Widget _buildMessage(_ChatMessage msg) {
  return Align(
    alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
      decoration: BoxDecoration(
        color: msg.isUser ? AppColors.accent : AppColors.surface,
        borderRadius: BorderRadius.circular(16).copyWith(
          bottomRight: msg.isUser ? const Radius.circular(4) : null,
          bottomLeft: msg.isUser ? null : const Radius.circular(4),
        ),
      ),
      child: msg.isUser
          ? Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 14))
          : msg.status == 'processing' && msg.text.isEmpty
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    Text('Thinking...', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                  ],
                )
              : msg.status == 'error'
                  ? GestureDetector(
                      onTap: () => _retry(msg),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, size: 16, color: AppColors.error),
                          const SizedBox(width: 6),
                          Text('Failed — tap to retry',
                              style: TextStyle(fontSize: 13, color: AppColors.error)),
                        ],
                      ),
                    )
                  : MarkdownBody(
                      data: msg.text,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                        strong: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
    ),
  );
}
```

**Step 6: Commit**

```bash
git add mobile/lib/features/ai/ui/ai_advisor_screen.dart
git commit -m "feat(ai): use persisted async chat with polling"
```

---

### Task A7: Clean up — remove unused SSE imports

**Objective:** Remove dead code after migration to async chat.

**Files:**
- Modify: `mobile/lib/features/ai/ui/ai_advisor_screen.dart`

**Step 1: Remove streamPost import and usage**

Remove the `streamPost` method call and any `StreamSubscription` imports. The `api.streamPost()` method may still be used elsewhere; just remove the import of `dart:async` if it's only used here.

**Step 2: Commit**

```bash
git add mobile/lib/features/ai/ui/ai_advisor_screen.dart
git commit -m "refactor(ai): remove unused SSE code"
```

---

## B — OCR Auto-Save Background

### Task B1: Add `ocr_jobs` DB table to migration

**Objective:** Create the `ocr_jobs` table for tracking background OCR processing.

**Files:**
- Modify: `backend/app/migrate_db.py`

**Step 1: Add migration step**

Add after the `ai_messages` step in `run_migration()`:

```python
# 20. Create ocr_jobs table (background OCR processing)
conn.execute("""
    CREATE TABLE IF NOT EXISTS ocr_jobs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL REFERENCES users(id),
        image_filename TEXT,
        status TEXT NOT NULL DEFAULT 'processing' CHECK(status IN ('processing', 'completed', 'failed')),
        transaction_id INTEGER REFERENCES transactions(id),
        error TEXT,
        raw_text TEXT,
        created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
        completed_at TEXT
    )
""")
conn.execute("CREATE INDEX IF NOT EXISTS idx_ocr_jobs_user ON ocr_jobs(user_id, status)")
print("  ✓ ocr_jobs table ready")
```

**Step 2: Commit**

```bash
git add backend/app/migrate_db.py
git commit -m "feat(db): add ocr_jobs table for background OCR"
```

---

### Task B2: Add `POST /ocr/process-and-save` endpoint

**Objective:** New endpoint that auto-creates transaction from OCR and returns immediately.

**Files:**
- Modify: `backend/app/routers/ocr.py`

**Step 1: Add new endpoint**

Replace existing `POST /ocr/process` or add alongside it. We'll add a new endpoint and keep the old one for compatibility:

```python
class OcrAutoSaveResult(BaseModel):
    job_id: int
    transaction_id: Optional[int] = None
    status: str = "processing"

@router.post("/process-and-save", response_model=OcrAutoSaveResult)
async def process_ocr_and_save(
    file: UploadFile = File(...),
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Process OCR image and auto-save transaction. Returns immediately."""
    _check_rate_limit(current_user["id"])

    # Validate + compress (same as /process)
    if not file.content_type:
        raise HTTPException(status_code=400, detail="Could not detect file type")

    image_bytes = await file.read()
    if len(image_bytes) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Image too large (max 10 MB)")

    _validate_image(file.content_type, image_bytes)

    # Save image to disk
    import os
    from datetime import datetime
    ocr_dir = Path(settings.DB_PATH).parent / "ocr_images"
    ocr_dir.mkdir(exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    ext = Path(file.filename or "receipt.jpg").suffix or ".jpg"
    img_filename = f"ocr_{current_user['id']}_{timestamp}{ext}"
    img_path = str(ocr_dir / img_filename)

    with open(img_path, "wb") as f:
        f.write(image_bytes)

    # Create OCR job with processing status
    cursor = await db.execute(
        "INSERT INTO ocr_jobs (user_id, image_filename, status) VALUES (?, ?, 'processing')",
        (current_user["id"], img_filename),
    )
    job_id = cursor.lastrowid
    await db.commit()

    # Start background processing
    async def _process_ocr():
        try:
            from app.database import get_db_bg
            bg_db = await get_db_bg()
            try:
                # Read and compress image
                raw = open(img_path, "rb").read()
                img = Image.open(BytesIO(raw))
                w, h = img.size
                max_side = 1200
                if max(w, h) > max_side:
                    ratio = max_side / max(w, h)
                    new_w, new_h = int(w * ratio), int(h * ratio)
                    img = img.resize((new_w, new_h), Image.LANCZOS)
                if img.mode in ("RGBA", "P"):
                    img = img.convert("RGB")
                compressed = BytesIO()
                img.save(compressed, format="JPEG", optimize=True, quality=85)
                compressed_bytes = compressed.getvalue()

                b64 = base64.b64encode(compressed_bytes).decode()
                data_url = f"data:image/jpeg;base64,{b64}"

                # Call vision API
                categories_str = await _load_categories(bg_db)
                prompt = SYSTEM_PROMPT.format(categories=categories_str)

                async with httpx.AsyncClient(timeout=60) as client:
                    resp = await client.post(
                        "https://opencode.ai/zen/go/v1/chat/completions",
                        headers={"Authorization": f"Bearer {settings.OPENCODE_GO_API_KEY}", "Content-Type": "application/json"},
                        json={
                            "model": "kimi-k2.5",
                            "messages": [
                                {"role": "system", "content": prompt},
                                {"role": "user", "content": [
                                    {"type": "image_url", "image_url": {"url": data_url}},
                                    {"type": "text", "text": "Extract transaction data from this image."},
                                ]},
                            ],
                            "max_tokens": 4096,
                        },
                    )

                if resp.status_code != 200:
                    raise Exception(f"Vision API error: {resp.status_code}")

                body = resp.json()
                content = body["choices"][0]["message"]["content"].strip()
                content = re.sub(r"^```(?:json)?\s*", "", content)
                content = re.sub(r"\s*```$", "", content)

                parsed = json.loads(content)

                # Map category name to category_id
                category_name = parsed.get("category_name", "")
                txn_type = parsed.get("type", "expense")
                cursor = await bg_db.execute(
                    "SELECT id FROM categories WHERE name = ? AND type = ?",
                    (category_name, txn_type),
                )
                cat_row = await cursor.fetchone()
                category_id = cat_row["id"] if cat_row else None

                if not category_id:
                    cursor = await bg_db.execute(
                        "SELECT id FROM categories WHERE name = 'Lainnya' AND type = ?",
                        (txn_type,),
                    )
                    cat_row = await cursor.fetchone()
                    category_id = cat_row["id"] if cat_row else None

                amount = int(parsed.get("amount", 0))
                description = str(parsed.get("description", ""))
                note = str(parsed.get("note", ""))
                txn_date = str(parsed.get("date", datetime.now().strftime("%Y-%m-%d")))

                if amount > 0 and category_id:
                    cursor = await bg_db.execute(
                        """INSERT INTO transactions (user_id, type, category_id, category_name, amount, description, note, date)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                        (current_user["id"], txn_type, category_id, category_name, amount, description, note, txn_date),
                    )
                    txn_id = cursor.lastrowid

                    await bg_db.execute(
                        "UPDATE ocr_jobs SET status = 'completed', transaction_id = ?, completed_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = ?",
                        (txn_id, job_id),
                    )
                else:
                    await bg_db.execute(
                        "UPDATE ocr_jobs SET status = 'failed', error = 'Could not determine amount or category' WHERE id = ?",
                        (job_id,),
                    )

                await bg_db.commit()

            except json.JSONDecodeError:
                await bg_db.execute(
                    "UPDATE ocr_jobs SET status = 'failed', error = 'Invalid JSON from vision API', raw_text = ? WHERE id = ?",
                    (content if 'content' in dir() else '', job_id),
                )
                await bg_db.commit()
            except Exception as e:
                await bg_db.execute(
                    "UPDATE ocr_jobs SET status = 'failed', error = ? WHERE id = ?",
                    (str(e), job_id),
                )
                await bg_db.commit()
            finally:
                await bg_db.close()
        except Exception:
            pass  # Don't crash the request

    asyncio.create_task(_process_ocr())

    return OcrAutoSaveResult(job_id=job_id, status="processing")
```

**Step 2: Add imports** — ensure `Path`, `os`, `datetime` are imported at top.

**Step 3: Commit**

```bash
git add backend/app/routers/ocr.py
git commit -m "feat(api): add POST /ocr/process-and-save auto-save endpoint"
```

---

### Task B3: Add `GET /ocr/pending-count` endpoint

**Objective:** Return count of pending/processing OCR jobs for the current user.

**Files:**
- Modify: `backend/app/routers/ocr.py`

**Step 1: Add endpoint**

```python
@router.get("/pending-count")
async def ocr_pending_count(
    db=Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    cursor = await db.execute(
        "SELECT COUNT(*) as count FROM ocr_jobs WHERE user_id = ? AND status = 'processing'",
        (current_user["id"],),
    )
    row = await cursor.fetchone()
    return {"count": row["count"]}
```

**Step 2: Commit**

```bash
git add backend/app/routers/ocr.py
git commit -m "feat(api): add GET /ocr/pending-count endpoint"
```

---

### Task B4: Flutter — Update OCR scan to auto-save + navigate

**Objective:** Replace the OCR blocking flow with auto-save + redirect.

**Files:**
- Modify: `mobile/lib/features/transactions/ui/add_transaction_screen.dart`

**Step 1: Modify `_scanReceipt()`**

Replace the current OCR flow. After picking image:

```dart
Future<void> _scanReceipt() async {
  // Show source picker (unchanged)
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(child: Text('Scan Receipt', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          const SizedBox(height: 4),
          Center(child: Text('Choose an image source', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Take Photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from Gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null || !mounted) return;

  try {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 70, maxWidth: 1920);
    if (picked == null) return;

    // Upload and auto-save
    final api = ref.read(apiClientProvider);
    await api.uploadFile('/ocr/process-and-save', picked.path);

    if (!mounted) return;

    // Show processing popup
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            const Text('Processing'),
          ],
        ),
        content: const Text('Your receipt is being processed in the background. The transaction will appear shortly.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Navigate to transactions page
              context.go('/main/transactions');
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('OCR failed: $e'), backgroundColor: AppColors.error),
    );
  }
}
```

**Step 2: Commit**

```bash
git add mobile/lib/features/transactions/ui/add_transaction_screen.dart
git commit -m "feat(ocr): auto-save OCR with background processing"
```

---

### Task B5: Flutter — Add OCR pending banner to transactions screen

**Objective:** Show a ticker/banner on the transactions list when OCR jobs are processing.

**Files:**
- Modify: Find the transactions list screen (likely `mobile/lib/features/transactions/ui/transactions_screen.dart`)

**Step 1: Create a pending OCR provider**

Create `mobile/lib/features/ocr/providers/ocr_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/app_providers.dart';

final ocrPendingCountProvider = StateNotifierProvider<OcrPendingCountNotifier, int>((ref) {
  return OcrPendingCountNotifier(ref.read(apiClientProvider));
});

class OcrPendingCountNotifier extends StateNotifier<int> {
  final ApiClient _api;
  OcrPendingCountNotifier(this._api) : super(0);

  Future<void> load() async {
    try {
      final res = await _api.get('/ocr/pending-count');
      final data = res.data as Map<String, dynamic>;
      state = data['count'] as int? ?? 0;
    } catch (_) {
      state = 0;
    }
  }
}
```

**Step 2: Add banner widget to transactions screen**

In the transactions screen, just below the AppBar or above the list:

```dart
// Inside build method, after AppBar
if (pendingCount > 0)
  Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    color: AppColors.warning.withOpacity(0.1),
    child: Row(
      children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 8),
        Text(
          pendingCount == 1
            ? '⏳ 1 transaction being processed...'
            : '⏳ $pendingCount transactions being processed...',
          style: TextStyle(fontSize: 13, color: AppColors.warning),
        ),
      ],
    ),
  ),
```

**Step 3: Add polling to transactions screen**

```dart
@override
void initState() {
  super.initState();
  _startOcrPolling();
}

Timer? _ocrPollTimer;

void _startOcrPolling() {
  _ocrPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
    ref.read(ocrPendingCountProvider.notifier).load();
  });
}

@override
void dispose() {
  _ocrPollTimer?.cancel();
  super.dispose();
}
```

Watch for the count dropping to 0 after being > 0 to trigger a refresh:

```dart
// In build method or via ref.listen
ref.listen<int>(ocrPendingCountProvider, (previous, next) {
  if (previous != null && previous > 0 && next == 0) {
    // Refresh transaction list when pending OCR completes
    ref.read(transactionListProvider.notifier).load();
  }
});
```

**Step 4: Commit**

```bash
git add mobile/lib/features/ocr/ mobile/lib/features/transactions/
git commit -m "feat(ocr): add pending OCR banner to transactions screen"
```

---

### Task B6: Flutter — Add OCR pending banner to home screen

**Objective:** Same ticker on home screen dashboard.

**Files:**
- Modify: `mobile/lib/features/home/ui/home_screen.dart`

**Step 1: Import OCR provider**

```dart
import '../../ocr/providers/ocr_provider.dart';
```

**Step 2: Add poll + banner in home screen build**

```dart
// In build body, before the main content:
final ocrCount = ref.watch(ocrPendingCountProvider);

// Poll on init
ref.read(ocrPendingCountProvider.notifier).load();

// Banner
if (ocrCount > 0)
  Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    color: AppColors.warning.withOpacity(0.1),
    child: Row(
      children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 8),
        Text(
          '⏳ $ocrCount transaction(s) being processed...',
          style: TextStyle(fontSize: 13, color: AppColors.warning),
        ),
      ],
    ),
  ),
```

Also add a periodic timer in initState to poll every 5 seconds.

**Step 3: Commit**

```bash
git add mobile/lib/features/home/ui/home_screen.dart
git commit -m "feat(ocr): add pending OCR banner to home screen"
```

---

## C — Tests & Verification

### Task C1: Backend tests — AI chat endpoint

**Objective:** Verify POST /ai/chat and GET /ai/chat/messages work.

**Files:**
- Create: `backend/tests/test_ai_chat.py`

**Step 1: Write tests**

```python
import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app

@pytest.mark.anyio
async def test_ai_chat_creates_messages(db_session):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Login first
        login_resp = await client.post("/api/v1/auth/login", json={"username": "filla", "password": "password123"})
        token = login_resp.json()["access_token"]

        # Send chat message
        resp = await client.post(
            "/api/v1/ai/chat",
            json={"question": "Hello", "model": "flash", "history": []},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "user_message_id" in data
        assert "ai_message_id" in data

        # Get messages
        resp2 = await client.get(
            "/api/v1/ai/chat/messages",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp2.status_code == 200
        msgs = resp2.json()
        assert len(msgs) >= 2

@pytest.mark.anyio
async def test_ai_chat_requires_auth(db_session):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.post("/api/v1/ai/chat", json={"question": "Hello", "model": "flash", "history": []})
        assert resp.status_code == 401
```

**Step 2: Run tests**

```bash
cd backend && uv run pytest tests/test_ai_chat.py -v
```
Expected: 2 passed (or 1 if auth test fails due to existing auth setup — adjust as needed)

**Step 3: Commit**

```bash
git add backend/tests/test_ai_chat.py
git commit -m "test: add AI chat endpoint tests"
```

---

### Task C2: Backend tests — OCR process-and-save endpoint

**Objective:** Verify OCR auto-save endpoint creates jobs.

**Files:**
- Create: `backend/tests/test_ocr_auto.py`

```python
import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app

@pytest.mark.anyio
async def test_ocr_process_and_save_auth(db_session):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Login
        login_resp = await client.post("/api/v1/auth/login", json={"username": "filla", "password": "password123"})
        token = login_resp.json()["access_token"]

        # Create a test image (tiny valid JPEG)
        import io
        from PIL import Image
        img = Image.new('RGB', (100, 100), color='red')
        buf = io.BytesIO()
        img.save(buf, format='JPEG')
        buf.seek(0)

        resp = await client.post(
            "/api/v1/ocr/process-and-save",
            files={"file": ("test.jpg", buf, "image/jpeg")},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "job_id" in data
        assert data["status"] == "processing"

        # Check pending count
        resp2 = await client.get(
            "/api/v1/ocr/pending-count",
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp2.status_code == 200
        count_data = resp2.json()
        assert "count" in count_data
```

**Step 2: Run tests**

```bash
cd backend && uv run pytest tests/test_ocr_auto.py -v
```

**Step 3: Commit**

```bash
git add backend/tests/test_ocr_auto.py
git commit -m "test: add OCR auto-save endpoint tests"
```

---

## D — Documentation

### Task D1: Add feature doc

**Objective:** Create feature documentation for background AI chat + OCR.

**Files:**
- Create: `docs/18-background-ai-ocr.md`

This doc should include:
1. Architecture diagram showing async flow
2. Files changed table with descriptions
3. Key implementation decisions (why `asyncio.create_task` instead of Celery, why polling instead of SSE reconnection)
4. Cross-reference updates to existing docs (P4 plan status, related docs)

**Step 1: Commit**

```bash
git add docs/18-background-ai-ocr.md
git commit -m "docs: add background AI chat & OCR feature doc"
```

---

## Verification Checklist

After all tasks are done:

- [ ] Migration re-run creates `ai_messages` and `ocr_jobs` tables (idempotent), `ai_messages` has `parent_message_id` column
- [ ] `POST /ai/chat` returns immediately with message IDs
- [ ] `POST /ai/chat` with `retry_parent_id` marks old AI messages as `error:hidden` and creates new processing message
- [ ] `GET /ai/chat/messages` returns persisted messages, excludes `error:hidden`
- [ ] Background LLM processing completes and updates message status to 'complete'
- [ ] Flutter AI advisor loads messages from server on init
- [ ] Flutter polls every **1 second** and shows completed AI responses after navigating back
- [ ] Flutter shows **"Failed — tap to retry"** button for error status on AI messages
- [ ] Tap retry → re-sends question with `retry_parent_id` → new processing begins
- [ ] `POST /ocr/process-and-save` creates job and returns immediately
- [ ] Background OCR processing creates transaction
- [ ] `GET /ocr/pending-count` returns accurate count
- [ ] Flutter transactions screen shows pending banner
- [ ] Flutter home screen shows pending banner
- [ ] Banner disappears when OCR completes
- [ ] All existing tests still pass
