"""Summary Service — business logic for all summary endpoints.

Aggregates transaction, debt, and household data into summary dictionaries.
No FastAPI dependency — works with CursorWrapper (from app.database) directly.

Usage::

    service = SummaryService(db)
    result = await service.get_daily_summary(user_id=1)
"""

from datetime import date, datetime
from typing import Optional

from app.database import CursorWrapper
from app.utils.cycle import get_cycle_range


class SummaryService:
    """Service for all summary/aggregation operations.

    Instantiate with a CursorWrapper (from ``app.database.get_db``).
    All methods return plain dicts/lists — no FastAPI types.
    """

    def __init__(self, db: CursorWrapper) -> None:
        self.db = db

    # ── Helpers ──────────────────────────────────────────────────────────

    @staticmethod
    def parse_date_iso(s: str) -> date:
        """Parse date from ISO string — handles both ``'2026-05-28'`` and ``'2026-05-28T00:00:00.000'``."""
        try:
            return date.fromisoformat(s)
        except ValueError:
            return datetime.fromisoformat(s).date()

    async def _get_cycle_start_day(self, user_id: int) -> int:
        cursor = await self.db.execute(
            "SELECT COALESCE(cycle_start_day, 1) as cycle_start_day FROM users WHERE id = ?",
            (user_id,),
        )
        row = await cursor.fetchone()
        return row["cycle_start_day"] if row else 1

    # ── Daily Summary ────────────────────────────────────────────────────

    async def get_daily_summary(
        self,
        user_id: int,
        date_from: Optional[str] = None,
        date_to: Optional[str] = None,
    ) -> dict:
        """Income / expense summary for a specific date range (single-user).

        Returns::

            {
                "date_from": "…", "date_to": "…",
                "total_income": int, "total_expense": int, "balance": int,
                "by_category": […], "by_user": […],
            }
        """
        # Jika tidak diberi tanggal, hitung SEMUA transaksi (bukan hanya hari ini)
        d_from = date_from
        d_to = date_to

        cursor = await self.db.execute(
            """SELECT t.type, COALESCE(SUM(t.amount), 0) as total, COUNT(*) as count
               FROM transactions t
               WHERE t.user_id = ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
               GROUP BY t.type""",
            (user_id, d_from, d_to),
        )
        rows = await cursor.fetchall()
        income = 0
        expense = 0
        for r in rows:
            if r["type"] == "income":
                income = r["total"]
            else:
                expense = r["total"]

        # Expense category breakdown
        cursor = await self.db.execute(
            """SELECT c.id, c.name, c.icon, c.name_en AS category_name_en,
                      SUM(t.amount) as total, COUNT(*) as count
               FROM transactions t
               JOIN categories c ON t.category_id = c.id
               WHERE t.user_id = ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
                 AND t.type = 'expense'
               GROUP BY c.id ORDER BY total DESC""",
            (user_id, d_from, d_to),
        )
        by_cat = await cursor.fetchall()
        categories = []
        for r in by_cat:
            pct = round((r["total"] / expense * 100), 1) if expense > 0 else 0
            categories.append(
                {
                    "category_id": r["id"],
                    "category_name": r["name"],
                    "category_name_en": r["category_name_en"] or "",
                    "icon": r["icon"] or "",
                    "total": int(r["total"]),
                    "count": r["count"],
                    "percentage": pct,
                }
            )

        # By user (current user breakdown)
        cursor = await self.db.execute(
            """SELECT t.user_id, u.display_name,
                      COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) as total_expense,
                      COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE 0 END), 0) as total_income
               FROM transactions t
               JOIN users u ON t.user_id = u.id
               WHERE t.user_id = ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
               GROUP BY t.user_id, u.display_name""",
            (user_id, d_from, d_to),
        )
        by_user = await cursor.fetchall()
        users = [
            {
                "user_id": r["user_id"],
                "display_name": r["display_name"],
                "total_expense": int(r["total_expense"]),
                "total_income": int(r["total_income"]),
            }
            for r in by_user
        ]

        return {
            "date_from": d_from,
            "date_to": d_to,
            "total_income": int(income),
            "total_expense": int(expense),
            "balance": int(income - expense),
            "by_category": categories,
            "by_user": users,
        }

    # ── Household Summary ────────────────────────────────────────────────

    async def get_household_summary(
        self,
        user_id: int,
        date_from: Optional[str] = None,
        date_to: Optional[str] = None,
    ) -> dict:
        """Household-wide summary across members of the current user's household."""
        # Jika tidak diberi tanggal, hitung SEMUA transaksi (bukan hanya hari ini)
        d_from = date_from
        d_to = date_to

        # Get the user's household ID
        cursor = await self.db.execute(
            "SELECT household_id FROM household_members WHERE user_id = ?",
            (user_id,),
        )
        hm = await cursor.fetchone()
        if not hm:
            # User not in a household — return personal-only summary
            cursor = await self.db.execute(
                """SELECT t.type, COALESCE(SUM(t.amount), 0) as total, COUNT(*) as count
                   FROM transactions t
                   WHERE t.user_id = ?
                     AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                     AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
                   GROUP BY t.type""",
                (user_id, d_from, d_to),
            )
            rows = await cursor.fetchall()
            income = 0
            expense = 0
            for r in rows:
                if r["type"] == "income":
                    income = r["total"]
                else:
                    expense = r["total"]
            user_row = await (
                await self.db.execute(
                    "SELECT display_name FROM users WHERE id = ?",
                    (user_id,),
                )
            ).fetchone()
            display_name = user_row["display_name"] if user_row else ""
            return {
                "date_from": d_from,
                "date_to": d_to,
                "total_income": int(income),
                "total_expense": int(expense),
                "balance": int(income - expense),
                "by_category": [],
                "by_user": [
                    {
                        "user_id": user_id,
                        "display_name": display_name,
                        "total_expense": int(expense),
                        "total_income": int(income),
                    }
                ],
            }

        household_id = hm["household_id"]

        # Jika tidak ada filter tanggal, hitung semua transaksi
        if not d_from:
            d_from = "2020-01-01"
        if not d_to:
            d_to = "2099-12-31"

        cursor = await self.db.execute(
            """SELECT t.type, CAST(COALESCE(SUM(t.amount), 0) AS INTEGER) as total,
                      COUNT(*) as count
               FROM transactions t
               JOIN household_members hm ON hm.user_id = t.user_id AND hm.household_id = ?
               WHERE COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
               GROUP BY t.type""",
            (household_id, d_from, d_to),
        )
        rows = await cursor.fetchall()
        income = 0
        expense = 0
        for r in rows:
            if r["type"] == "income":
                income = r["total"]
            else:
                expense = r["total"]

        cursor = await self.db.execute(
            """SELECT c.id, c.name, c.icon, c.name_en AS category_name_en,
                      SUM(t.amount) as total, COUNT(*) as count
               FROM transactions t
               JOIN categories c ON t.category_id = c.id
               JOIN household_members hm ON hm.user_id = t.user_id AND hm.household_id = ?
               WHERE COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
                 AND t.type = 'expense'
               GROUP BY c.id ORDER BY total DESC""",
            (household_id, d_from, d_to),
        )
        by_cat = await cursor.fetchall()
        categories = []
        for r in by_cat:
            pct = round((r["total"] / expense * 100), 1) if expense > 0 else 0
            categories.append(
                {
                    "category_id": r["id"],
                    "category_name": r["name"],
                    "category_name_en": r["category_name_en"] or "",
                    "icon": r["icon"] or "",
                    "total": int(r["total"]),
                    "count": r["count"],
                    "percentage": pct,
                }
            )

        # By user — LEFT JOIN from household_members so users with 0 transactions still appear
        cursor = await self.db.execute(
            """SELECT hm.user_id, u.display_name,
                      CAST(COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) AS INTEGER) as total_expense,
                      CAST(COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE 0 END), 0) AS INTEGER) as total_income
               FROM household_members hm
               JOIN users u ON hm.user_id = u.id
               LEFT JOIN transactions t ON t.user_id = hm.user_id
                   AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                   AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
               WHERE hm.household_id = ?
               GROUP BY hm.user_id, u.display_name ORDER BY total_expense DESC""",
            (d_from, d_to, household_id),
        )
        by_user = await cursor.fetchall()
        users = [
            {
                "user_id": r["user_id"],
                "display_name": r["display_name"],
                "total_expense": int(r["total_expense"]),
                "total_income": int(r["total_income"]),
            }
            for r in by_user
        ]

        return {
            "date_from": d_from,
            "date_to": d_to,
            "total_income": int(income),
            "total_expense": int(expense),
            "balance": int(income - expense),
            "by_category": categories,
            "by_user": users,
        }

    # ── Monthly Summary ─────────────────────────────────────────────────

    async def get_monthly_summary(
        self,
        user_id: int,
        month: Optional[str] = None,
        month_from: Optional[str] = None,
        month_to: Optional[str] = None,
        d_from_override: Optional[str] = None,
        d_to_override: Optional[str] = None,
    ) -> dict | list:
        """Monthly summary for a given month (YYYY-MM). Default: current month.

        With *month_from* + *month_to*, returns an array of monthly summaries
        (multi-month range) for trend charts.

        With *d_from_override* + *d_to_override*, overrides the date range
        (used for billing cycle support from client).
        """
        today = date.today()

        # Multi-month range mode
        if month_from or month_to:
            m_from = month_from or "2026-01"
            m_to = month_to or today.strftime("%Y-%m")
            return await self._get_monthly_range(user_id, m_from, m_to)

        # Single month mode (backward compatible)
        m = month or today.strftime("%Y-%m")
        d_from_parsed = self.parse_date_iso(d_from_override) if d_from_override is not None else None
        d_to_parsed = self.parse_date_iso(d_to_override) if d_to_override is not None else None
        return await self._get_single_month(
            user_id, m, today,
            d_from_override=d_from_parsed, d_to_override=d_to_parsed,
        )

    async def _get_single_month(
        self,
        user_id: int,
        month: str,
        today: date,
        d_from_override: Optional[date] = None,
        d_to_override: Optional[date] = None,
    ) -> dict:
        """Monthly summary for a single month (YYYY-MM).

        When *d_from_override* / *d_to_override* are provided, uses those
        dates instead of calendar month — supports billing cycle range.
        """
        import calendar

        if d_from_override and d_to_override:
            d_from = d_from_override.isoformat()
            d_to = d_to_override.isoformat()
        else:
            d_from = f"{month}-01"
            if month == today.strftime("%Y-%m"):
                d_to = today.isoformat()
            else:
                y, mo = map(int, month.split("-"))
                d_to = f"{month}-{calendar.monthrange(y, mo)[1]}"

        cursor = await self.db.execute(
            """SELECT t.type, COALESCE(SUM(t.amount), 0) as total, COUNT(*) as count
               FROM transactions t
               WHERE t.user_id = ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
               GROUP BY t.type""",
            (user_id, d_from, d_to),
        )
        rows = await cursor.fetchall()
        income = 0
        expense = 0
        for r in rows:
            if r["type"] == "income":
                income = r["total"]
            else:
                expense = r["total"]

        cursor = await self.db.execute(
            """SELECT c.id, c.name, c.icon, c.name_en AS category_name_en,
                      SUM(t.amount) as total, COUNT(*) as count
               FROM transactions t JOIN categories c ON t.category_id = c.id
               WHERE t.user_id = ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
                 AND t.type = 'expense'
               GROUP BY c.id ORDER BY total DESC""",
            (user_id, d_from, d_to),
        )
        categories = []
        for r in await cursor.fetchall():
            pct = round((r["total"] / expense * 100), 1) if expense > 0 else 0
            categories.append({
                "category_id": r["id"], "category_name": r["name"],
                "category_name_en": r["category_name_en"] or "",
                "icon": r["icon"] or "", "total": int(r["total"]),
                "count": r["count"], "percentage": pct,
            })

        # Income category breakdown
        cursor = await self.db.execute(
            """SELECT c.id, c.name, c.icon, c.name_en AS category_name_en,
                      SUM(t.amount) as total, COUNT(*) as count
               FROM transactions t JOIN categories c ON t.category_id = c.id
               WHERE t.user_id = ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
                 AND t.type = 'income'
               GROUP BY c.id ORDER BY total DESC""",
            (user_id, d_from, d_to),
        )
        income_categories = []
        for r in await cursor.fetchall():
            income_total = int(r["total"])
            pct = round((income_total / income * 100), 1) if income > 0 else 0
            income_categories.append({
                "category_id": r["id"], "category_name": r["name"],
                "category_name_en": r["category_name_en"] or "",
                "icon": r["icon"] or "", "total": income_total,
                "count": r["count"], "percentage": pct,
            })

        cursor = await self.db.execute(
            """SELECT COALESCE(t.date, LEFT(t.created_at::text, 10)) as date,
                      CAST(COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) AS INTEGER) as expense,
                      CAST(COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE 0 END), 0) AS INTEGER) as income
               FROM transactions t
               WHERE t.user_id = ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
               GROUP BY 1 ORDER BY 1""",
            (user_id, d_from, d_to),
        )
        daily_snapshot = [dict(r) for r in await cursor.fetchall()]

        return {
            "month": month,
            "total_income": int(income),
            "total_expense": int(expense),
            "balance": int(income - expense),
            "categories": categories,
            "income_categories": income_categories,
            "daily_snapshot": daily_snapshot,
        }

    async def _get_monthly_range(self, user_id: int, m_from: str, m_to: str) -> list:
        """Multi-month summary range. Returns list of ``{month, income, expense, balance}``."""
        import calendar

        # Generate all months between m_from and m_to
        y1, m1 = map(int, m_from.split("-"))
        y2, m2 = map(int, m_to.split("-"))
        months = []
        y, mo = y1, m1
        while (y < y2) or (y == y2 and mo <= m2):
            months.append(f"{y}-{mo:02d}")
            mo += 1
            if mo > 12:
                mo = 1
                y += 1

        results = []
        for m in months:
            d_from = f"{m}-01"
            _, days = calendar.monthrange(*map(int, m.split("-")))
            d_to = f"{m}-{days}"

            cursor = await self.db.execute(
                """SELECT t.type, COALESCE(SUM(t.amount), 0) as total
                   FROM transactions t
                   WHERE t.user_id = ?
                     AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                     AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
                   GROUP BY t.type""",
                (user_id, d_from, d_to),
            )
            rows = await cursor.fetchall()
            income = 0
            expense = 0
            for r in rows:
                if r["type"] == "income":
                    income = r["total"]
                else:
                    expense = r["total"]

            results.append({
                "month": m,
                "total_income": int(income),
                "total_expense": int(expense),
                "balance": int(income - expense),
            })

        return results

    # ── Current Month / Cycle ───────────────────────────────────────────

    async def get_current_month_summary(
        self,
        user_id: int,
        use_cycle: bool = False,
        ref_date: Optional[str] = None,
    ) -> dict:
        """Shorthand — monthly summary for the current cycle or month."""
        today = self.parse_date_iso(ref_date) if ref_date else date.today()
        if use_cycle:
            cycle_start = await self._get_cycle_start_day(user_id)
            d_from, d_to = get_cycle_range(today, cycle_start)
            result = await self._get_single_month(
                user_id,
                f"{d_from.year}-{d_from.month:02d}", today,
                d_from_override=d_from, d_to_override=d_to,
            )
            result["date_from"] = d_from.isoformat()
            result["date_to"] = d_to.isoformat()
            return result
        return await self.get_monthly_summary(user_id, month=None)  # type: ignore[return-value]

    # ── Cycle Info ──────────────────────────────────────────────────────

    async def get_cycle_info(
        self,
        user_id: int,
        ref_date_str: Optional[str] = None,
    ) -> dict:
        """Return the billing cycle date range for a given reference date."""
        cycle_start_day = await self._get_cycle_start_day(user_id)
        ref_date = date.fromisoformat(ref_date_str) if ref_date_str else date.today()
        d_from, d_to = get_cycle_range(ref_date, cycle_start_day)
        return {
            "cycle_start_day": cycle_start_day,
            "date_from": d_from.isoformat(),
            "date_to": d_to.isoformat(),
        }

    # ── All-Time Category Balance ───────────────────────────────────────

    async def get_all_time_category_balance(self, user_id: int) -> dict:
        """Returns all-time balance for Savings & Investment and Emergency Funds.

        For each, it calculates: SUM(expense transactions) - SUM(income transactions)
        """
        cursor = await self.db.execute(
            "SELECT id FROM categories WHERE name_en IN ('Savings & Investment', 'Savings & Investment Disbursed')"
        )
        savings_ids = [r["id"] for r in await cursor.fetchall()]

        cursor = await self.db.execute(
            "SELECT id FROM categories WHERE name_en = 'Emergency Funds'"
        )
        emergency_ids = [r["id"] for r in await cursor.fetchall()]

        async def _query_balance(cat_ids: list[int]) -> dict:
            if not cat_ids:
                return {"total_expense": 0, "total_income": 0, "balance": 0}
            placeholders = ",".join("?" for _ in cat_ids)
            cursor = await self.db.execute(
                f"""SELECT
                       COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount ELSE 0 END), 0) as total_expense,
                       COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount ELSE 0 END), 0) as total_income
                   FROM transactions t
                   WHERE t.user_id = ?
                     AND t.category_id IN ({placeholders})""",
                (user_id, *cat_ids),
            )
            row = await cursor.fetchone()
            exp = int(row["total_expense"])
            inc = int(row["total_income"])
            return {"total_expense": exp, "total_income": inc, "balance": exp - inc}

        return {
            "savings_investment": await _query_balance(savings_ids),
            "emergency_funds": await _query_balance(emergency_ids),
        }

    # ── Debt Summary ────────────────────────────────────────────────────

    async def get_debt_summary(self, user_id: int) -> dict:
        """Total remaining debt: KPR remaining principal + CC transactions + CC installment remaining."""
        # Total KPR remaining with due_date awareness
        cursor = await self.db.execute(
            """SELECT COALESCE(SUM(
                CASE
                    WHEN ks.due_date IS NOT NULL AND EXTRACT(DAY FROM CURRENT_DATE) >= ks.due_date THEN
                        COALESCE((
                            SELECT kms.remaining_balance
                            FROM kpr_monthly_schedules kms
                            WHERE kms.simulation_id = ks.id
                            AND kms.month_number = cm.current_month
                        ), ks.total_loan)
                    ELSE
                        CASE WHEN cm.current_month <= 1 THEN ks.total_loan
                        ELSE (
                            SELECT kms.remaining_balance
                            FROM kpr_monthly_schedules kms
                            WHERE kms.simulation_id = ks.id
                            AND kms.month_number = cm.current_month - 1
                        ) END
                END
            ), 0) AS total_kpr
            FROM kpr_simulations ks
            CROSS JOIN LATERAL (
                SELECT LEAST(
                    (EXTRACT(YEAR FROM CURRENT_DATE) - ks.start_year) * 12
                    + (EXTRACT(MONTH FROM CURRENT_DATE) - ks.start_month) + 1,
                    ks.tenor_months
                ) AS current_month
            ) cm
            WHERE ks.user_id = ?""",
            (user_id,),
        )
        row = await cursor.fetchone()
        total_kpr = int(row["total_kpr"]) if row else 0

        # Count active KPR simulations
        cursor = await self.db.execute(
            "SELECT COUNT(*) AS cnt FROM kpr_simulations WHERE user_id = ?",
            (user_id,),
        )
        row = await cursor.fetchone()
        kpr_count = row["cnt"] if row else 0

        # Total CC: this month's transactions (non-installment) + installment remaining amounts
        cursor = await self.db.execute(
            """SELECT COALESCE(SUM(cct.amount), 0) AS total_txns
               FROM credit_card_transactions cct
               JOIN credit_cards cc ON cc.id = cct.card_id
               WHERE cc.user_id = ? AND cct.is_installment = 0
                   AND EXTRACT(YEAR FROM cct.transaction_date::date) = EXTRACT(YEAR FROM CURRENT_DATE)
                   AND EXTRACT(MONTH FROM cct.transaction_date::date) = EXTRACT(MONTH FROM CURRENT_DATE)""",
            (user_id,),
        )
        row = await cursor.fetchone()
        total_cc_txns = int(row["total_txns"]) if row else 0

        cursor = await self.db.execute(
            """SELECT
                   COUNT(*) AS total_active,
                   COALESCE(SUM(cci.monthly_amount * GREATEST(0, cci.total_months - (
                       (EXTRACT(YEAR FROM CURRENT_DATE)::integer * 12 + EXTRACT(MONTH FROM CURRENT_DATE)::integer)
                       - (CAST(SUBSTR(cci.start_month, 1, 4) AS integer) * 12 + CAST(SUBSTR(cci.start_month, 6, 2) AS integer))
                   ))), 0) AS total_installments
               FROM credit_card_installments cci
               JOIN credit_cards cc ON cc.id = cci.card_id
               WHERE cc.user_id = ?
                   AND cci.total_months > (
                       (EXTRACT(YEAR FROM CURRENT_DATE)::integer * 12 + EXTRACT(MONTH FROM CURRENT_DATE)::integer)
                       - (CAST(SUBSTR(cci.start_month, 1, 4) AS integer) * 12 + CAST(SUBSTR(cci.start_month, 6, 2) AS integer))
                   )""",
            (user_id,),
        )
        row = await cursor.fetchone()
        total_cc_installments = int(row["total_installments"]) if row else 0
        cc_count = row["total_active"] if row else 0

        total_cc = total_cc_txns + total_cc_installments

        return {
            "total_kpr": total_kpr,
            "kpr_count": kpr_count,
            "total_cc": total_cc,
            "cc_count": cc_count,
            "total_debt": total_kpr + total_cc,
        }

    # ── Household Debt Summary ──────────────────────────────────────────

    async def get_household_debt_summary(self, user_id: int) -> dict:
        """Household-wide debt summary — aggregate across all household members."""
        cursor = await self.db.execute(
            "SELECT household_id FROM household_members WHERE user_id = ?",
            (user_id,),
        )
        hm = await cursor.fetchone()
        if not hm:
            # Not in household — personal data only
            detail = await self._get_single_member_debt(user_id)
            # Fetch display_name from DB
            user_row = await (
                await self.db.execute(
                    "SELECT display_name FROM users WHERE id = ?",
                    (user_id,),
                )
            ).fetchone()
            detail["display_name"] = user_row["display_name"] if user_row else ""
            detail["is_current_user"] = True
            member_total = detail["kpr_total"] + detail["cc_total"]
            detail["member_total"] = member_total
            return {
                "total_debt": member_total,
                "total_kpr": detail["kpr_total"],
                "total_cc": detail["cc_total"],
                "members": [detail],
            }

        household_id = hm["household_id"]

        # Get all members in the household
        cursor = await self.db.execute(
            """SELECT u.id AS user_id, u.display_name
               FROM household_members hm
               JOIN users u ON u.id = hm.user_id
               WHERE hm.household_id = ?""",
            (household_id,),
        )
        members = await cursor.fetchall()

        member_details = []
        grand_total_kpr = 0
        grand_total_cc = 0
        visible_total = 0

        for m in members:
            member = dict(m)
            detail = await self._get_single_member_debt(member["user_id"])
            detail["display_name"] = member["display_name"]
            detail["is_current_user"] = (member["user_id"] == user_id)
            member_total = detail["kpr_total"] + detail["cc_total"]
            detail["member_total"] = member_total
            member_details.append(detail)
            grand_total_kpr += detail.get("kpr_total", 0)
            grand_total_cc += detail.get("cc_total", 0)

            # Calculate visible debt from current user's perspective
            if detail["is_current_user"]:
                visible_total += detail["kpr_total"] + detail["cc_total"]
            else:
                visible_total += detail.get("kpr_shared", 0) + detail.get("cc_shared", 0)

        # Also include shared household debt where household_id is set
        cursor = await self.db.execute(
            """SELECT COUNT(*) AS cnt
               FROM kpr_simulations
               WHERE household_id = ?
                 AND user_id NOT IN (
                     SELECT user_id FROM household_members WHERE household_id = ?
                 )""",
            (household_id, user_id),
        )
        extra_kpr_row = await cursor.fetchone()
        extra_kpr = extra_kpr_row["cnt"] if extra_kpr_row else 0

        return {
            "total_debt": visible_total,
            "total_kpr": grand_total_kpr,
            "total_cc": grand_total_cc,
            "members": member_details,
        }

    async def _get_single_member_debt(self, user_id: int) -> dict:
        """Calculate KPR + CC debt for a single member with private/shared breakdown.

        Returns separate amounts for private (household_id IS NULL) and
        shared (household_id IS NOT NULL) debts.
        """
        kpr_schedule_sub = """
            CASE
                WHEN ks.due_date IS NOT NULL AND EXTRACT(DAY FROM CURRENT_DATE) >= ks.due_date THEN
                    COALESCE((
                        SELECT kms.remaining_balance
                        FROM kpr_monthly_schedules kms
                        WHERE kms.simulation_id = ks.id
                        AND kms.month_number = cm.current_month
                    ), ks.total_loan)
                ELSE
                    CASE WHEN cm.current_month <= 1 THEN ks.total_loan
                    ELSE (
                        SELECT kms.remaining_balance
                        FROM kpr_monthly_schedules kms
                        WHERE kms.simulation_id = ks.id
                        AND kms.month_number = cm.current_month - 1
                    ) END
            END
        """
        # KPR: private vs shared
        cursor = await self.db.execute(
            f"""SELECT
                COALESCE(SUM(CASE WHEN ks.household_id IS NULL THEN ({kpr_schedule_sub}) ELSE 0 END), 0) AS total_kpr_private,
                COALESCE(SUM(CASE WHEN ks.household_id IS NOT NULL THEN ({kpr_schedule_sub}) ELSE 0 END), 0) AS total_kpr_shared
            FROM kpr_simulations ks
            CROSS JOIN LATERAL (
                SELECT LEAST(
                    (EXTRACT(YEAR FROM CURRENT_DATE) - ks.start_year) * 12
                    + (EXTRACT(MONTH FROM CURRENT_DATE) - ks.start_month) + 1,
                    ks.tenor_months
                ) AS current_month
            ) cm
            WHERE ks.user_id = ?""",
            (user_id,),
        )
        row = await cursor.fetchone()
        kpr_private = int(row["total_kpr_private"]) if row else 0
        kpr_shared = int(row["total_kpr_shared"]) if row else 0

        # CC non-installment transactions: private vs shared
        cursor = await self.db.execute(
            """SELECT
                COALESCE(SUM(CASE WHEN cc.household_id IS NULL THEN cct.amount ELSE 0 END), 0) AS cc_txns_private,
                COALESCE(SUM(CASE WHEN cc.household_id IS NOT NULL THEN cct.amount ELSE 0 END), 0) AS cc_txns_shared
            FROM credit_card_transactions cct
            JOIN credit_cards cc ON cc.id = cct.card_id
            WHERE cc.user_id = ? AND cct.is_installment = 0
                AND EXTRACT(YEAR FROM cct.transaction_date::date) = EXTRACT(YEAR FROM CURRENT_DATE)
                AND EXTRACT(MONTH FROM cct.transaction_date::date) = EXTRACT(MONTH FROM CURRENT_DATE)""",
            (user_id,),
        )
        row = await cursor.fetchone()
        cc_txns_private = int(row["cc_txns_private"]) if row else 0
        cc_txns_shared = int(row["cc_txns_shared"]) if row else 0

        # CC installments: private vs shared
        cursor = await self.db.execute(
            """SELECT
                COALESCE(SUM(CASE WHEN cc.household_id IS NULL THEN
                    cci.monthly_amount * GREATEST(0, cci.total_months - (
                        (EXTRACT(YEAR FROM CURRENT_DATE)::integer * 12 + EXTRACT(MONTH FROM CURRENT_DATE)::integer)
                        - (CAST(SUBSTR(cci.start_month, 1, 4) AS integer) * 12 + CAST(SUBSTR(cci.start_month, 6, 2) AS integer))
                    ))
                ELSE 0 END), 0) AS cc_inst_private,
                COALESCE(SUM(CASE WHEN cc.household_id IS NOT NULL THEN
                    cci.monthly_amount * GREATEST(0, cci.total_months - (
                        (EXTRACT(YEAR FROM CURRENT_DATE)::integer * 12 + EXTRACT(MONTH FROM CURRENT_DATE)::integer)
                        - (CAST(SUBSTR(cci.start_month, 1, 4) AS integer) * 12 + CAST(SUBSTR(cci.start_month, 6, 2) AS integer))
                    ))
                ELSE 0 END), 0) AS cc_inst_shared
            FROM credit_card_installments cci
            JOIN credit_cards cc ON cc.id = cci.card_id
            WHERE cc.user_id = ?
                AND cci.total_months > (
                    (EXTRACT(YEAR FROM CURRENT_DATE)::integer * 12 + EXTRACT(MONTH FROM CURRENT_DATE)::integer)
                    - (CAST(SUBSTR(cci.start_month, 1, 4) AS integer) * 12 + CAST(SUBSTR(cci.start_month, 6, 2) AS integer))
                )""",
            (user_id,),
        )
        row = await cursor.fetchone()
        cc_inst_private = int(row["cc_inst_private"]) if row else 0
        cc_inst_shared = int(row["cc_inst_shared"]) if row else 0

        cc_private = cc_txns_private + cc_inst_private
        cc_shared = cc_txns_shared + cc_inst_shared

        # Count active KPR / CC (total, not split by shared)
        cursor = await self.db.execute(
            "SELECT COUNT(*) AS cnt FROM kpr_simulations WHERE user_id = ?",
            (user_id,),
        )
        row = await cursor.fetchone()
        kpr_count = row["cnt"] if row else 0

        cursor = await self.db.execute(
            "SELECT COUNT(*) AS cnt FROM credit_cards WHERE user_id = ?",
            (user_id,),
        )
        row = await cursor.fetchone()
        cc_count = row["cnt"] if row else 0

        return {
            "kpr_private": kpr_private,
            "kpr_shared": kpr_shared,
            "kpr_total": kpr_private + kpr_shared,
            "kpr_count": kpr_count,
            "cc_private": cc_private,
            "cc_shared": cc_shared,
            "cc_total": cc_private + cc_shared,
            "cc_count": cc_count,
        }
