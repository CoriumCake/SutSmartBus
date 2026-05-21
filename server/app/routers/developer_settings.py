import json

from fastapi import APIRouter, HTTPException

from app import analytics as analytics_module, constants, crud, schemas, state
from app.mqtt import (
    bus_document_to_app_payload,
    client as mqtt_client,
    mark_passenger_count_reset_pending,
    publish_reset_count_command,
)
from app.passenger_rules import seats_available_for_count

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


@router.post("/sync-assigned-bus-location")
async def sync_assigned_bus_location(
    request: schemas.AssignedBusLocationSyncRequest,
):
    updated_bus = await crud.update_bus_location(
        mac_address=request.bus_mac,
        lat=request.lat,
        lon=request.lon,
        seats_available=None,
        use_default_location_if_missing=False,
    )
    return {
        "success": updated_bus is not None,
        "bus": updated_bus,
    }


@router.post("/reset-passenger-count")
async def reset_passenger_count(
    request: schemas.PassengerCountResetRequest,
):
    bus_mac = request.bus_mac.strip()
    if not bus_mac:
        raise HTTPException(status_code=400, detail="bus_mac is required")

    bus = await crud.get_bus_by_mac(bus_mac)
    if bus is None:
        raise HTTPException(status_code=404, detail="Bus not found")

    updated_bus = await crud.update_bus_location(
        mac_address=bus["mac_address"],
        bus_id=bus.get("bus_id"),
        lat=None,
        lon=None,
        seats_available=seats_available_for_count(0),
        person_count=0,
        count_source="developer",
        apply_parking_reset=False,
        use_default_location_if_missing=False,
    )
    if updated_bus is None:
        raise HTTPException(
            status_code=500,
            detail="Could not reset passenger count",
        )

    analytics_module.record_passenger_count(
        updated_bus["mac_address"],
        0,
        updated_bus.get("current_lat") or 0.0,
        updated_bus.get("current_lon") or 0.0,
        apply_parking_reset=False,
    )
    with state.state.passenger_lock:
        state.state.current_passengers = 0

    mark_passenger_count_reset_pending(
        updated_bus.get("mac_address"),
        updated_bus.get("bus_id"),
        bus_mac,
        updated_bus.get("bus_name"),
    )
    reset_command = publish_reset_count_command(
        bus_mac=updated_bus.get("mac_address"),
        bus_id=updated_bus.get("bus_id"),
        force=True,
    )
    mqtt_client.publish(
        constants.TOPIC_APP_LOCATION,
        json.dumps(bus_document_to_app_payload(updated_bus)),
    )

    return {
        "success": True,
        "bus": updated_bus,
        "reset_command_sent": reset_command["sent"],
        "reset_command": reset_command,
    }
