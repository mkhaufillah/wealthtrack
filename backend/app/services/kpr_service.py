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
    KPRSimulationOut,
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

    @staticmethod
    def _pack(amount: int, extra: dict | None = None) -> dict:
        from app.core.vault_write import must_dek
        from app.core.vault_row import pack_money

        return pack_money(must_dek(), amount=max(0, int(amount)), extra=extra)

    @staticmethod
    async def _insert_schedule_item(db: CursorWrapper, sim_id: int, item) -> None:
        packed = KPRService._pack(
            int(item.remaining_balance) if int(item.remaining_balance) > 0 else 0,
            extra={
                "payment": int(item.payment),
                "principal": int(item.principal),
                "interest": int(item.interest),
                "remaining_balance": int(item.remaining_balance),
                "interest_rate": float(item.interest_rate),
                "month_number": int(item.month_number),
                "rate_type": item.rate_type,
            },
        )
        await db.execute(
            """INSERT INTO kpr_monthly_schedules
               (simulation_id, month_number, rate_type, vault_blob, amount_ord)
               VALUES (?, ?, ?, ?, ?)""",
            (
                sim_id,
                item.month_number,
                item.rate_type,
                packed["vault_blob"],
                packed["amount_ord"],
            ),
        )

    # ── Shared helpers ─────────────────────────────────────────

    @staticmethod
    async def _load_rate_periods(db: CursorWrapper, sim_id: int) -> list[RatePeriod]:
        from app.core.vault_row import open_row

        cursor = await db.execute(
            """SELECT period_start, period_end, rate_type, vault_blob
               FROM kpr_rate_periods WHERE simulation_id = ?
               ORDER BY period_start""",
            (sim_id,),
        )
        out: list[RatePeriod] = []
        for r in await cursor.fetchall():
            d = open_row(dict(r))
            out.append(
                RatePeriod(
                    period_start=int(d["period_start"]),
                    period_end=int(d["period_end"]),
                    interest_rate=float(d.get("interest_rate") or 0),
                    rate_type=d.get("rate_type") or "fixed",
                )
            )
        return out

    @staticmethod
    def _monthly_from_row(r) -> MonthlySchedule:
        from app.core.vault_row import open_row

        d = open_row(dict(r))
        return MonthlySchedule(
            month_number=int(d.get("month_number") or 0),
            payment=int(d.get("payment") or 0),
            principal=int(d.get("principal") or 0),
            interest=int(d.get("interest") or 0),
            remaining_balance=int(d.get("remaining_balance") or 0),
            rate_type=str(d.get("rate_type") or "fixed"),
            interest_rate=float(d.get("interest_rate") or 0),
        )

    @staticmethod
    async def _load_schedule(db: CursorWrapper, sim_id: int) -> list[MonthlySchedule]:
        cursor = await db.execute(
            """SELECT month_number, rate_type, vault_blob
               FROM kpr_monthly_schedules
               WHERE simulation_id = ? ORDER BY month_number""",
            (sim_id,),
        )
        return [KPRService._monthly_from_row(r) for r in await cursor.fetchall()]

    @staticmethod
    async def get_simulation_for_user(
        db: CursorWrapper, sim_id: int, user_id: int,
    ) -> dict:
        """Fetch a simulation row and verify ownership.

        Returns dict of the simulation row.

        Raises KPRServiceError:
            404 — simulation not found
            403 — not owned by user or user's household
        """
        cursor = await db.execute(
            "SELECT * FROM kpr_simulations WHERE id = ?", (sim_id,)
        )
        sim = await cursor.fetchone()
        if not sim:
            raise KPRServiceError("Simulasi gak ketemu", 404)
        sim = dict(sim)
        from app.core.vault_row import open_row

        sim = open_row(sim)
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
        raise KPRServiceError("Bukan simulasi kamu", 403)

    @staticmethod
    def convert_sim_row(row: dict) -> KPRSimulationOut:
        """Map a DB row dict to KPRSimulationOut with default handling."""
        from app.core.vault_row import open_row

        row = open_row(dict(row))
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
            packed_sim = KPRService._pack(
                total_loan,
                extra={
                    "name": data.name or "",
                    "property_price": int(data.property_price),
                    "down_payment": int(data.down_payment),
                    "total_loan": int(total_loan),
                    "base_interest_rate": float(data.base_interest_rate or 0),
                    "graduated_increment": float(data.graduated_increment or 0),
                    "graduated_every_months": int(data.graduated_every_months or 0),
                },
            )
            cursor = await db.execute(
                """INSERT INTO kpr_simulations
                   (user_id, tenor_months, interest_type, start_month, start_year, due_date,
                    household_id, vault_blob, amount_ord)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    user_id,
                    data.tenor_months,
                    data.interest_type,
                    data.start_month,
                    data.start_year,
                    data.due_date,
                    data.household_id,
                    packed_sim["vault_blob"],
                    packed_sim["amount_ord"],
                ),
            )
            sim_id = cursor.lastrowid
            if not sim_id:
                raise KPRServiceError("Gagal buat simulasi", 500)

            for rp in data.rate_periods:
                packed_rp = KPRService._pack(
                    0,
                    extra={
                        "interest_rate": float(rp.interest_rate),
                        "period_start": int(rp.period_start),
                        "period_end": int(rp.period_end),
                        "rate_type": rp.rate_type,
                    },
                )
                await db.execute(
                    """INSERT INTO kpr_rate_periods
                       (simulation_id, period_start, period_end, rate_type, vault_blob)
                       VALUES (?, ?, ?, ?, ?)""",
                    (sim_id, rp.period_start, rp.period_end, rp.rate_type, packed_rp["vault_blob"]),
                )

            schedule = calculate_kpr(
                total_loan=total_loan,
                tenor_months=data.tenor_months,
                rate_periods=rate_periods if rate_periods else None,
                interest_type=data.interest_type,
                base_interest_rate=data.base_interest_rate,
                graduated_increment=data.graduated_increment,
                graduated_every_months=data.graduated_every_months,
            )

            for item in schedule:
                await KPRService._insert_schedule_item(db, sim_id, item)

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
            """SELECT ks.id, ks.user_id, ks.tenor_months, ks.interest_type, ks.created_at,
                      ks.start_month, ks.start_year, ks.due_date,
                      ks.household_id, ks.display_order, ks.vault_blob
               FROM kpr_simulations ks
               WHERE ks.user_id = ?
                  OR ks.household_id IN (
                      SELECT household_id FROM household_members WHERE user_id = ?
                  )
               ORDER BY ks.display_order ASC, ks.created_at DESC""",
            (user_id, user_id),
        )
        rows = await cursor.fetchall()
        from app.core.vault_row import open_row

        out = []
        for r in rows:
            d = open_row(dict(r))
            from datetime import date as _date
            today = _date.today()
            sm = int(d.get("start_month") or 1)
            sy = int(d.get("start_year") or today.year)
            tenor = int(d.get("tenor_months") or 1)
            d["current_month_number"] = max(
                1, min(tenor, (today.year - sy) * 12 + (today.month - sm) + 1)
            )
            cur2 = await db.execute(
                """SELECT vault_blob, month_number
                   FROM kpr_monthly_schedules WHERE simulation_id = ?
                   ORDER BY month_number""",
                (d["id"],),
            )
            sched = [open_row(dict(x)) for x in await cur2.fetchall()]
            if sched:
                cmn = int(d.get("current_month_number") or 1)
                pick = next((s for s in sched if int(s.get("month_number") or 0) == cmn), sched[-1])
                prev_n = max(1, cmn - 1)
                prev = next((s for s in sched if int(s.get("month_number") or 0) == prev_n), pick)
                d["current_remaining_balance"] = int(
                    prev.get("remaining_balance") or d.get("total_loan") or 0
                )
                d["current_month_payment"] = int(pick.get("payment") or 0)
                d["monthly_payment"] = int(sched[0].get("payment") or 0)
                d["total_interest"] = sum(int(s.get("interest") or 0) for s in sched)
            out.append(d)
        return out

    @staticmethod
    async def get_simulation_detail(
        db: CursorWrapper,
        sim_id: int,
        user_id: int,
    ) -> dict:
        """Get a single simulation with full schedule and summary."""
        sim = await KPRService.get_simulation_for_user(db, sim_id, user_id)

        cursor = await db.execute(
            """SELECT month_number, rate_type, vault_blob
               FROM kpr_monthly_schedules
               WHERE simulation_id = ?
               ORDER BY month_number""",
            (sim_id,),
        )
        rows = await cursor.fetchall()
        from app.core.vault_row import open_row

        schedule_data = [open_row(dict(r)) for r in rows]

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
        sim = await KPRService.get_simulation_for_user(db, sim_id, user_id)

        fields: list[str] = []
        params: list = []

        if data.tenor_months is not None:
            fields.append("tenor_months = ?")
            params.append(data.tenor_months)

        prop_provided = data.property_price is not None
        dp_provided = data.down_payment is not None
        if data.name is not None or prop_provided or dp_provided:
            prop = int(data.property_price if prop_provided else sim.get("property_price") or 0)
            dp = int(data.down_payment if dp_provided else sim.get("down_payment") or 0)
            new_total = prop - dp
            packed = KPRService._pack(
                new_total,
                extra={
                    "name": data.name if data.name is not None else sim.get("name") or "",
                    "property_price": prop,
                    "down_payment": dp,
                    "total_loan": new_total,
                    "base_interest_rate": float(sim.get("base_interest_rate") or 0),
                    "graduated_increment": float(sim.get("graduated_increment") or 0),
                    "graduated_every_months": int(sim.get("graduated_every_months") or 0),
                },
            )
            fields.append("vault_blob = ?")
            params.append(packed["vault_blob"])
            fields.append("amount_ord = ?")
            params.append(packed["amount_ord"])

        if not fields:
            raise KPRServiceError("Gak ada yang diubah", status_code=400)

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

        schedule = await KPRService._load_schedule(db, sim_id)
        if month is not None:
            for item in schedule:
                if item.month_number == month:
                    return {
                        "month_number": item.month_number,
                        "payment": item.payment,
                        "principal": item.principal,
                        "interest": item.interest,
                        "remaining_balance": item.remaining_balance,
                        "rate_type": item.rate_type,
                        "interest_rate": item.interest_rate,
                    }
            raise KPRServiceError("Bulan gak ada di jadwal", status_code=404)
        return [
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
        ]

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

        schedule = await KPRService._load_schedule(db, sim_id)
        if not schedule:
            raise KPRServiceError(
                "No schedule found. Generate schedule first.",
                status_code=400,
            )

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
            rate_periods = await KPRService._load_rate_periods(db, sim_id)

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
        from app.core.vault_row import open_row

        existing_extras = [open_row(dict(r)) for r in await cursor.fetchall()]

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
            extra_payload = {
                "amount": int(data.amount),
                "apply_month": int(data.apply_month),
                "old_remaining_balance": int(result.old_remaining_balance),
                "new_remaining_balance": int(result.new_remaining_balance),
                "old_remaining_months": int(result.old_remaining_months),
                "new_remaining_months": int(result.new_remaining_months),
                "old_installment": int(result.old_installment),
                "new_installment": int(result.new_installment),
                "total_interest_saved": int(result.total_interest_saved),
                "original_end_date": result.original_end_date,
                "new_end_date": result.new_end_date,
            }
            packed_ep = KPRService._pack(int(data.amount), extra=extra_payload)
            cursor = await db.execute(
                """INSERT INTO kpr_extra_payments
                   (simulation_id, apply_month, reduction_type, vault_blob, amount_ord)
                   VALUES (?, ?, ?, ?, ?)""",
                (
                    sim_id,
                    data.apply_month, data.reduction_type,
                    packed_ep["vault_blob"], packed_ep["amount_ord"],
                ),
            )
            extra_id = cursor.lastrowid or 0

            # Delete old schedule and insert new one
            await db.execute(
                "DELETE FROM kpr_monthly_schedules WHERE simulation_id = ?",
                (sim_id,),
            )
            for item in result.schedule:
                await KPRService._insert_schedule_item(db, sim_id, item)

        # Re-fetch the record to get DB-generated created_at
        fetch_cursor = await db.execute(
            """SELECT id, simulation_id, vault_blob,
                      apply_month, reduction_type,
                      created_at
               FROM kpr_extra_payments WHERE id = ?""",
            (extra_id,),
        )
        db_record = await fetch_cursor.fetchone()

        if db_record:
            d = open_row(dict(db_record))
            d.pop("vault_blob", None)
            return d
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
            """SELECT id, simulation_id, vault_blob,
                      apply_month, reduction_type,
                      created_at
               FROM kpr_extra_payments
               WHERE simulation_id = ?
               ORDER BY created_at DESC""",
            (sim_id,),
        )
        from app.core.vault_row import open_row

        rows = await cursor.fetchall()
        month_cur = await db.execute(
            """SELECT month_number FROM kpr_monthly_schedules
               WHERE simulation_id = ?""",
            (sim_id,),
        )
        month_nums = [int(r["month_number"]) for r in await month_cur.fetchall()]
        out = []
        for r in rows:
            d = open_row(dict(r))
            d.pop("vault_blob", None)
            for k in (
                "id",
                "simulation_id",
                "amount",
                "apply_month",
                "old_remaining_balance",
                "new_remaining_balance",
                "old_remaining_months",
                "new_remaining_months",
                "old_installment",
                "new_installment",
                "total_interest_saved",
            ):
                d[k] = int(d[k] or 0) if d.get(k) is not None else 0
            apply = int(d.get("apply_month") or 0)
            live = sum(1 for m in month_nums if m >= apply) if apply else len(month_nums)
            if d["new_remaining_months"] <= 0 and live > 0:
                d["new_remaining_months"] = live
            if d["old_remaining_months"] <= 0 and live > 0:
                d["old_remaining_months"] = live
            d["original_end_date"] = d.get("original_end_date") or ""
            d["new_end_date"] = d.get("new_end_date") or ""
            d["reduction_type"] = d.get("reduction_type") or "tenor"
            d["created_at"] = d.get("created_at") or ""
            out.append(d)
        return out

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
            raise KPRServiceError("Pembayaran ekstra gak ketemu", status_code=404)

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
            rate_periods = await KPRService._load_rate_periods(db, sim_id)

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
                    await KPRService._insert_schedule_item(db, sim_id, item)
            else:
                from app.core.vault_row import open_row

                # Re-apply remaining extra payments
                cursor = await db.execute(
                    """SELECT id, apply_month, reduction_type, vault_blob
                       FROM kpr_extra_payments
                       WHERE simulation_id = ?
                       ORDER BY apply_month ASC""",
                    (sim_id,),
                )
                remaining_extras = await cursor.fetchall()

                current_schedule = base_schedule
                for ep in remaining_extras:
                    ep_dict = open_row(dict(ep))
                    ep_result = apply_extra_payment(
                        schedule=current_schedule,
                        extra_amount=int(ep_dict.get("amount") or 0),
                        apply_month=ep_dict["apply_month"],
                        reduction_type=ep_dict["reduction_type"],
                        start_month=sim.get("start_month", 1),
                        start_year=sim.get("start_year", 2026),
                    )
                    current_schedule = ep_result.schedule
                    extra_payload = {
                        "amount": int(ep_dict.get("amount") or 0),
                        "apply_month": int(ep_dict["apply_month"]),
                        "old_remaining_balance": int(ep_result.old_remaining_balance),
                        "new_remaining_balance": int(ep_result.new_remaining_balance),
                        "old_remaining_months": int(ep_result.old_remaining_months),
                        "new_remaining_months": int(ep_result.new_remaining_months),
                        "old_installment": int(ep_result.old_installment),
                        "new_installment": int(ep_result.new_installment),
                        "total_interest_saved": int(ep_result.total_interest_saved),
                        "original_end_date": ep_result.original_end_date,
                        "new_end_date": ep_result.new_end_date,
                    }
                    packed_ep = KPRService._pack(
                        int(ep_dict.get("amount") or 0), extra=extra_payload
                    )
                    await db.execute(
                        """UPDATE kpr_extra_payments
                           SET vault_blob=?, amount_ord=?
                           WHERE id=?""",
                        (
                            packed_ep["vault_blob"],
                            packed_ep["amount_ord"],
                            ep_dict["id"],
                        ),
                    )

                await db.execute(
                    "DELETE FROM kpr_monthly_schedules WHERE simulation_id = ?",
                    (sim_id,),
                )
                for item in current_schedule:
                    await KPRService._insert_schedule_item(db, sim_id, item)
