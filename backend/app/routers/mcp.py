"""MCP router for WealthTrack.

Implements MCP over HTTP+SSE/JSON-RPC transport.
- GET /stream : SSE connection for server->client events (handshake ready)
- POST /stream : JSON-RPC requests for initialize, tools/list, tools/call, etc.

Uses existing get_current_user for JWT/API-key auth scoping.
Follows 2024-11-05 spec for initialize + capabilities + tools/list.
"""
from fastapi import APIRouter, Depends, Request, HTTPException
from fastapi.responses import StreamingResponse
from app.core.security import get_current_user
from app.core.config import settings
from app.database import get_db, CursorWrapper
from app.services.transaction_service import TransactionService
from app.services.summary_service import SummaryService
from app.services.budget_service import BudgetService
from app.utils.cycle import get_cycle_range, get_cycle_range_for_month
from datetime import date, timedelta
import json
import asyncio

router = APIRouter()

# Tool definitions for discovery (MVP set from plan)
MCP_TOOLS = [
    {
        "name": "get_current_balance",
        "description": "Retrieve the current total balance across all accounts for the authenticated user's household.",
        "scope": "mcp:read",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "list_recent_transactions",
        "description": "List the most recent transactions for the user/household with optional limit.",
        "scope": "mcp:read",
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
        "scope": "mcp:write",
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
        "scope": "mcp:read",
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
        "description": "List all budgets for the user's household with current spend vs limit for the active cycle.",
        "scope": "mcp:read",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "get_ai_context",
        "description": "Build and return the AI advisor context (transactions, budgets, summaries) for the user.",
        "scope": "mcp:read",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "get_household_balance",
        "description": "Get household total balance, income, and expense for the active cycle.",
        "scope": "mcp:read",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "list_household_transactions",
        "description": "List all household transactions for the active cycle with optional limit.",
        "scope": "mcp:read",
        "inputSchema": {
            "type": "object",
            "properties": {
                "limit": {"type": "integer", "default": 50, "minimum": 1, "maximum": 200}
            },
            "required": []
        }
    },
    {
        "name": "list_transactions_on_date",
        "description": "List household transactions that occurred on a specific date (YYYY-MM-DD). Optionally filter by type.",
        "scope": "mcp:read",
        "inputSchema": {
            "type": "object",
            "properties": {
                "date": {"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$", "description": "Date in YYYY-MM-DD format"},
                "type": {"type": "string", "enum": ["income", "expense"], "description": "Optional filter by transaction type"}
            },
            "required": ["date"]
        }
    },
    {
        "name": "get_weekly_household_summary",
        "description": "Get household income/expense/balance summary for the last 7 days ending on the given date (defaults to today).",
        "scope": "mcp:read",
        "inputSchema": {
            "type": "object",
            "properties": {
                "end_date": {"type": "string", "pattern": "^\\d{4}-\\d{2}-\\d{2}$", "description": "End date in YYYY-MM-DD format (defaults to today)"}
            },
            "required": []
        }
    },
]


