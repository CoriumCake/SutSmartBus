from fastapi import APIRouter

from app import crud, schemas

router = APIRouter(prefix="/api/developer-settings", tags=["Developer Settings"])


@router.get("", response_model=schemas.DeveloperSettingsResponse)
async def get_developer_settings():
    return await crud.get_developer_settings()


@router.put("", response_model=schemas.DeveloperSettingsResponse)
async def update_developer_settings(
    request: schemas.DeveloperSettingsUpdateRequest,
):
    return await crud.update_developer_settings(
        reset_passenger_count_at_terminal_stop=(
            request.reset_passenger_count_at_terminal_stop
        ),
        no_gps_mode_enabled=request.no_gps_mode_enabled,
        assigned_bus_mac=request.assigned_bus_mac,
    )
