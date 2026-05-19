from fastapi import APIRouter, HTTPException, Body, Request
from typing import List
from app import crud, models, constants, schemas
from app.mqtt import client as mqtt_client
from app.ride_sessions import (
    RideSessionForbiddenError,
    RideSessionNotFoundError,
    RideSessionRateLimitError,
    end_ride_session,
    get_active_ride_session,
    start_ride_session,
    verify_session_for_ring,
)
from app.security import InMemoryRateLimiter, LimitRule, sign_ring_command
from core.config import settings
import json
import time

router = APIRouter(prefix="/api", tags=["Buses"])
rate_limiter = InMemoryRateLimiter()
RIDE_START_RULE = LimitRule(
    window_seconds=300,
    max_requests=5,
    message="Too many ride start attempts. Please try again later.",
)
RING_RULE = LimitRule(
    window_seconds=120,
    max_requests=4,
    message="Too many bell requests. Please wait before trying again.",
)


def _client_ip(request: Request) -> str:
    forwarded_for = request.headers.get("x-forwarded-for", "")
    if forwarded_for:
        return forwarded_for.split(",")[0].strip()
    client = request.client
    return client.host if client else "unknown"


def _ring_secret() -> str:
    secret = settings.RING_COMMAND_SECRET or settings.API_SECRET_KEY
    if not secret:
        raise HTTPException(
            status_code=503,
            detail="Ring command secret is not configured on the server",
        )
    return secret

@router.get("/buses", response_model=List[models.Bus])
async def list_buses(skip: int = 0, limit: int = 100):
    return await crud.get_buses(skip=skip, limit=limit)

@router.post("/buses", response_model=models.Bus)
async def create_bus(bus: models.Bus):
    return await crud.create_bus(bus)

@router.put("/buses/{mac_address}")
async def update_bus(mac_address: str, bus_data: dict = Body(...)):
    result = await crud.bus_collection.update_one(
        {"mac_address": mac_address},
        {"$set": bus_data}
    )
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Bus not found")
    return await crud.get_bus_by_mac(mac_address)

@router.delete("/buses/{mac_address}")
async def delete_bus(mac_address: str):
    # Logic from main.py
    bus = await crud.get_bus_by_mac(mac_address)
    if not bus:
        raise HTTPException(status_code=404, detail="Bus not found")
    
    result = await crud.bus_collection.delete_one({"mac_address": mac_address})
    if result.deleted_count == 0:
         raise HTTPException(status_code=404, detail="Bus not found")
    return {"message": "Bus deleted successfully"}

@router.post("/ring")
async def ring_bell(request: schemas.SecureRingRequest, http_request: Request):
    try:
        client_ip = _client_ip(http_request)
        rate_limiter.enforce(
            scope=f"ring:device:{request.device_id}",
            rule=RING_RULE,
        )
        rate_limiter.enforce(
            scope=f"ring:ip:{client_ip}",
            rule=RING_RULE,
        )
        rate_limiter.enforce(
            scope=f"ring:bus:{request.bus_mac}",
            rule=RING_RULE,
        )
        await verify_session_for_ring(
            session_id=request.session_id,
            device_id=request.device_id,
            bus_mac=request.bus_mac,
            user_lat=request.user_lat,
            user_lon=request.user_lon,
            user_accuracy_m=request.user_accuracy_m,
        )
        timestamp = int(time.time())
        mqtt_client.publish(constants.ring_topic_for_bus(request.bus_mac), json.dumps({
            "command": "ring",
            "bus_mac": request.bus_mac,
            "timestamp": timestamp,
            "sig": sign_ring_command(
                secret=_ring_secret(),
                bus_mac=request.bus_mac,
                timestamp=timestamp,
            ),
        }))
        return {"success": True, "message": f"Ring signal sent to {request.bus_mac}"}
    except RideSessionRateLimitError as e:
        raise HTTPException(status_code=429, detail=str(e))
    except RideSessionForbiddenError as e:
        raise HTTPException(status_code=403, detail=str(e))
    except RideSessionNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to send ring: {str(e)}")


@router.post("/rides/start")
async def create_ride_session(request: schemas.RideStartRequest, http_request: Request):
    try:
        client_ip = _client_ip(http_request)
        rate_limiter.enforce(
            scope=f"ride-start:device:{request.device_id}",
            rule=RIDE_START_RULE,
        )
        rate_limiter.enforce(
            scope=f"ride-start:ip:{client_ip}",
            rule=RIDE_START_RULE,
        )
        rate_limiter.enforce(
            scope=f"ride-start:bus:{request.bus_mac}",
            rule=RIDE_START_RULE,
        )
        session = await start_ride_session(
            device_id=request.device_id,
            bus_mac=request.bus_mac,
            user_lat=request.user_lat,
            user_lon=request.user_lon,
            user_accuracy_m=request.user_accuracy_m,
        )
        return {"success": True, "session": session.to_dict()}
    except RideSessionForbiddenError as e:
        raise HTTPException(status_code=403, detail=str(e))
    except RideSessionNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to start ride: {str(e)}")


@router.post("/rides/end")
async def close_ride_session(request: schemas.RideEndRequest):
    ended = end_ride_session(
        session_id=request.session_id,
        device_id=request.device_id,
    )
    if not ended:
        raise HTTPException(status_code=404, detail="Active ride session not found")
    return {"success": True}


@router.post("/rides/status")
async def ride_session_status(request: schemas.RideStatusRequest):
    session = get_active_ride_session(
        session_id=request.session_id,
        device_id=request.device_id,
    )
    if session is None:
        return {"success": True, "active": False, "session": None}
    return {"success": True, "active": True, "session": session.to_dict()}
