from fastapi import APIRouter, HTTPException, Query
import sqlite3
from app import analytics as analytics_module, crud
from app.passenger_rules import clamp_passenger_count
from core.config import settings

router = APIRouter(prefix="/api/passengers", tags=["Passengers"])

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
        apply_parking_reset = await crud.get_reset_passenger_count_at_terminal_stop()
        normalized_count = analytics_module.record_passenger_count(
            bus_mac,
            count,
            lat,
            lon,
            apply_parking_reset=apply_parking_reset,
        )
        return {"success": True, "bus": bus_mac, "new_count": normalized_count}
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
        
        normalized_rows = []
        for row in rows:
            item = dict(row)
            item["count"] = clamp_passenger_count(item.get("count"))
            normalized_rows.append(item)

        return normalized_rows
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
