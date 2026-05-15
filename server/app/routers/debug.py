from datetime import datetime, timezone
import logging

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app import crud

router = APIRouter(prefix="/api/debug", tags=["Debug"])
logger = logging.getLogger(__name__)


class DebugLocationUpdate(BaseModel):
    bus_mac: str
    bus_name: str | None = None
    lat: float | None = None
    lon: float | None = None
    current_lat: float | None = None
    current_lon: float | None = None
    seats_available: int = 40
    person_count: int = 0
    pm2_5: float = 0.0
    pm10: float = 0.0
    temp: float = 0.0
    hum: float = 0.0
    route_id: str | None = None
    is_online: bool = True
    last_updated: datetime | None = None


@router.post("/location")
async def upsert_debug_location(payload: DebugLocationUpdate):
    lat = payload.lat if payload.lat is not None else payload.current_lat
    lon = payload.lon if payload.lon is not None else payload.current_lon
    logger.info(
        "Debug location update bus=%s lat=%s lon=%s pm2_5=%s pm10=%s temp=%s hum=%s",
        payload.bus_mac,
        lat,
        lon,
        payload.pm2_5,
        payload.pm10,
        payload.temp,
        payload.hum,
    )

    updated_bus = await crud.update_bus_location(
        mac_address=payload.bus_mac,
        bus_name=payload.bus_name,
        lat=lat,
        lon=lon,
        seats_available=payload.seats_available,
        pm2_5=payload.pm2_5,
        pm10=payload.pm10,
        temp=payload.temp,
        hum=payload.hum,
        person_count=payload.person_count,
    )

    if updated_bus is None:
        raise HTTPException(status_code=500, detail="Failed to store debug bus")

    route_id = payload.route_id
    if route_id:
        await crud.bus_collection.update_one(
            {"mac_address": payload.bus_mac},
            {
                "$set": {
                    "route_id": route_id,
                    "is_online": payload.is_online,
                    "last_updated": payload.last_updated
                    or datetime.now(timezone.utc),
                }
            },
        )
        updated_bus = await crud.get_bus_by_mac(payload.bus_mac)

    return updated_bus


@router.delete("/location/{bus_mac}")
async def delete_debug_location(bus_mac: str):
    deleted = await crud.delete_bus(bus_mac)
    logger.info("Debug location delete bus=%s deleted=%s", bus_mac, deleted)
    if not deleted:
        return {"success": True, "message": "Debug bus already absent"}
    return {"success": True, "message": f"Deleted debug bus {bus_mac}"}
