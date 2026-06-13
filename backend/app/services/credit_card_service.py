"""Credit card service — pure business logic, no FastAPI dependency."""

from app.database import CursorWrapper
from app.schemas.credit_card import (
    CreditCardCreate,
    CreditCardUpdate,
    CreditCardInstallmentCreate,
    CreditCardTransactionCreate,
    NextMonthProjection,
)


# ── Domain exceptions ───────────────────────────────────────────────


class CreditCardNotFoundError(Exception):
    """Raised when a credit card does not exist."""

    def __init__(self, card_id: int) -> None:
        self.card_id = card_id
        super().__init__(f"Credit card {card_id} not found")


class CreditCardForbiddenError(Exception):
    """Raised when the user is not authorized to access a credit card."""

    def __init__(self, card_id: int) -> None:
        self.card_id = card_id
        super().__init__(f"Not authorized to access credit card {card_id}")


class TransactionNotFoundError(Exception):
    """Raised when a transaction does not exist."""

    def __init__(self, txn_id: int) -> None:
        self.txn_id = txn_id
        super().__init__(f"Transaction {txn_id} not found")


class InstallmentNotFoundError(Exception):
    """Raised when an installment does not exist."""

    def __init__(self, inst_id: int) -> None:
        self.inst_id = inst_id
        super().__init__(f"Installment {inst_id} not found")


# ── Service ─────────────────────────────────────────────────────────


