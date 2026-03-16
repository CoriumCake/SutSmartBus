from fastapi import APIRouter, HTTPException, Query, Body, Response
from typing import List, Optional, Annotated
from datetime import datetime
import json
import sqlite3
from app import analytics as analytics_module
from core.config import settings
from pydantic import BaseModel

router = APIRouter(prefix="/api/passengers", tags=["Passengers"])

class PassengerUpdate(BaseModel):
    bus_mac: str
    count: int
    lat: float = 0.0
    lon: float = 0.0

@router.post("/update-count")
async def update_passenger_count(
    bus_mac: str = Query(...), 
    count: int = Query(...), 
    lat: float = Query(0.0), 
    lon: float = Query(0.0)
):
    """
    Receives current passenger count from a bus.
    Updates SQLite DB for history.
    """
    try:
        analytics_module.record_passenger_count(bus_mac, count, lat, lon)
        return {"success": True, "bus": bus_mac, "new_count": count}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/latest")
async def get_latest_pax_counts():
    """Returns the most recent passenger count for each bus."""
    try:
        # Connect to SQLite
        conn = sqlite3.connect(settings.DB_FILE)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        # Get latest per bus mac
        cursor.execute('''
            SELECT bus_mac, count, timestamp 
            FROM passenger_history 
            WHERE id IN (SELECT MAX(id) FROM passenger_history GROUP BY bus_mac)
        ''')
        rows = cursor.fetchall()
        conn.close()
        
        return [dict(row) for row in rows]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
