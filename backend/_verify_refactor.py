"""Quick verification script for ai_advisor refactor."""
import sys
sys.path.insert(0, '.')

# Verify service module imports
import app.services.ai_advisor_service
print("1. Service module imported OK")

# Verify router module imports
import app.routers.ai_advisor
print("2. Router module imported OK")

# Verify router exports
from app.routers.ai_advisor import router
print(f"3. Router exported: prefix={router.prefix}, routes={len(router.routes)}")
for r in router.routes:
    print(f"   {r.methods} {r.path}")

# Verify service exports
from app.services.ai_advisor_service import (
    HistoryItem, AdviseRequest, AdviseResponse,
    ChatRequest, ChatResponse, ChatMessageResponse,
    SYSTEM_PROMPT, build_context, build_messages,
    resolve_model, call_model, call_model_stream,
    start_chat, get_chat_messages, delete_chat_messages,
)
print("4. All service exports verified")

# Verify SYSTEM_PROMPT is preserved
assert len(SYSTEM_PROMPT) > 2000
print(f"5. SYSTEM_PROMPT preserved ({len(SYSTEM_PROMPT)} chars)")

# Verify no FastAPI imports in service
import ast
with open("app/services/ai_advisor_service.py") as f:
    tree = ast.parse(f.read())
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        for alias in node.names:
            assert "fastapi" not in alias.name.lower(), f"FastAPI import found: {alias.name}"
    elif isinstance(node, ast.ImportFrom):
        if node.module:
            assert "fastapi" not in node.module.lower(), f"FastAPI import found: {node.module}"
print("6. No FastAPI imports in service (constraint met)")

print("\n✓ All verifications passed!")
