from fastapi import APIRouter, Depends, HTTPException, Query

from app.database import get_db, CursorWrapper
from app.core.security import get_current_user
from app.schemas.kpr import (
    KPRSimulationCreate,
    KPRSimulationUpdate,
    KPRSimulationOut,
    KPRSimulationDetailOut,
    KPRScheduleItemOut,
    ExtraPaymentCreate,
    ExtraPaymentPreviewRequest,
    ExtraPaymentPreviewOut,
    ExtraPaymentOptionOut,
    ExtraPaymentOut,
)
from app.services.kpr_engine import (
    calculate_kpr, simulate_summary, RatePeriod,
    MonthlySchedule, apply_extra_payment, preview_extra_payment,
)

router = APIRouter(prefix="/kpr", tags=["kpr"])


async def _get_simulation_for_user(
    db: CursorWrapper, sim_id: int, user_id: int
) -> dict:
    """Fetch a simulation row and verify ownership. Raises 404/403."""
    cursor = await db.execute(
        "SELECT * FROM kpr_simulations WHERE id = ?", (sim_id,)
    )
    sim = await cursor.fetchone()
    if not sim:
        raise HTTPException(status_code=404, detail="Simulation not found")
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
    raise HTTPException(status_code=403, detail="Not your simulation")


def _convert_sim_row(row: dict) -> KPRSimulationOut:
    cmn = row.get("current_month_number", 1)
    crb = row.get("current_remaining_balance", 0)
    # If month 1, remaining balance = total_loan (no payment made yet)
    if cmn <= 1 and crb == 0:
        crb = row.get("total_loan", 0)
    return KPRSimulationOut(
        id=row["id"],
        user_id=row["user_id"],
        name=row["name"],
        property_price=row["property_price"],
        down_payment=row["down_payment"],
        total_loan=row["total_loan"],
        tenor_months=row["tenor_months"],
        interest_type=row["interest_type"],
        created_at=row["created_at"],
        start_month=row.get("start_month", 1),
        start_year=row.get("start_year", 2026),
        current_month_number=row.get("current_month_number", 1),
        current_month_payment=row.get("current_month_payment", 0),
        current_remaining_balance=crb,
    )


# ── Create simulation ───────────────────────────────────────────────


@router.post("/simulations", status_code=201)
async def create_simulation(
    data: KPRSimulationCreate,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Create a KPR simulation, calculate full amortization schedule, and store it."""
    total_loan = data.property_price - data.down_payment
    user_id = current_user["id"]

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

    # Build response
    summary = simulate_summary(schedule)
    refetched = await _get_simulation_for_user(db, sim_id, user_id)

    return KPRSimulationDetailOut(
        **refetched,
        total_interest=summary["total_interest"],
        monthly_payment=summary["monthly_payment"],
        current_month_number=1,
        current_month_payment=schedule[0].payment if schedule else 0,
        current_remaining_balance=total_loan,
        schedule=[
            KPRScheduleItemOut(
                month_number=s.month_number,
                payment=s.payment,
                principal=s.principal,
                interest=s.interest,
                remaining_balance=s.remaining_balance,
                rate_type=s.rate_type,
                interest_rate=s.interest_rate,
            )
            for s in schedule
        ],
        summary=summary,
    )


# ── List simulations ────────────────────────────────────────────────


@router.get("/simulations")
async def list_simulations(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> list[KPRSimulationOut]:
    """List all KPR simulations for the current user (metadata only)."""
    cursor = await db.execute(
        """SELECT
               ks.id, ks.user_id, ks.name, ks.property_price, ks.down_payment,
               ks.total_loan, ks.tenor_months, ks.interest_type, ks.created_at,
               ks.start_month, ks.start_year, ks.due_date,
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
                       SELECT LEAST(
                           (EXTRACT(YEAR FROM CURRENT_DATE) - ks2.start_year) * 12
                           + (EXTRACT(MONTH FROM CURRENT_DATE) - ks2.start_month) + 1,
                           ks2.tenor_months
                       )
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
                       SELECT LEAST(
                           (EXTRACT(YEAR FROM CURRENT_DATE) - ks3.start_year) * 12
                           + (EXTRACT(MONTH FROM CURRENT_DATE) - ks3.start_month) + 1,
                           ks3.tenor_months
                       )
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
        (current_user["id"], current_user["id"]),
    )
    rows = await cursor.fetchall()
    return [KPRSimulationOut(**dict(r)) for r in rows]


# ── Get single simulation ───────────────────────────────────────────


