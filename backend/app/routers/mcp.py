"""MCP router for WealthTrack.

Implements MCP over HTTP+SSE/JSON-RPC transport.
- GET /stream : SSE connection for server->client events (handshake ready)
- POST /stream : JSON-RPC requests for initialize, tools/list, tools/call, etc.

Uses existing get_current_user for JWT auth scoping.
Follows 2024-11-05 spec for initialize + capabilities + tools/list.
"""
from fastapi import APIRouter, Depends, Request, HTTPException
from fastapi.responses import StreamingResponse
from app.core.security import get_current_user
from app.core.config import settings
from app.database import get_db, CursorWrapper
from app.services.transaction_service import TransactionService
from app.services.summary_service import SummaryService
import json
import asyncio

router = APIRouter()

# Tool definitions for discovery (MVP set from plan)
MCP_TOOLS = [
    {
        "name": "get_current_balance",
        "description": "Retrieve the current total balance across all accounts for the authenticated user's household.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "list_recent_transactions",
        "description": "List the most recent transactions for the user/household with optional limit.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "limit": {"type": "integer", "default": 10, "minimum": 1, "maximum": 100}
            },
            "required": []
        }
    },
    {
        "name": "create_transaction",
        "description": "Create a new income or expense transaction. Requires amount, type, category_id, description.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "amount": {"type": "number"},
                "type": {"type": "string", "enum": ["income", "expense"]},
                "category_id": {"type": "integer"},
                "description": {"type": "string"},
                "date": {"type": "string", "format": "date-time", "description": "ISO datetime, defaults to now"}
            },
            "required": ["amount", "type", "category_id", "description"]
        }
    },
    {
        "name": "get_monthly_summary",
        "description": "Get income/expense summary for the current or specified month.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "month": {"type": "string", "pattern": "^\\d{4}-\\d{2}$", "description": "YYYY-MM format"}
            },
            "required": []
        }
    },
    {
        "name": "list_budgets",
        "description": "List all budgets for the user's household with current spend vs limit.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "get_ai_context",
        "description": "Build and return the AI advisor context (transactions, budgets, summaries) for the user.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    }
]


@router.get("/stream")
async def mcp_stream(request: Request, current_user: dict = Depends(get_current_user)):
    """MCP SSE endpoint for streaming events and connection."""
    if not settings.MCP_ENABLED:
        raise HTTPException(status_code=503, detail="MCP disabled")

    async def event_generator():
        # Initial connection event (simplified handshake indicator)
        yield f"data: {json.dumps({'type': 'connected', 'user_id': current_user.get('id'), 'message': 'MCP SSE ready'})}\n\n"
        await asyncio.sleep(0.5)
        yield f"data: {json.dumps({'type': 'ready', 'capabilities': {'tools': True}})}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@router.post("/stream")
async def mcp_jsonrpc(
    request: Request,
    current_user: dict = Depends(get_current_user),
    db: CursorWrapper = Depends(get_db),
):
    """Handle JSON-RPC 2.0 requests over the MCP endpoint (initialize, tools/list, tools/call, etc.)."""
    if not settings.MCP_ENABLED:
        raise HTTPException(status_code=503, detail="MCP disabled")

    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid JSON")

    jsonrpc = body.get("jsonrpc")
    if jsonrpc != "2.0":
        return {"jsonrpc": "2.0", "id": body.get("id"), "error": {"code": -32600, "message": "Invalid Request"}}

    method = body.get("method")
    req_id = body.get("id")
    params = body.get("params", {})

    if method == "initialize":
        # Capabilities advertisement per MCP spec
        result = {
            "protocolVersion": "2024-11-05",
            "capabilities": {
                "tools": {"listChanged": True},
                "resources": {"subscribe": False, "listChanged": False},
            },
            "serverInfo": {
                "name": "wealthtrack-mcp-server",
                "version": settings.VERSION
            },
            "instructions": "WealthTrack MCP server. All tools are scoped to the authenticated user's household via JWT."
        }
        return {"jsonrpc": "2.0", "id": req_id, "result": result}

    elif method == "tools/list":
        # Tool discovery
        return {"jsonrpc": "2.0", "id": req_id, "result": {"tools": MCP_TOOLS}}

    elif method == "notifications/initialized":
        # Client notification after initialize - no response needed
        return {"jsonrpc": "2.0", "id": req_id, "result": None}

    elif method == "tools/call":
        # Execute tool - Task 5: first read-only tools wired to services (TDD)
        tool_name = params.get("name")
        arguments = params.get("arguments", {})

        if tool_name == "get_current_balance":
            service = SummaryService(db)
            summary = await service.get_household_summary(current_user["id"])
            tool_result = {
                "balance": summary.get("balance", 0),
                "currency": "IDR",
                "as_of": summary.get("date_to"),
                "total_income": summary.get("total_income", 0),
                "total_expense": summary.get("total_expense", 0),
            }
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": json.dumps(tool_result)}]
                },
            }

        elif tool_name == "list_recent_transactions":
            limit = arguments.get("limit", 10)
            if not isinstance(limit, int) or limit < 1:
                limit = 10
            limit = min(limit, 100)
            txn_service = TransactionService(db)
            paginated = await txn_service.list_household_transactions(
                current_user["id"], page=1, per_page=limit, sort="-date"
            )
            txns = [dict(t) for t in paginated.data]
            tool_result = {
                "transactions": txns,
                "count": len(txns),
                "meta": {
                    "page": paginated.meta.page,
                    "per_page": paginated.meta.per_page,
                    "total": paginated.meta.total,
                },
            }
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": json.dumps(tool_result)}]
                },
            }

        else:
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {"code": -32601, "message": f"Tool not found or not implemented yet: {tool_name}"},
            }

    else:
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "error": {"code": -32601, "message": f"Method not found: {method}"}
        }
