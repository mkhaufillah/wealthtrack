"""Budget Service — pure business logic, no FastAPI dependency.

Encapsulates all budget CRUD, summary aggregation, health projection,
and AI-suggested budget logic.

Usage::

    service = BudgetService(db)
    budgets = await service.list_budgets(user_id=1, month="2026-05")
"""

from typing import Optional

from app.database import CursorWrapper
from app.utils.cycle import get_cycle_range_for_month


# ── Domain exceptions ────────────────────────────────────────────────


class BudgetNotFoundError(Exception):
    """Raised when a budget does not exist or does not belong to the user."""

    def __init__(self, budget_id: int) -> None:
        self.budget_id = budget_id
        super().__init__(f"Budget {budget_id} not found")


class CategoryNotFoundError(Exception):
    """Raised when a category does not exist."""

    def __init__(self, category_id: int) -> None:
        self.category_id = category_id
        super().__init__(f"Category {category_id} not found")


# ── Service ──────────────────────────────────────────────────────────


class BudgetService:
    """Service for all budget operations.

    Instantiate with a ``CursorWrapper`` (from ``app.database.get_db``).
    All methods return plain dicts / lists — no FastAPI types.
    """

    def __init__(self, db: CursorWrapper) -> None:
        self.db = db

    # ── Helpers ──────────────────────────────────────────────────────

    async def _get_user_cycle_start_day(self, user_id: int) -> int:
        """Return the user's ``cycle_start_day`` (default 1)."""
        cursor = await self.db.execute(
            "SELECT cycle_start_day FROM users WHERE id = ?",
            (user_id,),
        )
        row = await cursor.fetchone()
        return row["cycle_start_day"] if row else 1

    async def _validate_category(self, category_id: int) -> dict:
        """Fetch category row. Raises ``CategoryNotFoundError`` if missing."""
        cursor = await self.db.execute(
            "SELECT id, name, icon, copy_key FROM categories WHERE id = ?",
            (category_id,),
        )
        cat = await cursor.fetchone()
        if not cat:
            raise CategoryNotFoundError(category_id)
        return {
            "id": cat["id"],
            "name": cat["name"],
            "icon": cat["icon"] or "",
            "copy_key": cat["copy_key"] or "",
        }

    @staticmethod
    def _build_budget_response(row: dict) -> dict:
        """Build a standard budget response dict from a DB row."""
        from app.core.vault_row import open_row

        row = open_row(dict(row))
        amt = int(row.get("amount") or row.get("budget_amount") or 0)
        return {
            "id": row["id"],
            "month": row["month"],
            "category_id": row["category_id"],
            "category_name": row.get("category_name") or "",
            "category_icon": row.get("category_icon") or "",
            "copy_key": row.get("copy_key") or "",
            "amount": amt,
        }

    @staticmethod
    def _build_summary_item(row: dict, actual_spent: int) -> dict:
        """Build a single ``BudgetSummaryItem``-compatible dict."""
        budget_amount = int(row.get("amount") or row.get("budget_amount") or 0)
        percentage = (actual_spent / budget_amount * 100) if budget_amount > 0 else 0
        return {
            "id": row["id"],
            "category_id": row["category_id"],
            "category_name": row["category_name"],
            "category_icon": row.get("category_icon") or "📦",
            "copy_key": row.get("copy_key") or "",
            "budget_amount": budget_amount,
            "actual_spent": actual_spent,
            "percentage": round(percentage, 1),
            "remaining": budget_amount - actual_spent,
            "cycle_on": row["cycle_on"],
        }

    # ── Core CRUD ────────────────────────────────────────────────────

    async def list_budgets(self, user_id: int, month: str) -> list[dict]:
        """Return all budgets for *user_id* in *month* (ordered by amount desc)."""
        cursor = await self.db.execute(
            """SELECT b.id, b.month, b.category_id, b.vault_blob, b.amount_ord,
                      c.name AS category_name, c.icon AS category_icon, c.copy_key AS copy_key
               FROM budgets b
               LEFT JOIN categories c ON b.category_id = c.id
               WHERE b.month = ? AND b.user_id = ?
               ORDER BY b.amount_ord DESC NULLS LAST""",
            (month, user_id),
        )
        rows = await cursor.fetchall()
        return [self._build_budget_response(r) for r in rows]

    async def create_or_update_budget(
        self,
        user_id: int,
        month: str,
        category_id: int,
        amount: int,
        cycle_on_override: Optional[int] = None,
    ) -> dict:
        """Create or update (upsert) a budget.

        Returns the created/updated budget dict.
        Raises ``CategoryNotFoundError`` if *category_id* does not exist.
        """
        # Validate category exists
        cat = await self._validate_category(category_id)

        # Determine cycle day
        explicit_cycle = cycle_on_override  # may be None

        # Check for existing budget
        cursor = await self.db.execute(
            "SELECT id, cycle_on FROM budgets WHERE user_id = ? AND month = ? AND category_id = ?",
            (user_id, month, category_id),
        )
        existing = await cursor.fetchone()

        from app.core.vault_write import pack_budget

        packed = pack_budget(
            amount=int(amount),
            category_id=category_id,
            category_name=cat["name"],
        )

        if existing:
            cycle_on = (
                explicit_cycle
                if explicit_cycle is not None
                else existing["cycle_on"]
            )
            await self.db.execute(
                """UPDATE budgets SET vault_blob=?, amount_ord=?, category_trace=?,
                   cycle_on=? WHERE id=?""",
                (
                    packed["vault_blob"],
                    packed["amount_ord"],
                    packed.get("category_trace") or "",
                    cycle_on,
                    existing["id"],
                ),
            )
            budget_id = existing["id"]
        else:
            if explicit_cycle is not None:
                cycle_on = explicit_cycle
            else:
                cycle_on = await self._get_user_cycle_start_day(user_id)
            cursor = await self.db.execute(
                """INSERT INTO budgets
                   (user_id, month, category_id, cycle_on,
                    vault_blob, amount_ord, category_trace)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (
                    user_id,
                    month,
                    category_id,
                    cycle_on,
                    packed["vault_blob"],
                    packed["amount_ord"],
                    packed.get("category_trace") or "",
                ),
            )
            budget_id = cursor.lastrowid
            if budget_id is None:
                raise RuntimeError("Failed to create budget")

        return {
            "id": budget_id,
            "month": month,
            "category_id": category_id,
            "category_name": cat["name"],
            "category_icon": cat["icon"],
            "copy_key": cat.get("copy_key") or "",
            "amount": amount,
        }

    async def delete_budget(self, user_id: int, budget_id: int) -> None:
        """Delete a budget owned by *user_id*.

        Raises ``BudgetNotFoundError`` if the budget does not exist or
        does not belong to the user.
        """
        cursor = await self.db.execute(
            "SELECT id FROM budgets WHERE id = ? AND user_id = ?",
            (budget_id, user_id),
        )
        if not await cursor.fetchone():
            raise BudgetNotFoundError(budget_id)
        await self.db.execute("DELETE FROM budgets WHERE id = ?", (budget_id,))

    # ── Summary ──────────────────────────────────────────────────────

    async def get_summary(
        self,
        user_id: int,
        month: str,
        use_cycle: bool = False,
        d_from_override: Optional[str] = None,
        d_to_override: Optional[str] = None,
    ) -> dict:
        """Budgets vs actual spending for *month*.

        Each budget uses its own stored ``cycle_on`` for computing
        ``actual_spent`` when *use_cycle* is True.

        Returns a dict with ``items`` (list of summary item dicts) and
        ``uncategorized_expenses`` (list of unbudgeted expense dicts).
        """
        import calendar as _cal

        # Get all budgets for this month
        cursor = await self.db.execute(
            """SELECT b.id, b.category_id, b.cycle_on, b.vault_blob,
                      c.name AS category_name, c.icon AS category_icon, c.copy_key AS copy_key
               FROM budgets b
               LEFT JOIN categories c ON b.category_id = c.id
               WHERE b.month = ? AND b.user_id = ?
               ORDER BY b.amount_ord DESC NULLS LAST""",
            (month, user_id),
        )
        from app.core.vault_row import open_row

        rows = [open_row(dict(r)) for r in await cursor.fetchall()]

        results = []

        if not use_cycle:
            # ── Optimised path (calendar month) — single query ──
            d_from_str = f"{month}-01"
            y, mo = map(int, month.split("-"))
            last_day = _cal.monthrange(y, mo)[1]
            d_to_str = f"{month}-{last_day:02d}"

            budget_ids = [r["id"] for r in rows]
            cat_ids = [r["category_id"] for r in rows if r.get("category_id") is not None]

            actual_map: dict[int, int] = {}
            if cat_ids:
                from app.core.vault_ctx import current_dek, current_sealed
                from app.core.vault import category_trace
                from app.core.vault_row import ope_sum_to_plain

                if current_sealed() and current_dek():
                    dek = current_dek()
                    assert dek is not None
                    traces = [category_trace(dek, int(i)) for i in cat_ids]
                    ph = ",".join("?" for _ in traces)
                    cur = await self.db.execute(
                        f"""SELECT t.category_trace,
                                   COALESCE(SUM(t.amount_ord), 0) AS total, COUNT(*) AS count
                            FROM transactions t
                            WHERE t.user_id = ? AND t.type = 'expense'
                              AND t.category_trace IN ({ph})
                              AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                              AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
                            GROUP BY t.category_trace""",
                        (user_id, *traces, d_from_str, d_to_str),
                    )
                    inv = {category_trace(dek, int(i)): int(i) for i in cat_ids}
                    for r in await cur.fetchall():
                        cid = inv.get(r["category_trace"])
                        if cid is not None:
                            actual_map[cid] = ope_sum_to_plain(
                                dek, int(r["total"] or 0), int(r["count"] or 0)
                            )
                else:
                    cat_placeholders = ",".join("?" for _ in cat_ids)
                    cur = await self.db.execute(
                        f"""SELECT t.category_id,
                                   COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount_ord ELSE 0 END), 0)::bigint AS actual_spent
                            FROM transactions t
                            WHERE t.user_id = ?
                              AND t.category_id IN ({cat_placeholders})
                              AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                              AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
                            GROUP BY t.category_id""",
                        (user_id, *cat_ids, d_from_str, d_to_str),
                    )
                    for r in await cur.fetchall():
                        actual_map[r["category_id"]] = r["actual_spent"]

            for r in rows:
                actual_spent = actual_map.get(r["category_id"], 0)
                results.append(self._build_summary_item(r, actual_spent))
        else:
            # ── Cycle-aware path — per-budget query ──
            from app.core.vault_ctx import current_dek, current_sealed
            from app.core.vault import category_trace
            from app.core.vault_row import ope_sum_to_plain

            sealed = current_sealed()
            dek = current_dek()
            for r in rows:
                cycle_on = r["cycle_on"]
                d_from, d_to = get_cycle_range_for_month(month, cycle_on)
                d_from_str = d_from.isoformat()
                d_to_str = d_to.isoformat()
                cid = r.get("category_id")
                if sealed and dek is not None and cid is not None:
                    tr = category_trace(dek, int(cid))
                    cur = await self.db.execute(
                        """SELECT COALESCE(SUM(t.amount_ord), 0) AS total, COUNT(*) AS count
                           FROM transactions t
                           WHERE t.category_trace = ? AND t.user_id = ? AND t.type = 'expense'
                             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?""",
                        (tr, user_id, d_from_str, d_to_str),
                    )
                    row = await cur.fetchone()
                    actual_spent = ope_sum_to_plain(
                        dek, int(row["total"] or 0), int(row["count"] or 0)
                    ) if row else 0
                elif cid is None:
                    actual_spent = 0
                else:
                    cur = await self.db.execute(
                        """SELECT COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount_ord ELSE 0 END), 0) AS actual_spent
                           FROM transactions t
                           WHERE t.category_id = ? AND t.user_id = ?
                             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                             AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?""",
                        (cid, user_id, d_from_str, d_to_str),
                    )
                    row = await cur.fetchone()
                    actual_spent = row[0] if row is not None else 0
                results.append(self._build_summary_item(r, actual_spent))

        # ── Unbudgeted expenses ──
        uncategorized = await self._get_unbudgeted_expenses(
            user_id, month, use_cycle, d_from_override, d_to_override, rows
        )
        await self._attach_cat_meta(results)
        await self._attach_cat_meta(uncategorized)

        return {
            "items": results,
            "uncategorized_expenses": uncategorized,
        }

    async def _attach_cat_meta(self, items: list[dict]) -> None:
        ids = [i.get("category_id") for i in items if i.get("category_id") is not None]
        if not ids:
            return
        ph = ",".join("?" * len(ids))
        cur = await self.db.execute(
            f"SELECT id, icon, copy_key, name FROM categories WHERE id IN ({ph})",
            tuple(ids),
        )
        meta = {r["id"]: dict(r) for r in await cur.fetchall()}
        for i in items:
            m = meta.get(i.get("category_id")) or {}
            if m.get("icon"):
                i["category_icon"] = m["icon"]
            if m.get("copy_key"):
                i["copy_key"] = m["copy_key"]
            if m.get("name"):
                i["category_name"] = m["name"]

    async def _get_unbudgeted_expenses(
        self,
        user_id: int,
        month: str,
        use_cycle: bool,
        d_from_override: Optional[str],
        d_to_override: Optional[str],
        budget_rows: list,
    ) -> list[dict]:
        """Query expenses in categories that have no budget set."""
        import calendar as _cal

        # Determine overall date range
        if use_cycle:
            if d_from_override and d_to_override:
                uncat_d_from = d_from_override
                uncat_d_to = d_to_override
            else:
                cycle_day = await self._get_user_cycle_start_day(user_id)
                uf, ut = get_cycle_range_for_month(month, cycle_day)
                uncat_d_from = uf.isoformat()
                uncat_d_to = ut.isoformat()
        else:
            uncat_d_from = f"{month}-01"
            y, mo = map(int, month.split("-"))
            last_day = _cal.monthrange(y, mo)[1]
            uncat_d_to = f"{month}-{last_day:02d}"

        from app.core.vault_ctx import current_dek, current_sealed
        from app.core.vault_row import unpack_money

        if current_sealed() and current_dek():
            dek = current_dek()
            budgeted = {
                int(r["category_id"])
                for r in budget_rows
                if r.get("category_id") is not None
            }
            cur = await self.db.execute(
                """SELECT * FROM transactions t
                   WHERE t.user_id = ? AND t.type = 'expense'
                     AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                     AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?""",
                (user_id, uncat_d_from, uncat_d_to),
            )
            buckets: dict = {}
            for raw in await cur.fetchall():
                d = unpack_money(dek, dict(raw))
                cid = d.get("category_id")
                if cid is None or int(cid) in budgeted:
                    continue
                b = buckets.setdefault(
                    int(cid),
                    {"category_id": int(cid), "total": 0, "name": d.get("category_name") or ""},
                )
                b["total"] += int(d.get("amount") or 0)
                if d.get("category_name"):
                    b["name"] = d["category_name"]
            ids = list(buckets.keys())
            meta = {}
            if ids:
                ph = ",".join("?" * len(ids))
                mc = await self.db.execute(
                    f"SELECT id, name, icon, copy_key FROM categories WHERE id IN ({ph})",
                    tuple(ids),
                )
                meta = {r["id"]: dict(r) for r in await mc.fetchall()}
            uncategorized = []
            for cid, b in sorted(buckets.items(), key=lambda x: -x[1]["total"]):
                m = meta.get(cid) or {}
                uncategorized.append(
                    {
                        "category_id": cid,
                        "category_name": b["name"] or m.get("name") or "Unknown",
                        "category_icon": m.get("icon") or "strokeRoundedInvoice01",
                        "copy_key": m.get("copy_key") or "",
                        "total": b["total"],
                    }
                )
            return uncategorized

        budgeted_cat_ids = tuple(r["category_id"] for r in budget_rows if r.get("category_id") is not None)
        uncategorized = []

        if budgeted_cat_ids:
            placeholders = ",".join("?" * len(budgeted_cat_ids))
            ucur = await self.db.execute(
                f"""SELECT t.category_id, c.name AS category_name, c.icon AS category_icon,
                                   c.copy_key AS copy_key,
                                   COALESCE(SUM(t.amount_ord), 0)::bigint AS total
                    FROM transactions t
                    LEFT JOIN categories c ON t.category_id = c.id
                    WHERE t.user_id = ?
                      AND t.type = 'expense'
                      AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                      AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
                      AND t.category_id NOT IN ({placeholders})
                    GROUP BY t.category_id, c.name, c.icon, c.copy_key
                    ORDER BY total DESC""",
                (user_id, uncat_d_from, uncat_d_to, *budgeted_cat_ids),
            )
            for urow in await ucur.fetchall():
                uncategorized.append(
                    {
                        "category_id": urow["category_id"],
                        "category_name": urow["category_name"] or "Unknown",
                        "category_icon": urow["category_icon"] or "📦",
                        "copy_key": urow["copy_key"] or "",
                        "total": urow["total"],
                    }
                )
        else:
            # No budgets at all — all expense categories are unbudgeted
            ucur = await self.db.execute(
                """SELECT t.category_id, c.name AS category_name, c.icon AS category_icon,
                                 c.copy_key AS copy_key,
                                 COALESCE(SUM(t.amount_ord), 0)::bigint AS total
                   FROM transactions t
                   LEFT JOIN categories c ON t.category_id = c.id
                   WHERE t.user_id = ?
                     AND t.type = 'expense'
                     AND COALESCE(t.date, LEFT(t.created_at::text, 10)) >= ?
                     AND COALESCE(t.date, LEFT(t.created_at::text, 10)) <= ?
                   GROUP BY t.category_id, c.name, c.icon, c.copy_key
                   ORDER BY total DESC""",
                (user_id, uncat_d_from, uncat_d_to),
            )
            for urow in await ucur.fetchall():
                uncategorized.append(
                    {
                        "category_id": urow["category_id"],
                        "category_name": urow["category_name"] or "Unknown",
                        "category_icon": urow["category_icon"] or "📦",
                        "copy_key": urow["copy_key"] or "",
                        "total": urow["total"],
                    }
                )

        return uncategorized

    # ── Suggestions (AI) ─────────────────────────────────────────────

    async def get_suggestions(
        self,
        user_id: int,
        month: str,
        num_cycles: int = 3,
    ) -> dict:
        """Analyse historical spending and suggest budget amounts per category.

        Returns a dict with ``items`` (list of suggestion dicts),
        ``total_suggested``, ``total_income``, and ``warning``.
        """
        from app.utils.budget_ai import get_historical_spending

        cycle_start_day = await self._get_user_cycle_start_day(user_id)

        history = await get_historical_spending(
            self.db,
            user_id,
            cycle_start_day=cycle_start_day,
            num_cycles=num_cycles,
        )

        if not history:
            return {"items": [], "total_suggested": 0, "total_income": 0, "warning": ""}

        # Get existing budgets for this month
        cursor = await self.db.execute(
            "SELECT category_id, vault_blob FROM budgets WHERE month = ? AND user_id = ?",
            (month, user_id),
        )
        from app.core.vault_row import open_row

        existing: dict[int, int] = {}
        for r in await cursor.fetchall():
            d = open_row(dict(r))
            cid = d.get("category_id")
            if cid is None:
                continue
            existing[int(cid)] = int(d.get("amount") or 0)

        # Build suggestions
        items = []
        for h in history:
            cat_id = h["category_id"]
            if cat_id is None:
                continue
            raw = h["avg_amount"]
            # Round up to nearest 10k, min Rp10k
            suggested = ((raw + 9999) // 10000) * 10000
            if suggested < 10000:
                suggested = 10000

            items.append(
                {
                    "category_id": cat_id,
                    "category_name": h["category_name"],
                    "category_icon": h["category_icon"],
                    "copy_key": h.get("copy_key") or "",
                    "suggested_amount": suggested,
                    "historical_avg": h["avg_amount"],
                    "historical_max": h["max_amount"],
                    "months_analyzed": h["months_analyzed"],
                    "has_budget": cat_id in existing,
                    "existing_amount": existing.get(cat_id, 0),
                }
            )

        total_suggested = sum(i["suggested_amount"] for i in items if not i["has_budget"])

        # Fetch total income for the period
        d_from, d_to = get_cycle_range_for_month(month, cycle_start_day)
        from app.core.vault_ctx import current_dek, current_sealed
        from app.core.vault_row import ope_sum_to_plain

        if current_sealed() and current_dek():
            dek = current_dek()
            assert dek is not None
            cursor = await self.db.execute(
                """SELECT COALESCE(SUM(amount_ord), 0) AS total, COUNT(*) AS count
                   FROM transactions
                   WHERE user_id = ? AND type = 'income'
                     AND COALESCE(date, LEFT(created_at::text, 10)) BETWEEN ? AND ?""",
                (user_id, d_from.isoformat(), d_to.isoformat()),
            )
            row = await cursor.fetchone()
            total_income = ope_sum_to_plain(
                dek, int(row["total"] or 0), int(row["count"] or 0)
            ) if row else 0
        else:
            cursor = await self.db.execute(
                """SELECT COALESCE(SUM(amount_ord), 0) FROM transactions
                   WHERE user_id = ? AND type = 'income'
                     AND COALESCE(date, LEFT(created_at::text, 10)) BETWEEN ? AND ?""",
                (user_id, d_from.isoformat(), d_to.isoformat()),
            )
            row = await cursor.fetchone()
            total_income = row[0] if row else 0

        warning = ""
        if total_income > 0 and total_suggested > total_income:
            warning = (
                f"Usulan anggaran (Rp{total_suggested:,}) lebih besar dari pemasukan "
                f"(Rp{total_income:,}). Kurangi beberapa ya."
            )

        return {
            "items": items,
            "total_suggested": total_suggested,
            "total_income": total_income,
            "warning": warning,
        }

    # ── Health / Projection ──────────────────────────────────────────

    async def get_health(
        self,
        user_id: int,
        month: str,
    ) -> dict:
        """Budget health forecast — projected end-of-cycle spending vs budget.

        Delegates to ``app.utils.budget_ai.get_projection``.
        """
        cycle_start_day = await self._get_user_cycle_start_day(user_id)
        d_from, d_to = get_cycle_range_for_month(month, cycle_start_day)

        from app.utils.budget_ai import get_projection

        return await get_projection(
            self.db,
            user_id,
            cycle_start_day,
            d_from.isoformat(),
            d_to.isoformat(),
        )