@router.get("/simulations/{simulation_id}")
async def get_simulation(
    simulation_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> KPRSimulationDetailOut:
    """Get a single simulation with full schedule and summary."""
    sim = await _get_simulation_for_user(db, simulation_id, current_user["id"])

    cursor = await db.execute(
        """SELECT month_number, payment, principal, interest,
                  remaining_balance, rate_type, interest_rate
           FROM kpr_monthly_schedules
           WHERE simulation_id = ?
           ORDER BY month_number""",
        (simulation_id,),
    )
    rows = await cursor.fetchall()
    schedule = [KPRScheduleItemOut(**dict(r)) for r in rows]

    # Build summary from the stored schedule
    from app.services.kpr_engine import MonthlySchedule
    engine_items = [
        MonthlySchedule(
            month_number=s.month_number,
            payment=s.payment,
            principal=s.principal,
            interest=s.interest,
            remaining_balance=s.remaining_balance,
            rate_type=s.rate_type,
            interest_rate=s.interest_rate,
        )
        for s in schedule
    ]
    summary = simulate_summary(engine_items)

    return KPRSimulationDetailOut(
        **sim,
        schedule=schedule,
        summary=summary,
    )


# ── Update simulation metadata ──────────────────────────────────────


@router.put("/simulations/{simulation_id}")
async def update_simulation(
    simulation_id: int,
    data: KPRSimulationUpdate,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Update simulation metadata (name, property_price, down_payment, tenor_months)."""
    await _get_simulation_for_user(db, simulation_id, current_user["id"])

    # Build dynamic UPDATE — only set non-None fields
    fields = []
    params = []

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
        # Fetch current values for the one not provided
        cursor = await db.execute(
            "SELECT property_price, down_payment FROM kpr_simulations WHERE id = ?",
            (simulation_id,),
        )
        current = dict(await cursor.fetchone())
        prop = data.property_price if prop_provided else current["property_price"]
        dp = data.down_payment if dp_provided else current["down_payment"]
        new_total = prop - dp
        fields.append("total_loan = ?")
        params.append(new_total)

    if not fields:
        raise HTTPException(status_code=400, detail="No fields to update")

    params.append(simulation_id)
    await db.execute(
        f"UPDATE kpr_simulations SET {', '.join(fields)} WHERE id = ?",
        tuple(params),
    )

    refetched = await _get_simulation_for_user(db, simulation_id, current_user["id"])
    return _convert_sim_row(refetched)


# ── Delete simulation ───────────────────────────────────────────────


@router.delete("/simulations/{simulation_id}", status_code=204)
async def delete_simulation(
    simulation_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Delete a simulation. Schedule and rate periods cascade via FK."""
    await _get_simulation_for_user(db, simulation_id, current_user["id"])
    await db.execute(
        "DELETE FROM kpr_simulations WHERE id = ?",
        (simulation_id,),
    )


# ── Extra Payment: Preview ──────────────────────────────────────────


@router.post("/simulations/{simulation_id}/extra-payments/preview")
async def preview_extra_payment_endpoint(
    simulation_id: int,
    data: ExtraPaymentPreviewRequest,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Preview both reduction options for an extra payment (no DB write)."""
    sim = await _get_simulation_for_user(db, simulation_id, current_user["id"])

    # Load schedule from DB
    cursor = await db.execute(
        """SELECT month_number, payment, principal, interest,
                  remaining_balance, rate_type, interest_rate
           FROM kpr_monthly_schedules
           WHERE simulation_id = ? ORDER BY month_number""",
        (simulation_id,),
    )
    rows = await cursor.fetchall()
    if not rows:
        raise HTTPException(status_code=400, detail="No schedule found. Generate schedule first.")

    schedule = [
        MonthlySchedule(**dict(r))
        for r in rows
    ]

    preview = preview_extra_payment(
        schedule=schedule,
        extra_amount=data.amount,
        apply_month=data.apply_month,
        penalty_rate=data.penalty_rate,
        start_month=sim.get("start_month", 1),
        start_year=sim.get("start_year", 2026),
    )

    def _to_option(result) -> ExtraPaymentOptionOut:
        return ExtraPaymentOptionOut(
            new_installment=result.new_installment,
            new_tenor=result.new_remaining_months,
            total_interest_paid=result.total_interest_paid,
            interest_saved=result.total_interest_saved,
            end_date=result.new_end_date,
        )

    comparison = {
        "installment_difference": preview.option_tenor.new_installment - preview.option_installment.new_installment,
        "months_saved_difference": preview.option_installment.new_remaining_months - preview.option_tenor.new_remaining_months,
    }

    return ExtraPaymentPreviewOut(
        option_installment=_to_option(preview.option_installment),
        option_tenor=_to_option(preview.option_tenor),
        comparison=comparison,
    )


# ── Extra Payment: Commit ───────────────────────────────────────────


@router.post("/simulations/{simulation_id}/extra-payments", status_code=201)
async def create_extra_payment(
    simulation_id: int,
    data: ExtraPaymentCreate,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Commit an extra payment, regenerate schedule, store record."""
    sim = await _get_simulation_for_user(db, simulation_id, current_user["id"])

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
    rate_periods = []
    if interest_type == "mix":
        cursor = await db.execute(
            "SELECT * FROM kpr_rate_periods WHERE simulation_id = ? ORDER BY period_start",
            (simulation_id,),
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
        (simulation_id,),
    )
    existing_extras = [dict(r) for r in await cursor.fetchall()]

    # 3. Apply all existing extra payments in chronological order
    #    to get the current state before applying the new one
    current_schedule = original_schedule
    for ep in existing_extras:
        ep_result = apply_extra_payment(
            schedule=current_schedule,
            extra_amount=ep["amount"],
            apply_month=ep["apply_month"],
            penalty_rate=float(ep["penalty_rate"]),
            reduction_type=ep["reduction_type"],
            start_month=start_month,
            start_year=start_year,
        )
        current_schedule = ep_result.schedule

    # 4. Apply penalty for the new extra payment
    penalty_amount = int(data.amount * data.penalty_rate)

    # 5. Apply the new extra payment to the current schedule
    result = apply_extra_payment(
        schedule=current_schedule,
        extra_amount=data.amount,
        apply_month=data.apply_month,
        penalty_rate=data.penalty_rate,
        reduction_type=data.reduction_type,
        start_month=start_month,
        start_year=start_year,
    )

    async with db.transaction():
        # 1. Store the extra payment record
        cursor = await db.execute(
            """INSERT INTO kpr_extra_payments
               (simulation_id, amount, penalty_rate, penalty_amount, apply_month,
                reduction_type, old_remaining_balance, new_remaining_balance,
                old_remaining_months, new_remaining_months, old_installment,
                new_installment, total_interest_saved, original_end_date, new_end_date)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                simulation_id, data.amount, data.penalty_rate, penalty_amount,
                data.apply_month, data.reduction_type,
                result.old_remaining_balance, result.new_remaining_balance,
                result.old_remaining_months, result.new_remaining_months,
                result.old_installment, result.new_installment,
                result.total_interest_saved,
                result.original_end_date, result.new_end_date,
            ),
        )
        extra_id = cursor.lastrowid or 0

        # 2. Delete old schedule and insert new one
        await db.execute(
            "DELETE FROM kpr_monthly_schedules WHERE simulation_id = ?",
            (simulation_id,),
        )
        for item in result.schedule:
            await db.execute(
                """INSERT INTO kpr_monthly_schedules
                   (simulation_id, month_number, payment, principal, interest,
                    remaining_balance, rate_type, interest_rate)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    simulation_id,
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
        """SELECT id, simulation_id, amount, penalty_rate, penalty_amount,
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

    return ExtraPaymentOut(
        **(dict(db_record) if db_record else {
            "id": extra_id,
            "simulation_id": simulation_id,
            "amount": data.amount,
            "penalty_rate": data.penalty_rate,
            "penalty_amount": penalty_amount,
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
        }),
    )


# ── Extra Payment: List ─────────────────────────────────────────────


@router.get("/simulations/{simulation_id}/extra-payments")
async def list_extra_payments(
    simulation_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> list[ExtraPaymentOut]:
    """List all extra payments for a simulation."""
    await _get_simulation_for_user(db, simulation_id, current_user["id"])

    cursor = await db.execute(
        """SELECT id, simulation_id, amount, penalty_rate, penalty_amount,
                  apply_month, reduction_type,
                  old_remaining_balance, new_remaining_balance,
                  old_remaining_months, new_remaining_months,
                  old_installment, new_installment,
                  total_interest_saved, original_end_date, new_end_date,
                  created_at
           FROM kpr_extra_payments
           WHERE simulation_id = ?
           ORDER BY created_at DESC""",
        (simulation_id,),
    )
    rows = await cursor.fetchall()
    return [ExtraPaymentOut(**dict(r)) for r in rows]


# ── Extra Payment: Delete ───────────────────────────────────────────


@router.delete(
    "/simulations/{simulation_id}/extra-payments/{extra_payment_id}",
    status_code=204,
)
async def delete_extra_payment(
    simulation_id: int,
    extra_payment_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Delete an extra payment and regenerate the original schedule.

    This re-calculates the full amortization schedule as if the extra
    payment never happened, removing its effect.
    """
    sim = await _get_simulation_for_user(db, simulation_id, current_user["id"])

    # Verify extra payment exists
    cursor = await db.execute(
        "SELECT id FROM kpr_extra_payments WHERE id = ? AND simulation_id = ?",
        (extra_payment_id, simulation_id),
    )
    if not await cursor.fetchone():
        raise HTTPException(status_code=404, detail="Extra payment not found")

    async with db.transaction():
        # Delete the extra payment record
        await db.execute(
            "DELETE FROM kpr_extra_payments WHERE id = ?",
            (extra_payment_id,),
        )

        # Regenerate the schedule based on current extra payments
        # First check if any extra payments remain
        cursor = await db.execute(
            "SELECT COUNT(*) AS cnt FROM kpr_extra_payments WHERE simulation_id = ?",
            (simulation_id,),
        )
        count_row = await cursor.fetchone()
        remaining_count = count_row["cnt"] if count_row else 0

        # We need to re-apply remaining extra payments on top of original schedule
        # Strategy: get the original simulation params, generate base schedule,
        # then re-apply remaining extra payments in order
        rate_periods_cursor = await db.execute(
            """SELECT period_start, period_end, interest_rate, rate_type
               FROM kpr_rate_periods WHERE simulation_id = ?
               ORDER BY period_start""",
            (simulation_id,),
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
                (simulation_id,),
            )
            for item in base_schedule:
                await db.execute(
                    """INSERT INTO kpr_monthly_schedules
                       (simulation_id, month_number, payment, principal, interest,
                        remaining_balance, rate_type, interest_rate)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                    (
                        simulation_id,
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
                """SELECT amount, penalty_rate, apply_month, reduction_type
                   FROM kpr_extra_payments
                   WHERE simulation_id = ?
                   ORDER BY apply_month ASC""",
                (simulation_id,),
            )
            remaining_extras = await cursor.fetchall()

            current_schedule = base_schedule
            for ep in remaining_extras:
                ep_dict = dict(ep)
                result = apply_extra_payment(
                    schedule=current_schedule,
                    extra_amount=ep_dict["amount"],
                    apply_month=ep_dict["apply_month"],
                    penalty_rate=ep_dict["penalty_rate"],
                    reduction_type=ep_dict["reduction_type"],
                    start_month=sim.get("start_month", 1),
                    start_year=sim.get("start_year", 2026),
                )
                current_schedule = result.schedule

            await db.execute(
                "DELETE FROM kpr_monthly_schedules WHERE simulation_id = ?",
                (simulation_id,),
            )
            for item in current_schedule:
                await db.execute(
                    """INSERT INTO kpr_monthly_schedules
                       (simulation_id, month_number, payment, principal, interest,
                        remaining_balance, rate_type, interest_rate)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                    (
                        simulation_id,
                        item.month_number,
                        item.payment,
                        item.principal,
                        item.interest,
                        item.remaining_balance,
                        item.rate_type,
                        item.interest_rate,
                    ),
                )


@router.get("/simulations/{simulation_id}/schedule")
async def get_simulation_schedule(
    simulation_id: int,
    month: int = Query(None, ge=1, description="Month number (1-based). Omits all for full schedule."),
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Get schedule items for a simulation. Optionally filter to a single month."""
    await _get_simulation_for_user(db, simulation_id, current_user["id"])

    if month is not None:
        cursor = await db.execute(
            """SELECT month_number, payment, principal, interest,
                      remaining_balance, rate_type, interest_rate
               FROM kpr_monthly_schedules
               WHERE simulation_id = ? AND month_number = ?
               ORDER BY month_number""",
            (simulation_id, month),
        )
        row = await cursor.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Month not found in schedule")
        return KPRScheduleItemOut(**dict(row))
    else:
        cursor = await db.execute(
            """SELECT month_number, payment, principal, interest,
                      remaining_balance, rate_type, interest_rate
               FROM kpr_monthly_schedules
               WHERE simulation_id = ?
               ORDER BY month_number""",
            (simulation_id,),
        )
        rows = await cursor.fetchall()
        return [KPRScheduleItemOut(**dict(r)) for r in rows]
