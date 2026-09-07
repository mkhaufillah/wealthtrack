# AI Chat History

**Feature added:** 2026-05-29
**See also:** [Flutter Mobile](05-flutter-mobile.md) · [P4 Plan](08-p4-plan.md)

---

## Overview

AI Chat History persists the user's conversation with the AI Financial Advisor locally on-device via a JSON file. This ensures conversations survive app restarts without requiring any backend storage.

| Aspect | Detail |
|--------|--------|
| **Storage location** | `getApplicationDocumentsDirectory()/wealthtrack_chat_history.json` |
| **Format** | JSON array of message objects |
| **Privacy** | Data stays on-device — no backend upload |
| **Context window** | Last 10 exchanges sent to AI API |
| **Clear on logout** | Yes — called in `profile_screen.dart _logout()` |
| **Manual clear** | `delete_outline` IconButton in AiAdvisorScreen AppBar |

---

## Architecture

```
┌─────────────────────┐     load() / persist()      ┌──────────────────┐
│                     │ ◄─────────────────────────►  │                  │
│  AiAdvisorScreen    │                              │  File on disk    │
│  (Chat UI)          │                              │  (JSON)          │
│                     │                              │                  │
│  addMessage() ──────┼─► write to disk ───────────► │ wealthtrack_chat │
│                     │                              │ _history.json    │
│  clear() ───────────┼─► delete file ─────────────► │                  │
│                     │                              │                  │
│  load() ◄───────────┼─ read on init ◄───────────── │                  │
│                     │                              └──────────────────┘
│  getLastExchanges() │
│  (10 most recent)   │
└─────────┬───────────┘
          │
          │ context (last 10 exchanges)
          ▼
┌─────────────────────┐
│  FastAPI /ai/advise │
│  (AI API endpoint)  │
└─────────────────────┘
```

---

## Implementation

### File: `lib/core/services/local_chat_storage.dart`

The `LocalChatStorage` class is a simple singleton-like service with lazy loading:

```dart
class LocalChatStorage {
  static const _fileName = 'wealthtrack_chat_history.json';
  List<ChatMessage> _messages = [];
  bool _loaded = false;
```

#### Data Model

```dart
class ChatMessage {
  final String role;      // "user" | "assistant"
  final String content;
  final DateTime timestamp;
```

Persisted as JSON:
```json
{
  "role": "user",
  "content": "How much did I spend on groceries last month?",
  "timestamp": "2026-05-29T10:30:00.000Z"
}
```

#### Key Methods

| Method | Behavior |
|--------|----------|
| `load()` | Lazy-loads from disk on first call; skips if already loaded. Handles corrupted file by starting fresh. |
| `addMessage(role, content)` | Calls `load()` first, appends message, immediately persists to disk |
| `clear()` | Clears in-memory list, deletes file from disk |
| `getLastExchanges(count)` | Returns last N exchanges (each exchange = 1 user + 1 assistant) as `[{role, content}]` for API context |

#### Lazy Load (`load()`)

```dart
Future<void> load() async {
  if (_loaded) return;
  try {
    final file = await _getFile();
    if (await file.exists()) {
      final content = await file.readAsString();
      final list = jsonDecode(content) as List<dynamic>;
      _messages = list.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();
    }
  } catch (_) {
    _messages = [];  // corrupted file → fresh start
  }
  _loaded = true;
}
```

#### Immediate Persist (`addMessage()`)

```dart
Future<void> addMessage(String role, String content) async {
  await load();
  _messages.add(ChatMessage(role: role, content: content));
  await _persist();  // writes to disk immediately
}
```

#### Sliding Window (`getLastExchanges()`)

```dart
List<Map<String, String>> getLastExchanges(int count) {
  final window = <Map<String, String>>[];
  for (final msg in _messages.reversed.take(count * 2).toList().reversed) {
    window.add({'role': msg.role, 'content': msg.content});
  }
  return window;
}
```

Takes the last `count * 2` messages (user + assistant pairs), preserving chronological order. This ensures the AI API receives meaningful conversational context without exceeding token limits.

---

## Integration Points

### AiAdvisorScreen (`lib/features/ai/ui/ai_advisor_screen.dart`)

- **`initState()`** → calls `_loadHistory()` which invokes `_chatStorage.load()` and populates the message list
- **`_send()`** → after adding user message to UI, calls `_chatStorage.addMessage('user', text)`. After receiving AI response, calls `_chatStorage.addMessage('assistant', fullAnswer)`
- **`_clearChat()`** → calls `_chatStorage.clear()` and clears UI state
- **AppBar** → `delete_outline` IconButton with `tooltip: 'Clear chat'` calls `_clearChat()`
- **Context** → `_chatStorage.getLastExchanges(10)` sent as `history` field in the API request body

### ProfileScreen (`lib/features/profile/ui/profile_screen.dart`)

- **`_logout()`** → before calling `authProvider.logout()`, calls `LocalChatStorage().clear()` to wipe all chat history on logout
- This ensures no residual conversation data remains when switching accounts

---

## Privacy / storage (current)

- **Server:** `ai_messages` (full thread for the UI) plus `ai_chat_summaries` (rolling summary for the model). See [22](22-ai-chat-summary-debt-context.md).
- **Device:** `wealthtrack_chat_history.json` is a fallback only.
- **Logout:** local file cleared; server rows stay until the user clears chat or deletes the account.
- **Manual clear:** Teman AI trash control → `DELETE /ai/chat/messages` (also drops the summary).

---

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| First launch (no file exists) | Empty history, `_loaded = false` until first `load()` call |
| App killed mid-conversation | History restored from disk on next launch |
| JSON file corrupted | Silently reset to empty history |
| Logout | `clear()` deletes file + resets in-memory list |
| User clears chat manually | Same as logout — file deleted, list cleared |
| > 10 exchanges stored | All stored on disk, but only last 10 sent to API |
| Rapid messages | Each `addMessage` triggers immediate disk write |

---

## Files

| File | Role |
|------|------|
| `lib/core/services/local_chat_storage.dart` | Core storage service (read/write/clear) |
| `lib/core/services/local_chat_storage.dart` | `ChatMessage` data model |
| `lib/features/ai/ui/ai_advisor_screen.dart` | Chat UI — load, add, clear, context sending |
| `lib/features/profile/ui/profile_screen.dart` | Clear on logout |

Backend: `ai_messages`, `ai_chat_summaries`, `GET/DELETE /ai/chat/messages`. Local file is fallback only.
