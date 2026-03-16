from fastapi import APIRouter, HTTPException
from typing import List
from app import crud, models, constants, schemas
import os
import json

router = APIRouter(prefix="/api", tags=["Routes"])

@router.get("/routes", response_model=List[models.Route])
async def list_routes(skip: int = 0, limit: int = 100):
    return await crud.get_routes(skip=skip, limit=limit)

@router.get("/stops", response_model=List[models.Stop])
async def list_stops(skip: int = 0, limit: int = 100):
    return await crud.get_stops(skip=skip, limit=limit)

@router.get("/bus-route-mapping", response_model=schemas.RouteData)
async def get_bus_route_mapping():
    """Returns the static mapping of buses to routes and available route files."""
    return constants.BUS_ROUTE_MAPPING

@router.get("/route-file/{filename}")
async def get_route_file(filename: str):
    """Returns the content of a specific route geojson file."""
    # Security check: only allow files in the routes directory
    if ".." in filename or "/" in filename or "\\" in filename:
        raise HTTPException(status_code=400, detail="Invalid filename")
    
    file_path = os.path.join(constants.ROUTES_DIR, filename)
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="Route file not found")
        
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error reading route file: {str(e)}")