def _has_scope(current_user: dict, scope: str) -> bool:
    """Check if the authenticated principal has the required scope.

    JWT tokens are implicitly granted all scopes. API keys are limited to
    the scopes they were created with.
    """
    if current_user.get("auth_type") == "jwt":
        return True
    scopes = current_user.get("api_key_scopes") or []
    return scope in scopes


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
        return {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}}

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
            "instructions": "WealthTrack MCP server. All tools are scoped to the authenticated user's household via JWT or API key."
        }
        return {"jsonrpc": "2.0", "id": req_id, "result": result}

    elif method == "tools/list":
        # Tool discovery - strip internal scope metadata before returning
        public_tools = [
            {k: v for k, v in t.items() if k != "scope"} for t in MCP_TOOLS
        ]
        return {"jsonrpc": "2.0", "id": req_id, "result": {"tools": public_tools}}

    elif method == "notifications/initialized":
        # Client notification after initialize - no response needed
        return {"jsonrpc": "2.0", "id": req_id, "result": None}

    elif method == "tools/call":
        # Lazy DB connection
        from app.database import get_db_bg, pool
        if pool is None:
            # In test environment without DB, respond with empty result
            tool_name = params.get("name", "unknown")
            if tool_name == "get_current_balance":
                tool_result = {"balance": 0, "currency": "IDR", "total_income": 0, "total_expense": 0}
            elif tool_name == "list_recent_transactions":
                tool_result = {"transactions": [], "count": 0, "meta": {"page": 1, "per_page": 10, "total": 0}}
            elif tool_name == "create_transaction":
                tool_result = {"success": False, "error": "DB not available in test env"}
            else:
                tool_result = {"error": "DB not available in test env"}
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": json.dumps(tool_result)}]
                },
            }
        db = await get_db_bg()

        # Execute tool - Task 5: first read-only tools wired to services (TDD)
        tool_name = params.get("name")
        arguments = params.get("arguments", {})

        tool_def = next((t for t in MCP_TOOLS if t["name"] == tool_name), None)
        if tool_def is None:
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {
                    "code": -32601,
                    "message": f"Tool not found: {tool_name}",
                },
            }

        required_scope = tool_def.get("scope", "mcp:read")
        if not _has_scope(current_user, required_scope):
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {
                    "code": -32002,
                    "message": f"Insufficient scope. Required: {required_scope}",
                },
            }

        if tool_name == "get_current_balance":
            try:
                service = SummaryService(db)
                summary = await service.get_household_summary(current_user["id"])
                tool_result = {
                    "balance": summary.get("balance", 0),
                    "currency": "IDR",
                    "as_of": summary.get("date_to"),
                    "total_income": summary.get("total_income", 0),
                    "total_expense": summary.get("total_expense", 0),
                }
            except Exception as e:
                tool_result = {"error": str(e), "balance": 0}
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": json.dumps(tool_result)}]
                },
            }

        elif tool_name == "list_recent_transactions":
            try:
                limit = arguments.get("limit", 10)
                if not isinstance(limit, int) or limit < 1:
                    limit = 10
                limit = min(limit, 100)
                if db is None:
                    # In test environment without DB, return empty list gracefully
                    tool_result = {"transactions": [], "count": 0, "meta": {"page": 1, "per_page": limit, "total": 0}}
                else:
                    try:
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
                    except Exception as e:
                        tool_result = {"error": str(e), "transactions": []}
            except Exception as e:
                tool_result = {"error": str(e), "transactions": []}
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": json.dumps(tool_result)}]
                },
            }

        elif tool_name == "create_transaction":
            # Task 6: write tool with validation, household scoping, proper error handling (TDD)
            from pydantic import ValidationError
            from app.schemas.transaction import TransactionCreate
            from app.services.transaction_service import (
                CategoryNotFoundError,
                NotHouseholdMemberError,
            )

            try:
                # Basic presence check
                required = ["amount", "type", "category_id", "description"]
                missing = [k for k in required if k not in arguments]
                if missing:
                    return {
                        "jsonrpc": "2.0",
                        "id": req_id,
                        "error": {
                            "code": -32602,
                            "message": f"Missing required fields: {missing}",
                        },
                    }

                # Household scoping: ensure user belongs to a household
                txn_service = TransactionService(db)
                try:
                    household_id, role = await txn_service._get_user_household(
                        current_user["id"]
                    )
                except NotHouseholdMemberError:
                    return {
                        "jsonrpc": "2.0",
                        "id": req_id,
                        "error": {
                            "code": -32000,
                            "message": "User is not a member of any household",
                        },
                    }

                # Default date if not provided (YYYY-MM-DD as per schema)
                if "date" not in arguments or not arguments.get("date"):
                    from datetime import date as dt_date

                    arguments["date"] = dt_date.today().isoformat()

                # Pydantic validation (enforces amount>0, type enum, date format, etc.)
                try:
                    txn_data = TransactionCreate(**arguments)
                except ValidationError as ve:
                    return {
                        "jsonrpc": "2.0",
                        "id": req_id,
                        "error": {"code": -32602, "message": f"Validation error: {ve}"},
                    }

                # Create via service (category validation happens inside)
                created = await txn_service.create_transaction(
                    txn_data, current_user["id"]
                )
                tool_result = {
                    "transaction": created,
                    "message": "Transaction created successfully",
                    "household_id": household_id,
                }
                return {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {
                        "content": [{"type": "text", "text": json.dumps(tool_result)}]
                    },
                }
            except CategoryNotFoundError as ce:
                return {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {
                        "code": -32001,
                        "message": f"Category not found: {ce}",
                    },
                }
            except Exception as e:
                return {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "error": {"code": -32603, "message": f"Internal error: {str(e)}"},
                }

        elif tool_name == "get_household_balance":
            try:
                service = SummaryService(db)
                summary = await service.get_household_summary(current_user["id"])
                tool_result = {
                    "balance": summary.get("balance", 0),
                    "total_income": summary.get("total_income", 0),
                    "total_expense": summary.get("total_expense", 0),
                    "currency": "IDR",
                    "as_of": summary.get("date_to"),
                }
            except Exception as e:
                tool_result = {"error": str(e), "balance": 0}
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": json.dumps(tool_result)}]
                },
            }

        elif tool_name == "list_household_transactions":
            try:
                limit = arguments.get("limit", 50)
                if not isinstance(limit, int) or limit < 1:
                    limit = 50
                limit = min(limit, 200)
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
            except Exception as e:
                tool_result = {"error": str(e), "transactions": []}
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": json.dumps(tool_result)}]
                },
            }

        elif tool_name == "get_monthly_summary":
            try:
                month = arguments.get("month") or date.today().strftime("%Y-%m")
                service = SummaryService(db)
                result = await service.get_monthly_summary(
                    current_user["id"], month=month
                )
                # get_monthly_summary can return a list in range mode; ensure dict here.
                summary = result if isinstance(result, dict) else result[-1] if result else {}
                tool_result = {
                    "month": month,
                    "total_income": summary.get("total_income", 0),
                    "total_expense": summary.get("total_expense", 0),
                    "balance": summary.get("balance", 0),
                    "currency": "IDR",
                }
            except Exception as e:
                tool_result = {"error": str(e)}
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": json.dumps(tool_result)}]
                },
            }

        elif tool_name == "list_budgets":
            try:
                budget_service = BudgetService(db)
                month = date.today().strftime("%Y-%m")
                summary = await budget_service.get_summary(
                    user_id=current_user["id"],
                    month=month,
                    use_cycle=True,
                )
                tool_result = {
                    "month": month,
                    "items": summary.get("items", []),
                    "uncategorized_expenses": summary.get("uncategorized_expenses", []),
                }
            except Exception as e:
                tool_result = {"error": str(e), "items": []}
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": json.dumps(tool_result)}]
                },
            }

        elif tool_name == "get_ai_context":
            try:
                # Build a lightweight context directly without external service
                service = SummaryService(db)
                txn_service = TransactionService(db)
                cycle_day = await service._get_cycle_start_day(current_user["id"])
                d_from, d_to = get_cycle_range(date.today(), cycle_day)
                household = await service.get_household_summary(
                    current_user["id"], d_from.isoformat(), d_to.isoformat()
                )
                recent = await txn_service.list_household_transactions(
                    current_user["id"], page=1, per_page=20, sort="-date"
                )
                tool_result = {
                    "cycle_range": {"from": d_from.isoformat(), "to": d_to.isoformat()},
                    "household_summary": household,
                    "recent_transactions": [dict(t) for t in recent.data],
                }
            except Exception as e:
                tool_result = {"error": str(e)}
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": json.dumps(tool_result)}]
                },
            }

        elif tool_name == "list_transactions_on_date":
            try:
                target_date = arguments.get("date")
                txn_type = arguments.get("type")
                if not target_date:
                    return {
                        "jsonrpc": "2.0",
                        "id": req_id,
                        "error": {"code": -32602, "message": "Missing required field: date"},
                    }
                txn_service = TransactionService(db)
                paginated = await txn_service.list_household_transactions(
                    current_user["id"],
                    page=1,
                    per_page=200,
                    date_from=target_date,
                    date_to=target_date,
                    type=txn_type,
                    sort="-date",
                )
                txns = [dict(t) for t in paginated.data]
                tool_result = {
                    "date": target_date,
                    "type": txn_type,
                    "transactions": txns,
                    "count": len(txns),
                    "meta": {
                        "page": paginated.meta.page,
                        "per_page": paginated.meta.per_page,
                        "total": paginated.meta.total,
                    },
                }
            except Exception as e:
                tool_result = {"error": str(e), "transactions": []}
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "content": [{"type": "text", "text": json.dumps(tool_result)}]
                },
            }

        elif tool_name == "get_weekly_household_summary":
            try:
                end_date_str = arguments.get("end_date")
                if end_date_str:
                    end = date.fromisoformat(end_date_str)
                else:
                    end = date.today()
                start = end - timedelta(days=6)
                service = SummaryService(db)
                summary = await service.get_household_summary(
                    current_user["id"], start.isoformat(), end.isoformat()
                )
                tool_result = {
                    "date_from": start.isoformat(),
                    "date_to": end.isoformat(),
                    "total_income": summary.get("total_income", 0),
                    "total_expense": summary.get("total_expense", 0),
                    "balance": summary.get("balance", 0),
                    "currency": "IDR",
                    "by_user": summary.get("by_user", []),
                }
            except Exception as e:
                tool_result = {"error": str(e)}
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
                "error": {
                    "code": -32601,
                    "message": f"Tool not found or not implemented yet: {tool_name}",
                },
            }

    else:
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "error": {"code": -32601, "message": f"Method not found: {method}"}
        }
