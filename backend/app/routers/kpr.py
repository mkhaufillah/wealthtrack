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
from app.services.kpr_service import KPRService, KPRServiceError

router = APIRouter(prefix="/kpr", tags=["kpr"])


# ── Create simulation ───────────────────────────────────────────────


@router.post("/simulations", status_code=201)
async def create_simulation(
    data: KPRSimulationCreate,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Create a KPR simulation, calculate full amortization schedule, and store it."""
    try:
        result = await KPRService.create_simulation(
            db, data, current_user["id"],
        )
    except KPRServiceError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)

    return KPRSimulationDetailOut(**result)


# ── List simulations ────────────────────────────────────────────────


@router.get("/simulations")
async def list_simulations(
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> list[KPRSimulationOut]:
    """List all KPR simulations for the current user (metadata only)."""
    try:
        rows = await KPRService.list_simulations(db, current_user["id"])
    except KPRServiceError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)

    return [KPRSimulationOut(**r) for r in rows]


# ── Get single simulation ───────────────────────────────────────────


@router.get("/simulations/{simulation_id}")
async def get_simulation(
    simulation_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> KPRSimulationDetailOut:
    """Get a single simulation with full schedule and summary."""
    try:
        result = await KPRService.get_simulation_detail(
            db, simulation_id, current_user["id"],
        )
    except KPRServiceError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)

    return KPRSimulationDetailOut(
        **result,
        schedule=[KPRScheduleItemOut(**s) for s in result["schedule"]],
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
    try:
        refetched = await KPRService.update_simulation(
            db, simulation_id, data, current_user["id"],
        )
    except KPRServiceError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)

    return KPRService.convert_sim_row(refetched)


# ── Delete simulation ───────────────────────────────────────────────


@router.delete("/simulations/{simulation_id}", status_code=204)
async def delete_simulation(
    simulation_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Delete a simulation. Schedule and rate periods cascade via FK."""
    try:
        await KPRService.delete_simulation(db, simulation_id, current_user["id"])
    except KPRServiceError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)


# ── Extra Payment: Preview ──────────────────────────────────────────


@router.post("/simulations/{simulation_id}/extra-payments/preview")
async def preview_extra_payment_endpoint(
    simulation_id: int,
    data: ExtraPaymentPreviewRequest,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Preview both reduction options for an extra payment (no DB write)."""
    try:
        preview = await KPRService.preview_extra_payment(
            db, simulation_id, data, current_user["id"],
        )
    except KPRServiceError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)

    return ExtraPaymentPreviewOut(
        option_installment=ExtraPaymentOptionOut(**preview["option_installment"]),
        option_tenor=ExtraPaymentOptionOut(**preview["option_tenor"]),
        comparison=preview["comparison"],
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
    try:
        db_record = await KPRService.create_extra_payment(
            db, simulation_id, data, current_user["id"],
        )
    except KPRServiceError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)

    return ExtraPaymentOut(**db_record)


# ── Extra Payment: List ─────────────────────────────────────────────


@router.get("/simulations/{simulation_id}/extra-payments")
async def list_extra_payments(
    simulation_id: int,
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
) -> list[ExtraPaymentOut]:
    """List all extra payments for a simulation."""
    try:
        rows = await KPRService.list_extra_payments(
            db, simulation_id, current_user["id"],
        )
    except KPRServiceError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)

    return [ExtraPaymentOut(**r) for r in rows]


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
    """Delete an extra payment and regenerate the original schedule."""
    try:
        await KPRService.delete_extra_payment(
            db, simulation_id, extra_payment_id, current_user["id"],
        )
    except KPRServiceError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)


# ── Schedule ────────────────────────────────────────────────────────


@router.get("/simulations/{simulation_id}/schedule")
async def get_simulation_schedule(
    simulation_id: int,
    month: int = Query(None, ge=1, description="Month number (1-based). Omit for full schedule."),
    db: CursorWrapper = Depends(get_db),
    current_user: dict = Depends(get_current_user),
):
    """Get schedule items for a simulation. Optionally filter to a single month."""
    try:
        result = await KPRService.get_simulation_schedule(
            db, simulation_id, current_user["id"], month=month,
        )
    except KPRServiceError as e:
        raise HTTPException(status_code=e.status_code, detail=e.message)

    if isinstance(result, dict):
        return KPRScheduleItemOut(**result)
    return [KPRScheduleItemOut(**r) for r in result]
