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

    def _vault(self):
        from app.core.vault_ctx import VaultRequiredError, current_dek, current_sealed

        sealed = current_sealed()
        dek = current_dek()
        if sealed and dek is None:
            raise VaultRequiredError()
        return sealed, dek

    def _plain(self, sealed, dek, total, count) -> int:
        if not sealed:
            return int(total or 0)
        from app.core.vault_row import ope_sum_to_plain

        return ope_sum_to_plain(dek or b"\x00" * 32, int(total or 0), int(count or 0))

    async def _expense_categories(self, where_sql: str, params: tuple, expense: int, typ: str = "expense") -> list:
        from app.core.vault_row import unpack_money

        sealed, dek = self._vault()
        if sealed:
            cursor = await self.db.execute(
                f"SELECT * FROM transactions t WHERE 1=1 {where_sql} AND t.type = ?",
                (*params, typ),
            )
            buckets: dict = {}
            for raw in await cursor.fetchall():
                d = unpack_money(dek, dict(raw))
                cid = d.get("category_id")
                name = d.get("category_name") or ""
                key = int(cid) if cid is not None else name or 0
                b = buckets.setdefault(
                    key,
                    {
                        "category_id": cid,
                        "category_name": name,
                        "total": 0,
                        "count": 0,
                    },
                )
                b["total"] += int(d.get("amount") or 0)
                b["count"] += 1
            ids = [b["category_id"] for b in buckets.values() if b.get("category_id")]
            meta = {}
            if ids:
                ph = ",".join("?" * len(ids))
                cur = await self.db.execute(
                    f"SELECT id, icon, copy_key, name FROM categories WHERE id IN ({ph})",
                    tuple(ids),
                )
                meta = {r["id"]: dict(r) for r in await cur.fetchall()}
            out = []
            for b in sorted(buckets.values(), key=lambda x: -x["total"]):
                m = meta.get(b["category_id"]) or {}
                pct = round((b["total"] / expense * 100), 1) if expense > 0 else 0
                out.append(
                    {
                        "category_id": b["category_id"],
                        "category_name": b["category_name"] or m.get("name") or "",
                        "copy_key": m.get("copy_key") or "",
                        "icon": m.get("icon") or "",
                        "total": int(b["total"]),
                        "count": b["count"],
                        "percentage": pct,
                    }
                )
            return out
        return []

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
        # No dates → all-time personal. Dates → inclusive range.
        d_from = date_from
        d_to = date_to

        date_sql = ""
        date_params: tuple = ()
        if d_from:
            date_sql += " AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?"
            date_params += (d_from,)
        if d_to:
            date_sql += " AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?"
            date_params += (d_to,)

        from app.core.vault_ctx import VaultRequiredError, current_dek, current_sealed
        from app.core.vault_row import ope_sum_to_plain

        sealed = current_sealed()
        if sealed and current_dek() is None:
            raise VaultRequiredError()
        amount_expr = "t.amount_ord"

        cursor = await self.db.execute(
            f"""SELECT t.type, COALESCE(SUM({amount_expr}), 0) as total, COUNT(*) as count
               FROM transactions t
               WHERE t.user_id = ?{date_sql}
               GROUP BY t.type""",
            (user_id, *date_params),
        )
        rows = await cursor.fetchall()
        income = 0
        expense = 0
        for r in rows:
            total = int(r["total"] or 0)
            cnt = int(r["count"] or 0)
            if sealed:
                total = ope_sum_to_plain(current_dek() or b"\x00" * 32, total, cnt)
            if r["type"] == "income":
                income = total
            else:
                expense = total

        categories = await self._expense_categories(
            f" AND t.user_id = ?{date_sql}",
            (user_id, *date_params),
            expense,
        )

        # By user (current user breakdown)
        cursor = await self.db.execute(
            f"""SELECT t.user_id, u.display_name,
                      COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount_ord ELSE 0 END), 0) as total_expense,
                      COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount_ord ELSE 0 END), 0) as total_income
               FROM transactions t
               JOIN users u ON t.user_id = u.id
               WHERE t.user_id = ?{date_sql}
               GROUP BY t.user_id, u.display_name""",
            (user_id, *date_params),
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
                """SELECT t.type, COALESCE(SUM(t.amount_ord), 0) as total, COUNT(*) as count
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
        # tapi as_of tetap hari ini
        today = date.today().isoformat()
        if not d_from:
            d_from = "2020-01-01"
        if not d_to:
            d_to = today

        sealed, dek = self._vault()
        cursor = await self.db.execute(
            """SELECT t.type, COALESCE(SUM(t.amount_ord), 0)::bigint as total,
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
            val = self._plain(sealed, dek, r["total"], r["count"])
            if r["type"] == "income":
                income = val
            else:
                expense = val

        categories = await self._expense_categories(
            """ AND t.user_id IN (SELECT user_id FROM household_members WHERE household_id = ?)
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?""",
            (household_id, d_from, d_to),
            expense,
        )

        # By user — LEFT JOIN from household_members so users with 0 transactions still appear
        cursor = await self.db.execute(
            """SELECT hm.user_id, u.display_name,
                      COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount_ord ELSE 0 END), 0)::bigint as total_expense,
                      COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount_ord ELSE 0 END), 0)::bigint as total_income,
                      COUNT(*) FILTER (WHERE t.type = 'expense') as expense_count,
                      COUNT(*) FILTER (WHERE t.type = 'income') as income_count
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
                "total_expense": self._plain(sealed, dek, r["total_expense"], r["expense_count"]),
                "total_income": self._plain(sealed, dek, r["total_income"], r["income_count"]),
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

        sealed, dek = self._vault()
        amt = "t.amount_ord"
        cursor = await self.db.execute(
            f"""SELECT t.type, COALESCE(SUM({amt}), 0) as total, COUNT(*) as count
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
            total = self._plain(sealed, dek, r["total"], r["count"])
            if r["type"] == "income":
                income = total
            else:
                expense = total

        date_where = """ AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?"""
        categories = await self._expense_categories(
            f" AND t.user_id = ?{date_where}",
            (user_id, d_from, d_to),
            expense,
            typ="expense",
        )
        income_categories = await self._expense_categories(
            f" AND t.user_id = ?{date_where}",
            (user_id, d_from, d_to),
            income,
            typ="income",
        )

        cursor = await self.db.execute(
            """SELECT COALESCE(t.date, LEFT(t.created_at::text, 10)) as date,
                      COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount_ord ELSE 0 END), 0)::bigint as expense,
                      COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount_ord ELSE 0 END), 0)::bigint as income,
                      COUNT(*) FILTER (WHERE t.type = 'expense') as expense_count,
                      COUNT(*) FILTER (WHERE t.type = 'income') as income_count
               FROM transactions t
               WHERE t.user_id = ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                 AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
               GROUP BY 1 ORDER BY 1""",
            (user_id, d_from, d_to),
        )
        daily_snapshot = [
            {
                "date": r["date"],
                "expense": self._plain(sealed, dek, r["expense"], r["expense_count"]),
                "income": self._plain(sealed, dek, r["income"], r["income_count"]),
            }
            for r in await cursor.fetchall()
        ]

        # Savings rate — same formula the app used client-side, now server-owned.
        # Adjusted: (income - expense) + (savings expense - savings withdrawal)
        savings_expense = sum(
            c["total"] for c in categories
            if c.get("copy_key") == "cat.n.savings"
        )
        savings_income = sum(
            c["total"] for c in income_categories
            if c.get("copy_key") == "cat.n.withdrawal"
        )
        adjusted = (income - expense) + (savings_expense - savings_income)
        savings_rate = round(adjusted / income * 100, 1) if income > 0 else 0

        # Daily average expense over the actual range length.
        d_from_date = date.fromisoformat(d_from)
        d_to_date = date.fromisoformat(d_to)
        range_days = (d_to_date - d_from_date).days
        if range_days <= 0:
            range_days = 30
        daily_avg_expense = expense // range_days if range_days > 0 else 0

        return {
            "month": month,
            "total_income": int(income),
            "total_expense": int(expense),
            "balance": int(income - expense),
            "categories": categories,
            "income_categories": income_categories,
            "daily_snapshot": daily_snapshot,
            "savings_rate": savings_rate,
            "daily_avg_expense": daily_avg_expense,
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
        sealed, dek = self._vault()
        amt = "t.amount_ord"
        for m in months:
            d_from = f"{m}-01"
            _, days = calendar.monthrange(*map(int, m.split("-")))
            d_to = f"{m}-{days}"

            cursor = await self.db.execute(
                f"""SELECT t.type, COALESCE(SUM({amt}), 0) as total, COUNT(*) as count
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
                total = self._plain(sealed, dek, r["total"], r.get("count") or 1)
                if r["type"] == "income":
                    income = total
                else:
                    expense = total

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
            "SELECT id FROM categories WHERE name IN ('Tabungan & Investasi', 'Penarikan Tabungan & Investasi')"
        )
        savings_ids = [r["id"] for r in await cursor.fetchall()]

        cursor = await self.db.execute(
            "SELECT id FROM categories WHERE name = 'Dana Darurat'"
        )
        emergency_ids = [r["id"] for r in await cursor.fetchall()]

        async def _query_balance(cat_ids: list[int]) -> dict:
            if not cat_ids:
                return {"total_expense": 0, "total_income": 0, "balance": 0}
            sealed, dek = self._vault()
            if sealed:
                from app.core.vault import category_trace

                traces = [category_trace(dek or b"\x00" * 32, int(i)) for i in cat_ids]
                ph = ",".join("?" for _ in traces)
                cursor = await self.db.execute(
                    f"""SELECT t.type, COALESCE(SUM(t.amount_ord), 0) as total, COUNT(*) as count
                        FROM transactions t
                        WHERE t.user_id = ? AND t.category_trace IN ({ph})
                        GROUP BY t.type""",
                    (user_id, *traces),
                )
                exp = inc = 0
                for r in await cursor.fetchall():
                    total = self._plain(True, dek, r["total"], r["count"])
                    if r["type"] == "expense":
                        exp = total
                    else:
                        inc = total
                return {"total_expense": exp, "total_income": inc, "balance": exp - inc}
            return {"total_expense": 0, "total_income": 0, "balance": 0}

        return {
            "savings_investment": await _query_balance(savings_ids),
            "emergency_funds": await _query_balance(emergency_ids),
        }

    # ── Debt Summary ────────────────────────────────────────────────────

    async def get_debt_summary(self, user_id: int) -> dict:
        """Total remaining debt: KPR remaining principal + CC transactions + CC installment remaining."""
        sealed, dek = self._vault()
        if sealed:
            from app.core.vault_row import unpack_money

            cur = await self.db.execute(
                "SELECT id FROM kpr_simulations WHERE user_id = ?", (user_id,)
            )
            sims = await cur.fetchall()
            kpr_count = len(sims)
            total_kpr = 0
            for sim in sims:
                cur = await self.db.execute(
                    """SELECT vault_blob FROM kpr_monthly_schedules
                       WHERE simulation_id = ? ORDER BY month_number""",
                    (sim["id"],),
                )
                sched = [unpack_money(dek, dict(r)) for r in await cur.fetchall()]
                if sched:
                    amt = max(int(s.get("remaining_balance") or 0) for s in sched)
                    if amt <= 0:
                        amt = int(sched[0].get("remaining_balance") or 0)
                    total_kpr += amt
                else:
                    cur = await self.db.execute(
                        "SELECT vault_blob FROM kpr_simulations WHERE id = ?",
                        (sim["id"],),
                    )
                    ks = await cur.fetchone()
                    d = unpack_money(dek, dict(ks or {}))
                    total_kpr += int(d.get("total_loan") or 0)
            cur = await self.db.execute(
                """SELECT cct.vault_blob FROM credit_card_transactions cct
                   JOIN credit_cards cc ON cc.id = cct.card_id
                   WHERE cc.user_id = ?""",
                (user_id,),
            )
            total_cc_txns = 0
            for r in await cur.fetchall():
                d = unpack_money(dek, dict(r))
                total_cc_txns += int(d.get("amount") or 0)
            cur = await self.db.execute(
                """SELECT cci.vault_blob, cci.remaining_months
                   FROM credit_card_installments cci
                   JOIN credit_cards cc ON cc.id = cci.card_id
                   WHERE cc.user_id = ?""",
                (user_id,),
            )
            total_cc_installments = 0
            cc_count = 0
            for r in await cur.fetchall():
                d = unpack_money(dek, dict(r))
                months = int(d.get("remaining_months") or r["remaining_months"] or 0)
                if months > 0:
                    cc_count += 1
                    total_cc_installments += int(d.get("monthly_amount") or 0) * months
            total_cc = total_cc_txns + total_cc_installments
            return {
                "total_kpr": total_kpr,
                "kpr_count": kpr_count,
                "total_cc": total_cc,
                "cc_count": cc_count,
                "total_debt": total_kpr + total_cc,
            }
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
            """SELECT COALESCE(SUM(cct.amount_ord), 0) AS total_txns
               FROM credit_card_transactions cct
               JOIN credit_cards cc ON cc.id = cct.card_id
               WHERE cc.user_id = ?
                   AND EXTRACT(YEAR FROM cct.transaction_date::date) = EXTRACT(YEAR FROM CURRENT_DATE)
                   AND EXTRACT(MONTH FROM cct.transaction_date::date) = EXTRACT(MONTH FROM CURRENT_DATE)""",
            (user_id,),
        )
        row = await cursor.fetchone()
        total_cc_txns = int(row["total_txns"]) if row else 0

        cursor = await self.db.execute(
            """SELECT COUNT(*) AS total_active, 0 AS total_installments
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
        sealed, dek = self._vault()
        if sealed and dek is not None:
            from app.core.vault_row import unpack_money

            cur = await self.db.execute(
                "SELECT id, household_id FROM kpr_simulations WHERE user_id = ?",
                (user_id,),
            )
            kpr_private = 0
            kpr_shared = 0
            sims = await cur.fetchall()
            for sim in sims:
                cur = await self.db.execute(
                    """SELECT vault_blob FROM kpr_monthly_schedules
                       WHERE simulation_id = ? ORDER BY month_number""",
                    (sim["id"],),
                )
                sched = [unpack_money(dek, dict(r)) for r in await cur.fetchall()]
                amt = 0
                if sched:
                    amt = max(int(s.get("remaining_balance") or 0) for s in sched)
                else:
                    cur = await self.db.execute(
                        "SELECT vault_blob FROM kpr_simulations WHERE id = ?",
                        (sim["id"],),
                    )
                    ks = await cur.fetchone()
                    amt = int(unpack_money(dek, dict(ks or {})).get("total_loan") or 0)
                if sim.get("household_id"):
                    kpr_shared += amt
                else:
                    kpr_private += amt
        else:
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

        from datetime import date as _date

        cc_txns_private = 0
        cc_txns_shared = 0
        cc_inst_private = 0
        cc_inst_shared = 0
        if sealed and dek is not None:
            from app.core.vault_row import unpack_money

            cur = await self.db.execute(
                """SELECT cct.vault_blob, cc.household_id
                   FROM credit_card_transactions cct
                   JOIN credit_cards cc ON cc.id = cct.card_id
                   WHERE cc.user_id = ?
                     AND EXTRACT(YEAR FROM cct.transaction_date::date) = EXTRACT(YEAR FROM CURRENT_DATE)
                     AND EXTRACT(MONTH FROM cct.transaction_date::date) = EXTRACT(MONTH FROM CURRENT_DATE)""",
                (user_id,),
            )
            for r in await cur.fetchall():
                amt = int(unpack_money(dek, dict(r)).get("amount") or 0)
                if r["household_id"]:
                    cc_txns_shared += amt
                else:
                    cc_txns_private += amt
            cur = await self.db.execute(
                """SELECT cci.vault_blob, cci.total_months, cci.start_month, cc.household_id
                   FROM credit_card_installments cci
                   JOIN credit_cards cc ON cc.id = cci.card_id
                   WHERE cc.user_id = ?""",
                (user_id,),
            )
            today = _date.today()
            now_m = today.year * 12 + today.month
            for r in await cur.fetchall():
                sm = str(r["start_month"] or "0000-00")
                start_m = int(sm[:4]) * 12 + int(sm[5:7] or 0)
                months = max(0, int(r["total_months"] or 0) - (now_m - start_m))
                if months <= 0:
                    continue
                monthly = int(unpack_money(dek, dict(r)).get("monthly_amount") or 0)
                if r["household_id"]:
                    cc_inst_shared += monthly * months
                else:
                    cc_inst_private += monthly * months

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
