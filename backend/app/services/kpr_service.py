"""KPR (Mortgage) service layer — business logic extracted from router.

Each method encapsulates a complete business operation for the KPR domain.
Errors are reported via KPRServiceError so the router can convert to HTTPException.
No FastAPI dependency.
"""

from __future__ import annotations

from typing import Optional

from app.database import CursorWrapper
from app.schemas.kpr import (
    KPRSimulationCreate,
    KPRSimulationUpdate,
    ExtraPaymentPreviewRequest,
    ExtraPaymentCreate,
)
from app.services.kpr_engine import (
    calculate_kpr,
    simulate_summary,
    apply_extra_payment,
    preview_extra_payment,
    RatePeriod,
    MonthlySchedule,
)


class KPRServiceError(Exception):
    """Error from KPR service layer. Router converts to HTTPException."""

    def __init__(self, message: str, status_code: int = 400) -> None:
        self.message = message
        self.status_code = status_code
        super().__init__(message)


class KPRService:
    """Business logic for KPR simulations and extra payments."""

    # ── Shared helpers ─────────────────────────────────────────

    @staticmethod
    async def get_simulation_for_user(
        db: CursorWrapper, sim_id: int, user_id: int,
    ) -> dict:
        """Fetch a simulation row and verify ownership.

        Raises KPRServiceError with 404 or 403 status if not found/not authorised.
        """
        cursor = await db.execute(
            "SELECT * FROM kpr_simulations WHERE id = ?", (sim_id,),
        )
        sim = await cursor.fetchone()
        if not sim:
            raise KPRServiceError("Simulation not found", status_code=404)
        sim = dict(sim)
        if sim["user_id"] == user_id:
            return sim
        # Allow household members if simulation has household_id
        if sim.get("household_id"):
            cursor = await db.execute(
                "SELECT 1 FROM household_members WHERE user_id = ? AND household_id = ?",
                (user_id, sim["household_id"]),
            )
            if await cursor.fetchone():
                return sim
        raise KPRServiceError("Not your simulation", status_code=403)

    # ── Simulation CRUD ────────────────────────────────────────

    @staticmethod
    async def create_simulation(
        db: CursorWrapper,
        data: KPRSimulationCreate,
        user_id: int,
    ) -> dict:
        """Create a KPR simulation with full amortisation schedule.

        Returns a dict with keys suitable for KPRSimulationDetailOut.
        """
        total_loan = data.property_price - data.down_payment

        # Verify household_id belongs to the user if sharing
        if data.household_id is not None:
            cursor = await db.execute(
                "SELECT 1 FROM household_members WHERE user_id = ? AND household_id = ?",
                (user_id, data.household_id),
            )
            if not await cursor.fetchone():
                raise KPRServiceError(
                    "You are not a member of this household",
                    status_code=403,
                )

        # Convert API rate periods to engine dataclasses
        rate_periods = [
            RatePeriod(
                period_start=rp.period_start,
                period_end=rp.period_end,
                interest_rate=rp.interest_rate,
                rate_type=rp.rate_type,
            )
            for rp in data.rate_periods
        ]

        async with db.transaction():
            # 1. Insert simulation
            cursor = await db.execute(
                """INSERT INTO kpr_simulations
                   (user_id, name, property_price, down_payment, total_loan,
                    tenor_months, interest_type, start_month, start_year, due_date,
                    household_id, base_interest_rate, graduated_increment, graduated_every_months)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    user_id,
                    data.name,
                    data.property_price,
                    data.down_payment,
                    total_loan,
                    data.tenor_months,
                    data.interest_type,
                    data.start_month,
                    data.start_year,
                    data.due_date,
                    data.household_id,
                    data.base_interest_rate,
                    data.graduated_increment,
                    data.graduated_every_months,
                ),
            )
            sim_id = cursor.lastrowid

            # 2. Insert rate periods if provided
            for rp in data.rate_periods:
                await db.execute(
                    """INSERT INTO kpr_rate_periods
                       (simulation_id, period_start, period_end, interest_rate, rate_type)
                       VALUES (?, ?, ?, ?, ?)""",
                    (sim_id, rp.period_start, rp.period_end, rp.interest_rate, rp.rate_type),
                )

            # 3. Calculate schedule via engine
            schedule = calculate_kpr(
                total_loan=total_loan,
                tenor_months=data.tenor_months,
                rate_periods=rate_periods if rate_periods else None,
                interest_type=data.interest_type,
                base_interest_rate=data.base_interest_rate,
                graduated_increment=data.graduated_increment,
                graduated_every_months=data.graduated_every_months,
            )

            # 4. Insert schedule items
            for item in schedule:
                await db.execute(
                    """INSERT INTO kpr_monthly_schedules
                       (simulation_id, month_number, payment, principal, interest,
                        remaining_balance, rate_type, interest_rate)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                    (
                        sim_id,
                        item.month_number,
                        item.payment,
                        item.principal,
                        item.interest,
                        item.remaining_balance,
                        item.rate_type,
                        item.interest_rate,
                    ),
                )

        # Build response data
        summary = simulate_summary(schedule)
        refetched = await KPRService.get_simulation_for_user(db, sim_id, user_id)

        return {
            **refetched,
            "total_interest": summary["total_interest"],
            "monthly_payment": summary["monthly_payment"],
            "current_month_number": 1,
            "current_month_payment": schedule[0].payment if schedule else 0,
            "current_remaining_balance": total_loan,
            "schedule": [
                {
                    "month_number": s.month_number,
                    "payment": s.payment,
                    "principal": s.principal,
                    "interest": s.interest,
                    "remaining_balance": s.remaining_balance,
                    "rate_type": s.rate_type,
                    "interest_rate": s.interest_rate,
                }
                for s in schedule
            ],
            "summary": summary,
        }

    @staticmethod
    async def list_simulations(
        db: CursorWrapper,
        user_id: int,
    ) -> list[dict]:
        """List all KPR simulations accessible to the user (metadata only)."""
        cursor = await db.execute(
            """SELECT
                   ks.id, ks.user_id, ks.name, ks.property_price, ks.down_payment,
                   ks.total_loan, ks.tenor_months, ks.interest_type, ks.created_at,
                   ks.start_month, ks.start_year, ks.due_date,
                   ks.household_id, ks.display_order,
                   COALESCE(agg.total_interest, 0) AS total_interest,
                   COALESCE(agg.monthly_payment, 0) AS monthly_payment,
                   COALESCE(agg.current_month_number, 1) AS current_month_number,
                   COALESCE(agg.current_month_payment, 0) AS current_month_payment,
                   COALESCE(agg.current_remaining_balance, 0) AS current_remaining_balance
               FROM kpr_simulations ks
               LEFT JOIN (
                   SELECT
                       simulation_id,
                       SUM(interest) AS total_interest,
                       MAX(CASE WHEN month_number = 1 THEN payment ELSE 0 END) AS monthly_payment,
                       MAX(CASE WHEN month_number = (
                           SELECT GREATEST(1, LEAST(
                               (EXTRACT(YEAR FROM CURRENT_DATE) - ks2.start_year) * 12
                               + (EXTRACT(MONTH FROM CURRENT_DATE) - ks2.start_month) + 1,
                               ks2.tenor_months
                           ))
                           FROM kpr_simulations ks2 WHERE ks2.id = kms.simulation_id
                       ) THEN payment ELSE 0 END) AS current_month_payment,
                       MAX(CASE WHEN month_number = (
                           SELECT CASE WHEN cm.current_month <= 1 THEN 0
                           ELSE cm.current_month - 1 END
                           FROM kpr_simulations ks3
                           CROSS JOIN LATERAL (
                               SELECT LEAST(
                                   (EXTRACT(YEAR FROM CURRENT_DATE) - ks3.start_year) * 12
                                   + (EXTRACT(MONTH FROM CURRENT_DATE) - ks3.start_month) + 1,
                                   ks3.tenor_months
                               ) AS current_month
                           ) cm
                           WHERE ks3.id = kms.simulation_id
                       ) THEN remaining_balance ELSE 0 END) AS current_remaining_balance,
                       (
                           SELECT GREATEST(1, LEAST(
                               (EXTRACT(YEAR FROM CURRENT_DATE) - ks3.start_year) * 12
                               + (EXTRACT(MONTH FROM CURRENT_DATE) - ks3.start_month) + 1,
                               ks3.tenor_months
                           ))
                           FROM kpr_simulations ks3 WHERE ks3.id = kms.simulation_id
                       ) AS current_month_number
                   FROM kpr_monthly_schedules kms
                   GROUP BY simulation_id
               ) agg ON agg.simulation_id = ks.id
               WHERE ks.user_id = ?
                  OR ks.household_id IN (
                      SELECT household_id FROM household_members WHERE user_id = ?
                  )
               ORDER BY ks.display_order ASC, ks.created_at DESC""",
            (user_id, user_id),
        )
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]

    @staticmethod
    async def get_simulation_detail(
        db: CursorWrapper,
        sim_id: int,
        user_id: int,
    ) -> dict:
        """Get a single simulation with full schedule and summary."""
        sim = await KPRService.get_simulation_for_user(db, sim_id, user_id)

        cursor = await db.execute(
            """SELECT month_number, payment, principal, interest,
                      remaining_balance, rate_type, interest_rate
               FROM kpr_monthly_schedules
               WHERE simulation_id = ?
               ORDER BY month_number""",
            (sim_id,),
        )
        rows = await cursor.fetchall()
        schedule_data = [dict(r) for r in rows]

        # Build summary from the stored schedule
        engine_items = [
            MonthlySchedule(
                month_number=s["month_number"],
                payment=s["payment"],
                principal=s["principal"],
                interest=s["interest"],
                remaining_balance=s["remaining_balance"],
                rate_type=s["rate_type"],
                interest_rate=s["interest_rate"],
            )
            for s in schedule_data
        ]
        summary = simulate_summary(engine_items)

        return {
            **sim,
            "schedule": schedule_data,
            "summary": summary,
        }

    @staticmethod
    async def update_simulation(
        db: CursorWrapper,
        sim_id: int,
        data: KPRSimulationUpdate,
        user_id: int,
    ) -> dict:
        """Update simulation metadata.

        Returns the updated row as a dict.
        """
        await KPRService.get_simulation_for_user(db, sim_id, user_id)

        # Build dynamic UPDATE — only set non-None fields
        fields: list[str] = []
        params: list = []

        if data.name is not None:
            fields.append("name = ?")
            params.append(data.name)
        if data.property_price is not None:
            fields.append("property_price = ?")
            params.append(data.property_price)
        if data.down_payment is not None:
            fields.append("down_payment = ?")
            params.append(data.down_payment)
        if data.tenor_months is not None:
            fields.append("tenor_months = ?")
            params.append(data.tenor_months)

        # Recalculate total_loan if either property_price or down_payment changed
        prop_provided = data.property_price is not None
        dp_provided = data.down_payment is not None
        if prop_provided or dp_provided:
            cursor = await db.execute(
                "SELECT property_price, down_payment FROM kpr_simulations WHERE id = ?",
                (sim_id,),
            )
            current = dict(await cursor.fetchone())
            prop = data.property_price if prop_provided else current["property_price"]
            dp = data.down_payment if dp_provided else current["down_payment"]
            new_total = prop - dp
            fields.append("total_loan = ?")
            params.append(new_total)

        if not fields:
            raise KPRServiceError("No fields to update", status_code=400)

        params.append(sim_id)
        await db.execute(
            f"UPDATE kpr_simulations SET {', '.join(fields)} WHERE id = ?",
            tuple(params),
        )

        refetched = await KPRService.get_simulation_for_user(db, sim_id, user_id)
        return refetched

    @staticmethod
    async def delete_simulation(
        db: CursorWrapper,
        sim_id: int,
        user_id: int,
    ) -> None:
        """Delete a simulation. Schedule and rate periods cascade via FK."""
        await KPRService.get_simulation_for_user(db, sim_id, user_id)
        await db.execute(
            "DELETE FROM kpr_simulations WHERE id = ?",
            (sim_id,),
        )

    # ── Schedule ───────────────────────────────────────────────

    @staticmethod
    async def get_simulation_schedule(
        db: CursorWrapper,
        sim_id: int,
        user_id: int,
        month: Optional[int] = None,
    ) -> list[dict] | dict:
        """Get schedule items for a simulation.

        If *month* is given returns a single schedule dict (or raises 404).
        Otherwise returns a list of schedule dicts.
        """
        await KPRService.get_simulation_for_user(db, sim_id, user_id)

        if month is not None:
            cursor = await db.execute(
                """SELECT month_number, payment, principal, interest,
                          remaining_balance, rate_type, interest_rate
                   FROM kpr_monthly_schedules
                   WHERE simulation_id = ? AND month_number = ?
                   ORDER BY month_number""",
                (sim_id, month),
            )
            row = await cursor.fetchone()
            if not row:
                raise KPRServiceError("Month not found in schedule", status_code=404)
            return dict(row)
        else:
            cursor = await db.execute(
                """SELECT month_number, payment, principal, interest,
                          remaining_balance, rate_type, interest_rate
                   FROM kpr_monthly_schedules
                   WHERE simulation_id = ?
                   ORDER BY month_number""",
                (sim_id,),
            )
            rows = await cursor.fetchall()
            return [dict(r) for r in rows]

    # ── Extra Payments ─────────────────────────────────────────

    @staticmethod
    async def preview_extra_payment(
        db: CursorWrapper,
        sim_id: int,
        data: ExtraPaymentPreviewRequest,
        user_id: int,
    ) -> dict:
        """Preview both reduction options for an extra payment (no DB write)."""
        sim = await KPRService.get_simulation_for_user(db, sim_id, user_id)

        # Load schedule from DB
        cursor = await db.execute(
            """SELECT month_number, payment, principal, interest,
                      remaining_balance, rate_type, interest_rate
               FROM kpr_monthly_schedules
               WHERE simulation_id = ? ORDER BY month_number""",
            (sim_id,),
        )
        rows = await cursor.fetchall()
        if not rows:
            raise KPRServiceError(
                "No schedule found. Generate schedule first.",
                status_code=400,
            )

        schedule = [MonthlySchedule(**dict(r)) for r in rows]

        if data.apply_month < 1 or data.apply_month > len(schedule):
            raise KPRServiceError(
                f"apply_month must be between 1 and {len(schedule)}",
                status_code=400,
            )

        preview = preview_extra_payment(
            schedule=schedule,
            extra_amount=data.amount,
            apply_month=data.apply_month,
            start_month=sim.get("start_month", 1),
            start_year=sim.get("start_year", 2026),
        )

        def _to_option(result) -> dict:
            return {
                "new_installment": result.new_installment,
                "new_tenor": result.new_remaining_months,
                "total_interest_paid": result.total_interest_paid,
                "interest_saved": result.total_interest_saved,
                "end_date": result.new_end_date,
            }

        comparison = {
            "installment_difference": preview.option_tenor.new_installment - preview.option_installment.new_installment,
            "months_saved_difference": preview.option_installment.new_remaining_months - preview.option_tenor.new_remaining_months,
        }

        return {
            "option_installment": _to_option(preview.option_installment),
            "option_tenor": _to_option(preview.option_tenor),
            "comparison": comparison,
        }

    @staticmethod
    async def create_extra_payment(
        db: CursorWrapper,
        sim_id: int,
        data: ExtraPaymentCreate,
        user_id: int,
    ) -> dict:
        """Commit an extra payment, regenerate schedule, store record."""
        sim = await KPRService.get_simulation_for_user(db, sim_id, user_id)

        # 1. Regenerate original schedule from KPR params (not from DB,
        #    which may already have previous extra payments applied)
        total_loan = sim["total_loan"]
        tenor_months = sim["tenor_months"]
        interest_type = sim["interest_type"]
        base_rate = sim.get("base_interest_rate", 0.075)
        grad_inc = sim.get("graduated_increment", 0.005)
        grad_every = sim.get("graduated_every_months", 12)
        start_month = sim.get("start_month", 1)
        start_year = sim.get("start_year", 2026)

        # Load rate periods if mix type
        rate_periods: list[RatePeriod] = []
        if interest_type == "mix":
            cursor = await db.execute(
                "SELECT period_start, period_end, interest_rate, rate_type FROM kpr_rate_periods WHERE simulation_id = ? ORDER BY period_start",
                (sim_id,),
            )
            rate_periods = [RatePeriod(**dict(r)) for r in await cursor.fetchall()]

        original_schedule = calculate_kpr(
            total_loan=total_loan,
            tenor_months=tenor_months,
            rate_periods=rate_periods if rate_periods else None,
            interest_type=interest_type,
            base_interest_rate=base_rate,
            graduated_increment=grad_inc,
            graduated_every_months=grad_every,
        )

        # 2. Load existing extra payments sorted chronologically
        cursor = await db.execute(
            "SELECT * FROM kpr_extra_payments WHERE simulation_id = ? ORDER BY apply_month, id",
            (sim_id,),
        )
        existing_extras = [dict(r) for r in await cursor.fetchall()]

        # Validate apply_month range
        min_month = 1
        if existing_extras:
            min_month = max(ep["apply_month"] for ep in existing_extras)
        if data.apply_month < min_month or data.apply_month > tenor_months:
            raise KPRServiceError(
                f"apply_month must be between {min_month} and {tenor_months}",
                status_code=400,
            )

        # 3. Apply all existing extra payments in chronological order
        #    to get the current state before applying the new one
        current_schedule = original_schedule
        for ep in existing_extras:
            ep_result = apply_extra_payment(
                schedule=current_schedule,
                extra_amount=ep["amount"],
                apply_month=ep["apply_month"],
                reduction_type=ep["reduction_type"],
                start_month=start_month,
                start_year=start_year,
            )
            current_schedule = ep_result.schedule

        # 4. Validate new apply_month against current schedule length
        if data.apply_month > len(current_schedule):
            raise KPRServiceError(
                f"apply_month {data.apply_month} exceeds current schedule length ({len(current_schedule)}) after existing extra payments",
                status_code=400,
            )

        # 5. Apply the new extra payment to the current schedule
        result = apply_extra_payment(
            schedule=current_schedule,
            extra_amount=data.amount,
            apply_month=data.apply_month,
            reduction_type=data.reduction_type,
            start_month=start_month,
            start_year=start_year,
        )

        async with db.transaction():
            # Store the extra payment record
            cursor = await db.execute(
                """INSERT INTO kpr_extra_payments
                   (simulation_id, amount, apply_month,
                    reduction_type, old_remaining_balance, new_remaining_balance,
                    old_remaining_months, new_remaining_months, old_installment,
                    new_installment, total_interest_saved, original_end_date, new_end_date)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    simulation_id, data.amount,
                    data.apply_month, data.reduction_type,
                    result.old_remaining_balance, result.new_remaining_balance,
                    result.old_remaining_months, result.new_remaining_months,
                    result.old_installment, result.new_installment,
                    result.total_interest_saved,
                    result.original_end_date, result.new_end_date,
                ),
            )
            extra_id = cursor.lastrowid or 0

            # Delete old schedule and insert new one
            await db.execute(
                "DELETE FROM kpr_monthly_schedules WHERE simulation_id = ?",
                (sim_id,),
            )
            for item in result.schedule:
                await db.execute(
                    """INSERT INTO kpr_monthly_schedules
                       (simulation_id, month_number, payment, principal, interest,
                        remaining_balance, rate_type, interest_rate)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                    (
                        sim_id,
                        item.month_number,
                        item.payment,
                        item.principal,
                        item.interest,
                        item.remaining_balance,
                        item.rate_type,
                        item.interest_rate,
                    ),
                )

        # Re-fetch the record to get DB-generated created_at
        fetch_cursor = await db.execute(
            """SELECT id, simulation_id, amount,
                      apply_month, reduction_type,
                      old_remaining_balance, new_remaining_balance,
                      old_remaining_months, new_remaining_months,
                      old_installment, new_installment,
                      total_interest_saved, original_end_date, new_end_date,
                      created_at
               FROM kpr_extra_payments WHERE id = ?""",
            (extra_id,),
        )
        db_record = await fetch_cursor.fetchone()

        if db_record:
            return dict(db_record)
        # Fallback if DB didn't return the record
        return {
            "id": extra_id,
            "simulation_id": sim_id,
            "amount": data.amount,
            "apply_month": data.apply_month,
            "reduction_type": data.reduction_type,
            "old_remaining_balance": result.old_remaining_balance,
            "new_remaining_balance": result.new_remaining_balance,
            "old_remaining_months": result.old_remaining_months,
            "new_remaining_months": result.new_remaining_months,
            "old_installment": result.old_installment,
            "new_installment": result.new_installment,
            "total_interest_saved": result.total_interest_saved,
            "original_end_date": result.original_end_date,
            "new_end_date": result.new_end_date,
            "created_at": "",
        }

    @staticmethod
    async def list_extra_payments(
        db: CursorWrapper,
        sim_id: int,
        user_id: int,
    ) -> list[dict]:
        """List all extra payments for a simulation."""
        await KPRService.get_simulation_for_user(db, sim_id, user_id)

        cursor = await db.execute(
            """SELECT id, simulation_id, amount,
                      apply_month, reduction_type,
                      old_remaining_balance, new_remaining_balance,
                      old_remaining_months, new_remaining_months,
                      old_installment, new_installment,
                      total_interest_saved, original_end_date, new_end_date,
                      created_at
               FROM kpr_extra_payments
               WHERE simulation_id = ?
               ORDER BY created_at DESC""",
            (sim_id,),
        )
        rows = await cursor.fetchall()
        return [dict(r) for r in rows]

    @staticmethod
    async def delete_extra_payment(
        db: CursorWrapper,
        sim_id: int,
        extra_payment_id: int,
        user_id: int,
    ) -> None:
        """Delete an extra payment and regenerate the original schedule."""
        sim = await KPRService.get_simulation_for_user(db, sim_id, user_id)

        # Verify extra payment exists
        cursor = await db.execute(
            "SELECT id FROM kpr_extra_payments WHERE id = ? AND simulation_id = ?",
            (extra_payment_id, sim_id),
        )
        if not await cursor.fetchone():
            raise KPRServiceError("Extra payment not found", status_code=404)

        async with db.transaction():
            # Delete the extra payment record
            await db.execute(
                "DELETE FROM kpr_extra_payments WHERE id = ?",
                (extra_payment_id,),
            )

            # Regenerate the schedule based on current extra payments
            cursor = await db.execute(
                "SELECT COUNT(*) AS cnt FROM kpr_extra_payments WHERE simulation_id = ?",
                (sim_id,),
            )
            count_row = await cursor.fetchone()
            remaining_count = count_row["cnt"] if count_row else 0

            # Load rate periods
            rate_periods_cursor = await db.execute(
                """SELECT period_start, period_end, interest_rate, rate_type
                   FROM kpr_rate_periods WHERE simulation_id = ?
                   ORDER BY period_start""",
                (sim_id,),
            )
            rate_periods_rows = await rate_periods_cursor.fetchall()
            rate_periods = [
                RatePeriod(**dict(r))
                for r in rate_periods_rows
            ]

            base_schedule = calculate_kpr(
                total_loan=sim["total_loan"],
                tenor_months=sim["tenor_months"],
                rate_periods=rate_periods if rate_periods else None,
                interest_type=sim["interest_type"],
                base_interest_rate=float(sim.get("base_interest_rate", 0.075)),
                graduated_increment=float(sim.get("graduated_increment", 0.005)),
                graduated_every_months=int(sim.get("graduated_every_months", 12)),
            )

            if remaining_count == 0:
                # No remaining extra payments — write base schedule
                await db.execute(
                    "DELETE FROM kpr_monthly_schedules WHERE simulation_id = ?",
                    (sim_id,),
                )
                for item in base_schedule:
                    await db.execute(
                        """INSERT INTO kpr_monthly_schedules
                           (simulation_id, month_number, payment, principal, interest,
                            remaining_balance, rate_type, interest_rate)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                        (
                            sim_id,
                            item.month_number,
                            item.payment,
                            item.principal,
                            item.interest,
                            item.remaining_balance,
                            item.rate_type,
                            item.interest_rate,
                        ),
                    )
            else:
                # Re-apply remaining extra payments
                cursor = await db.execute(
                    """SELECT amount, apply_month, reduction_type
                       FROM kpr_extra_payments
                       WHERE simulation_id = ?
                       ORDER BY apply_month ASC""",
                    (sim_id,),
                )
                remaining_extras = await cursor.fetchall()

                current_schedule = base_schedule
                for ep in remaining_extras:
                    ep_dict = dict(ep)
                    ep_result = apply_extra_payment(
                        schedule=current_schedule,
                        extra_amount=ep_dict["amount"],
                        apply_month=ep_dict["apply_month"],
                        reduction_type=ep_dict["reduction_type"],
                        start_month=sim.get("start_month", 1),
                        start_year=sim.get("start_year", 2026),
                    )
                    current_schedule = ep_result.schedule

                await db.execute(
                    "DELETE FROM kpr_monthly_schedules WHERE simulation_id = ?",
                    (sim_id,),
                )
                for item in current_schedule:
                    await db.execute(
                        """INSERT INTO kpr_monthly_schedules
                           (simulation_id, month_number, payment, principal, interest,
                            remaining_balance, rate_type, interest_rate)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                        (
                            sim_id,
                            item.month_number,
                            item.payment,
                            item.principal,
                            item.interest,
                            item.remaining_balance,
                            item.rate_type,
                            item.interest_rate,
                        ),
                    )
