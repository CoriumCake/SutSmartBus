from fastapi import APIRouter, HTTPException, Body
from typing import List
from app import crud, models, schemas

router = APIRouter(prefix="/api/pm_zones", tags=["PM Zones"])

@router.get("", response_model=List[models.PMZone])
async def list_pm_zones(skip: int = 0, limit: int = 100):
    return await crud.get_pm_zones(skip=skip, limit=limit)

@router.get("/{zone_id}", response_model=models.PMZone)
async def get_pm_zone(zone_id: str):
    zone = await crud.get_pm_zone(zone_id)
    if not zone:
        raise HTTPException(status_code=404, detail="PM Zone not found")
    return zone

@router.post("", response_model=models.PMZone)
async def create_pm_zone(zone: models.PMZone):
    return await crud.create_pm_zone(zone)

@router.put("/{zone_id}", response_model=models.PMZone)
async def update_pm_zone(zone_id: str, zone_data: dict = Body(...)):
    updated_zone = await crud.update_pm_zone(zone_id, zone_data)
    if not updated_zone:
        raise HTTPException(status_code=404, detail="PM Zone not found")
    return updated_zone

@router.delete("/{zone_id}")
async def delete_pm_zone(zone_id: str):
    success = await crud.delete_pm_zone(zone_id)
    if not success:
        raise HTTPException(status_code=404, detail="PM Zone not found")
    return {"success": True, "message": "PM Zone deleted successfully"}
