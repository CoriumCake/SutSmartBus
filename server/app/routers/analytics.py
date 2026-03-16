from fastapi import APIRouter, Query, HTTPException
from typing import List, Optional
from datetime import datetime, timedelta, timezone
from app import crud, models, analytics as analytics_module
import sqlite3
from core.config import settings

router = APIRouter(prefix="/api/analytics", tags=["Analytics"])

@router.get("/heatmap")
async def get_heatmap(limit: int = 1000, hours: int = Query(24, description="Get data from last X hours")):
    start_time = datetime.now(timezone.utc) - timedelta(hours=hours)
    return await crud.get_heatmap_data(limit=limit, start_time=start_time)

@router.get("/pm-grid")
async def get_pm_grid(limit: int = 5000, hours: int = Query(24, description="Get data from last X hours")):
    start_time = datetime.now(timezone.utc) - timedelta(hours=hours)
    return await crud.get_pm_grid_data(limit=limit, start_time=start_time)

@router.get("/passenger-count-history")
async def get_passenger_count_history(hours: int = 24):
    """Fetch history from SQLite DB."""
    try:
        data = analytics_module.get_passenger_history(hours=hours)
        return data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/passenger-stats")
async def get_passenger_stats(period: str = "daily"):
    """Fetch aggregated passenger stats."""
    try:
        data = analytics_module.get_pax_stats(period=period)
        return data
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/bus-load-prediction")
async def predict_bus_load(bus_id: str, stop_id: str):
    """Mock-up predictive service for bus loading."""
    # This is a placeholder for actual ML model logic
    return {
        "bus_id": bus_id,
        "stop_id": stop_id,
        "predicted_load": 0.45,
        "confidence": 0.82,
        "message": "Moderately busy based on historical Monday 10:00AM data"
    }
