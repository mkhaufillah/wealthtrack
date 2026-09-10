"""GET /home — personal all-time dashboard with server-formatted amounts."""

from __future__ import annotations

from app.database import CursorWrapper
from app.services.summary_service import SummaryService
from app.services.ui_bootstrap_service import UiBootstrapService


def format_money(amount: int, prefix: str = "Rp", group_sep: str = ".") -> str:
    sign = "-" if amount < 0 else ""
    grouped = f"{abs(int(amount)):,}".replace(",", group_sep)
    return f"{sign}{prefix}{grouped}"


class HomeService:
    def __init__(self, db: CursorWrapper) -> None:
        self.db = db

    async def get_home(self, user_id: int) -> dict:
        boot = await UiBootstrapService(self.db).get_bootstrap()
        fmt = boot.get("format") or {}
        prefix = fmt.get("currency_prefix") or "Rp"
        group = fmt.get("group_sep") or "."

        def money(n: int) -> str:
            return format_money(n, prefix=prefix, group_sep=group)

        summary = SummaryService(self.db)
        daily = await summary.get_daily_summary(user_id=user_id)
        pots_raw = await summary.get_all_time_category_balance(user_id=user_id)
        debt = await summary.get_debt_summary(user_id=user_id)

        income = int(daily.get("total_income") or 0)
        expense = int(daily.get("total_expense") or 0)
        balance = int(daily.get("balance") or 0)
        savings = int((pots_raw.get("savings_investment") or {}).get("balance") or 0)
        emergency = int((pots_raw.get("emergency_funds") or {}).get("balance") or 0)
        total_debt = int(debt.get("total_debt") or 0)

        cursor = await self.db.execute(
            """
            SELECT id, type, vault_blob,
                   COALESCE(date, LEFT(created_at::text, 10)) AS txn_date
            FROM transactions
            WHERE user_id = ?
            ORDER BY COALESCE(date, LEFT(created_at::text, 10)) DESC, id DESC
            LIMIT 5
            """,
            (user_id,),
        )
        from app.core.vault_row import open_row

        rows = await cursor.fetchall()
        recent = []
        for row in rows:
            row = open_row(dict(row))
            amt = int(row["amount"] or 0)
            is_exp = row["type"] == "expense"
            disp = money(amt)
            if is_exp:
                disp = f"−{disp}" if not disp.startswith("-") else disp
            else:
                disp = f"+{disp}"
            recent.append(
                {
                    "id": row["id"],
                    "description": row["description"] or "",
                    "amount": amt,
                    "amount_display": disp,
                    "type": row["type"],
                    "date": row["txn_date"],
                }
            )

        return {
            "hero": {
                "title_key": "home.hero_title",
                "amount": balance,
                "amount_display": money(balance),
                "income": income,
                "income_display": money(income),
                "expense": expense,
                "expense_display": money(expense),
            },
            "pots": {
                "savings": savings,
                "savings_display": money(savings),
                "emergency": emergency,
                "emergency_display": money(emergency),
            },
            "debt_summary": {
                "visible": total_debt > 0,
                "total": total_debt,
                "total_display": money(total_debt),
                "title_key": "home.debt_running",
            },
            "recent": recent,
        }