class CreditCardService:
    """Service layer for credit card operations.

    Encapsulates all business logic and data access for credit cards,
    transactions, and installments. Instantiated with a ``CursorWrapper``
    obtained from the FastAPI ``get_db`` dependency.
    """

    def __init__(self, db: CursorWrapper) -> None:
        self.db = db

    # ── helpers ──────────────────────────────────────────────────────

    async def get_card_for_user(self, card_id: int, user_id: int) -> dict:
        """Retrieve a credit card, verifying user ownership or household membership.

        Raises ``CreditCardNotFoundError`` if the card doesn't exist or
        ``CreditCardForbiddenError`` if the user has no access rights.
        """
        cursor = await self.db.execute(
            "SELECT * FROM credit_cards WHERE id = ?", (card_id,)
        )
        card = await cursor.fetchone()
        if not card:
            raise CreditCardNotFoundError(card_id)
        card = dict(card)
        if card["user_id"] == user_id:
            return card
        # Allow household members if card has household_id
        if card.get("household_id"):
            cursor = await self.db.execute(
                "SELECT 1 FROM household_members WHERE user_id = ? AND household_id = ?",
                (user_id, card["household_id"]),
            )
            if await cursor.fetchone():
                return card
        raise CreditCardForbiddenError(card_id)

    # ── Credit Cards CRUD ────────────────────────────────────────────

    async def create_credit_card(
        self, data: CreditCardCreate, user_id: int
    ) -> dict:
        """Create a new credit card for the given user."""
        cursor = await self.db.execute(
            """INSERT INTO credit_cards
               (user_id, name, card_number_last4, billing_date, due_date,
                credit_limit, household_id)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (
                user_id,
                data.name,
                data.card_number_last4,
                data.billing_date,
                data.due_date,
                data.credit_limit,
                data.household_id,
            ),
        )
        card_id = cursor.lastrowid
        return await self.get_card_for_user(card_id, user_id)

    async def list_credit_cards(self, user_id: int) -> list[dict]:
        """List all credit cards for the user, including household shared cards."""
        cursor = await self.db.execute(
            """SELECT
                   cc.id, cc.user_id, cc.name, cc.card_number_last4,
                   cc.billing_date, cc.due_date, cc.credit_limit,
                   cc.created_at, cc.household_id, cc.display_order,
                   COALESCE(active_inst.cnt, 0) AS active_installments
               FROM credit_cards cc
               LEFT JOIN (
                   SELECT card_id, COUNT(*) AS cnt
                   FROM credit_card_installments
                   WHERE remaining_months > 0
                   GROUP BY card_id
               ) active_inst ON active_inst.card_id = cc.id
               WHERE cc.user_id = ?
                  OR cc.household_id IN (
                      SELECT household_id FROM household_members WHERE user_id = ?
                  )
               ORDER BY cc.display_order ASC, cc.created_at DESC""",
            (user_id, user_id),
        )
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]

    async def get_credit_card(self, card_id: int, user_id: int) -> dict:
        """Get a single credit card with its transactions and installments."""
        card = await self.get_card_for_user(card_id, user_id)

        # Fetch transactions
        txn_cursor = await self.db.execute(
            """SELECT id, card_id, description, amount, category_id,
                      transaction_date, is_installment, installment_id, created_at
               FROM credit_card_transactions
               WHERE card_id = ?
               ORDER BY transaction_date DESC""",
            (card_id,),
        )
        transactions = [dict(r) for r in await txn_cursor.fetchall()]

        # Fetch installments
        inst_cursor = await self.db.execute(
            """SELECT id, card_id, description, total_amount, monthly_amount,
                      total_months,
                      GREATEST(0, total_months - (
                          (EXTRACT(YEAR FROM CURRENT_DATE)::integer * 12
                           + EXTRACT(MONTH FROM CURRENT_DATE)::integer)
                          - (CAST(SUBSTR(start_month, 1, 4) AS integer) * 12
                             + CAST(SUBSTR(start_month, 6, 2) AS integer))
                      )) AS remaining_months,
                      start_month, created_at
               FROM credit_card_installments
               WHERE card_id = ?
               ORDER BY start_month DESC""",
            (card_id,),
        )
        installments = [dict(r) for r in await inst_cursor.fetchall()]

        return {
            **card,
            "transactions": transactions,
            "installments": installments,
        }

    async def update_credit_card(
        self, card_id: int, data: CreditCardUpdate, user_id: int
    ) -> dict:
        """Update a credit card's non-sensitive fields."""

        await self.get_card_for_user(card_id, user_id)

        fields: list[str] = []
        params: list = []

        if data.name is not None:
            fields.append("name = ?")
            params.append(data.name)
        if data.billing_date is not None:
            fields.append("billing_date = ?")
            params.append(data.billing_date)
        if data.due_date is not None:
            fields.append("due_date = ?")
            params.append(data.due_date)
        if data.credit_limit is not None:
            fields.append("credit_limit = ?")
            params.append(data.credit_limit)

        if not fields:
            raise ValueError("No fields to update")

        params.append(card_id)
        await self.db.execute(
            f"UPDATE credit_cards SET {', '.join(fields)} WHERE id = ?",
            tuple(params),
        )

        return await self.get_card_for_user(card_id, user_id)

    async def delete_credit_card(self, card_id: int, user_id: int) -> None:
        """Delete a credit card. Transactions and installments cascade via FK."""
        await self.get_card_for_user(card_id, user_id)
        await self.db.execute(
            "DELETE FROM credit_cards WHERE id = ?", (card_id,)
        )

    # ── Transactions ──────────────────────────────────────────────

    async def create_transaction(
        self, card_id: int, data: CreditCardTransactionCreate, user_id: int
    ) -> dict:
        """Add a transaction to a credit card."""
        await self.get_card_for_user(card_id, user_id)

        cursor = await self.db.execute(
            """INSERT INTO credit_card_transactions
               (card_id, description, amount, category_id,
                transaction_date, is_installment, installment_id)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (
                card_id,
                data.description,
                data.amount,
                data.category_id,
                data.transaction_date,
                1 if data.is_installment else 0,
                data.installment_id,
            ),
        )
        txn_id = cursor.lastrowid

        txn_cursor = await self.db.execute(
            """SELECT id, card_id, description, amount, category_id,
                      transaction_date, is_installment, installment_id, created_at
               FROM credit_card_transactions WHERE id = ?""",
            (txn_id,),
        )
        row = await txn_cursor.fetchone()
        return dict(row)

    async def list_transactions(self, card_id: int, user_id: int) -> list[dict]:
        """List all transactions for a credit card."""
        await self.get_card_for_user(card_id, user_id)

        cursor = await self.db.execute(
            """SELECT id, card_id, description, amount, category_id,
                      transaction_date, is_installment, installment_id, created_at
               FROM credit_card_transactions
               WHERE card_id = ?
               ORDER BY transaction_date DESC""",
            (card_id,),
        )
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]

    async def delete_transaction(
        self, card_id: int, txn_id: int, user_id: int
    ) -> None:
        """Delete a transaction from a credit card."""
        await self.get_card_for_user(card_id, user_id)

        cursor = await self.db.execute(
            "SELECT id FROM credit_card_transactions WHERE id = ? AND card_id = ?",
            (txn_id, card_id),
        )
        if not await cursor.fetchone():
            raise TransactionNotFoundError(txn_id)

        await self.db.execute(
            "DELETE FROM credit_card_transactions WHERE id = ?", (txn_id,)
        )

    # ── Installments ────────────────────────────────────────────

    async def create_installment(
        self, card_id: int, data: CreditCardInstallmentCreate, user_id: int
    ) -> dict:
        """Add an installment plan to a credit card."""
        await self.get_card_for_user(card_id, user_id)

        cursor = await self.db.execute(
            """INSERT INTO credit_card_installments
               (card_id, description, total_amount, monthly_amount,
                total_months, remaining_months, start_month)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (
                card_id,
                data.description,
                data.total_amount,
                data.monthly_amount,
                data.total_months,
                data.total_months,
                data.start_month,
            ),
        )
        inst_id = cursor.lastrowid

        inst_cursor = await self.db.execute(
            """SELECT id, card_id, description, total_amount, monthly_amount,
                      total_months,
                      GREATEST(0, total_months - (
                          (EXTRACT(YEAR FROM CURRENT_DATE)::integer * 12
                           + EXTRACT(MONTH FROM CURRENT_DATE)::integer)
                          - (CAST(SUBSTR(start_month, 1, 4) AS integer) * 12
                             + CAST(SUBSTR(start_month, 6, 2) AS integer))
                      )) AS remaining_months,
                      start_month, created_at
               FROM credit_card_installments WHERE id = ?""",
            (inst_id,),
        )
        row = await inst_cursor.fetchone()
        return dict(row)

    async def list_installments(self, card_id: int, user_id: int) -> list[dict]:
        """List all installment plans for a credit card."""
        await self.get_card_for_user(card_id, user_id)

        cursor = await self.db.execute(
            """SELECT id, card_id, description, total_amount, monthly_amount,
                      total_months,
                      GREATEST(0, total_months - (
                          (EXTRACT(YEAR FROM CURRENT_DATE)::integer * 12
                           + EXTRACT(MONTH FROM CURRENT_DATE)::integer)
                          - (CAST(SUBSTR(start_month, 1, 4) AS integer) * 12
                             + CAST(SUBSTR(start_month, 6, 2) AS integer))
                      )) AS remaining_months,
                      start_month, created_at
               FROM credit_card_installments
               WHERE card_id = ?
               ORDER BY start_month DESC""",
            (card_id,),
        )
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]

    async def delete_installment(
        self, card_id: int, inst_id: int, user_id: int
    ) -> None:
        """Delete an installment plan."""
        await self.get_card_for_user(card_id, user_id)

        cursor = await self.db.execute(
            "SELECT id FROM credit_card_installments WHERE id = ? AND card_id = ?",
            (inst_id, card_id),
        )
        if not await cursor.fetchone():
            raise InstallmentNotFoundError(inst_id)

        await self.db.execute(
            "DELETE FROM credit_card_installments WHERE id = ?", (inst_id,)
        )

    # ── Next Month Projection ───────────────────────────────────

    async def next_month_projection(self, user_id: int) -> NextMonthProjection:
        """Aggregate this month's non-installment transactions and active
        installments per card for next month's projection."""
        cursor = await self.db.execute(
            """SELECT
                   cc.id AS card_id,
                   cc.name AS card_name,
                   COALESCE(SUM(combined.monthly), 0) AS total_monthly
               FROM credit_cards cc
               LEFT JOIN (
                   -- current month non-installment transactions
                   SELECT card_id, amount AS monthly
                   FROM credit_card_transactions
                   WHERE is_installment = 0
                     AND EXTRACT(YEAR FROM transaction_date::date)
                         = EXTRACT(YEAR FROM CURRENT_DATE)
                     AND EXTRACT(MONTH FROM transaction_date::date)
                         = EXTRACT(MONTH FROM CURRENT_DATE)
                   UNION ALL
                   -- active installments
                   SELECT cci.card_id, cci.monthly_amount AS monthly
                   FROM credit_card_installments cci
                   WHERE cci.total_months > (
                       EXTRACT(YEAR FROM CURRENT_DATE)::integer * 12
                       + EXTRACT(MONTH FROM CURRENT_DATE)::integer
                       - (CAST(SUBSTR(cci.start_month, 1, 4) AS integer) * 12
                          + CAST(SUBSTR(cci.start_month, 6, 2) AS integer))
                   )
               ) combined ON combined.card_id = cc.id
               WHERE cc.user_id = ?
                  OR cc.household_id IN (
                      SELECT household_id FROM household_members WHERE user_id = ?
                  )
               GROUP BY cc.id, cc.name
               ORDER BY cc.name""",
            (user_id, user_id),
        )
        rows = await cursor.fetchall()

        per_card: list[dict] = []
        grand_total = 0
        total_installments = 0

        for r in rows:
            monthly = int(r["total_monthly"])
            if monthly > 0:
                total_installments += 1
            grand_total += monthly
            per_card.append(
                {
                    "card_id": r["card_id"],
                    "card_name": r["card_name"],
                    "total": monthly,
                }
            )

        # Count distinct active installments dynamically (remaining > 0)
        count_cursor = await self.db.execute(
            """SELECT COUNT(*) AS cnt
               FROM credit_card_installments cci
               JOIN credit_cards cc ON cc.id = cci.card_id
               WHERE (cc.user_id = ?
                  OR cc.household_id IN (
                      SELECT household_id FROM household_members WHERE user_id = ?
                  ))
                 AND cci.total_months > (
                     EXTRACT(YEAR FROM CURRENT_DATE)::integer * 12
                     + EXTRACT(MONTH FROM CURRENT_DATE)::integer
                     - (CAST(SUBSTR(cci.start_month, 1, 4) AS integer) * 12
                        + CAST(SUBSTR(cci.start_month, 6, 2) AS integer))
                 )""",
            (user_id, user_id),
        )
        count_row = await count_cursor.fetchone()
        if count_row:
            total_installments = count_row["cnt"]

        return NextMonthProjection(
            total_installments=total_installments,
            total_expected=grand_total,
            per_card=per_card,
        )
