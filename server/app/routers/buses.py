from fastapi import APIRouter, HTTPException, Body
from typing import List
from app import crud, models, constants, schemas
from app.mqtt import client as mqtt_client
import json
import time

router = APIRouter(prefix="/api", tags=["Buses"])

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
async def ring_bell(request: schemas.RingRequest):
    try:
        mqtt_client.publish(constants.TOPIC_RING, json.dumps({
            "command": "ring",
            "bus_mac": request.bus_mac,
            "timestamp": int(time.time())
        }))
        return {"success": True, "message": f"Ring signal sent to {request.bus_mac}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to send ring: {str(e)}")
