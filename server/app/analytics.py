"""
Air Quality Analytics Module
Provides endpoints for air quality data analysis and visualization.
"""

import sqlite3
from datetime import datetime, timedelta, timezone
from typing import List, Optional
from . import crud
from .database import db
from .passenger_rules import clamp_passenger_count
from core.config import settings

# Get hardware locations collection
hardware_location_collection = db.get_collection("hardware_locations")

def record_passenger_count(
    bus_mac: str,
    count: int,
    lat: float = 0.0,
    lon: float = 0.0,
    apply_parking_reset: bool = True,
):
    """Log passenger count to SQLite history for local analytics."""
    try:
        normalized_count = (
            normalize_passenger_count(count, lat, lon)
            if apply_parking_reset
            else clamp_passenger_count(count)
        )
        with sqlite3.connect(settings.DB_FILE) as conn:
            conn.execute(
                "INSERT INTO passenger_history (bus_mac, count, timestamp, lat, lon) VALUES (?, ?, ?, ?, ?)",
                (bus_mac, normalized_count, datetime.now(timezone.utc).isoformat(), lat, lon)
            )
            conn.commit()
        return normalized_count
    except Exception as e:
        print(f"Error recording passenger count: {e}")
        return 0


def get_passenger_history(hours: int = 24) -> List[dict]:
    """Return recent passenger-count history rows from SQLite."""
    lookback_hours = max(1, hours)
    cutoff = datetime.now(timezone.utc) - timedelta(hours=lookback_hours)

    with sqlite3.connect(settings.DB_FILE) as conn:
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            """
            SELECT bus_mac, count, timestamp, lat, lon
            FROM passenger_history
            WHERE timestamp >= ?
            ORDER BY timestamp ASC
            """,
            (cutoff.isoformat(),),
        ).fetchall()

    normalized_rows = []
    for row in rows:
        item = dict(row)
        item["count"] = clamp_passenger_count(item.get("count"))
        normalized_rows.append(item)

    return normalized_rows


def get_pax_stats(period: str = "daily") -> dict:
    """Return aggregated passenger stats built from SQLite history."""
    period_key = (period or "daily").lower()
    if period_key == "weekly":
        bucket_format = "%Y-%W"
        label = "week"
        lookback = timedelta(days=28)
    else:
        bucket_format = "%Y-%m-%d"
        label = "day"
        lookback = timedelta(days=14)

    cutoff = datetime.now(timezone.utc) - lookback

    with sqlite3.connect(settings.DB_FILE) as conn:
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            """
            SELECT
                bus_mac,
                count,
                timestamp,
                lat,
                lon,
                strftime(?, timestamp) AS bucket
            FROM passenger_history
            WHERE timestamp >= ?
            ORDER BY timestamp ASC
            """,
            (bucket_format, cutoff.isoformat()),
        ).fetchall()

    if not rows:
        return {
            "period": period_key,
            "total_samples": 0,
            "overall_average": 0,
            "peak_count": 0,
            "peak_timestamp": None,
            "buckets": [],
        }

    bucket_stats: dict[str, dict] = {}
    total_count = 0
    peak_row = None

    for row in rows:
        count = clamp_passenger_count(row["count"])
        total_count += count

        peak_count = (
            clamp_passenger_count(peak_row["count"])
            if peak_row is not None
            else -1
        )
        if peak_row is None or count > peak_count:
            peak_row = row

        bucket = row["bucket"] or "unknown"
        current = bucket_stats.setdefault(
            bucket,
            {
                label: bucket,
                "sample_count": 0,
                "average_count": 0.0,
                "max_count": 0,
                "buses": {},
            },
        )
        current["sample_count"] += 1
        current["average_count"] += count
        current["max_count"] = max(int(current["max_count"]), count)
        current["buses"][row["bus_mac"]] = (
            current["buses"].get(row["bus_mac"], 0) + 1
        )

    buckets = []
    for bucket, stats in bucket_stats.items():
        sample_count = int(stats["sample_count"])
        buckets.append(
            {
                label: bucket,
                "sample_count": sample_count,
                "average_count": round(stats["average_count"] / sample_count, 2),
                "max_count": int(stats["max_count"]),
                "active_buses": len(stats["buses"]),
            }
        )

    buckets.sort(key=lambda item: item[label])

    return {
        "period": period_key,
        "total_samples": len(rows),
        "overall_average": round(total_count / len(rows), 2),
        "peak_count": clamp_passenger_count(peak_row["count"]) if peak_row is not None else 0,
        "peak_timestamp": peak_row["timestamp"] if peak_row is not None else None,
        "buckets": buckets,
    }


async def get_zone_heatmap_data(hours: int = 24, grid_size: float = 0.001, bus_mac: Optional[str] = None):
    """
    Get air quality data grouped by geographic zones for heatmap visualization.
    
    Args:
        hours: Number of hours of historical data to include
        grid_size: Size of grid cells in degrees (0.001 ≈ 111 meters)
    
    Returns:
        List of zone objects with lat, lon, avg_pm25, avg_pm10, count
    """
    cutoff_time = datetime.now(timezone.utc) - timedelta(hours=hours)
    
    match_stage = {
        "timestamp": {"$gte": cutoff_time},
        "lat": {"$ne": None},
        "lon": {"$ne": None},
        "pm2_5": {"$gt": 0}  # Filter out 0 values (artifacts/missing data)
    }

    if bus_mac:
        match_stage["bus_mac"] = bus_mac

    # Aggregation pipeline to group by grid cells
    pipeline = [
        {
            "$match": match_stage
        },
        {
            "$project": {
                "grid_lat": {
                    "$multiply": [
                        {"$floor": {"$divide": ["$lat", grid_size]}},
                        grid_size
                    ]
                },
                "grid_lon": {
                    "$multiply": [
                        {"$floor": {"$divide": ["$lon", grid_size]}},
                        grid_size
                    ]
                },
                "pm2_5": 1,
                "pm10": 1,
                "timestamp": 1
            }
        },
        {
            "$group": {
                "_id": {
                    "lat": "$grid_lat",
                    "lon": "$grid_lon"
                },
                "avg_pm25": {"$avg": "$pm2_5"},
                "avg_pm10": {"$avg": "$pm10"},
                "max_pm25": {"$max": "$pm2_5"},
                "min_pm25": {"$min": "$pm2_5"},
                "count": {"$sum": 1},
                "last_updated": {"$max": "$timestamp"}
            }
        },
        {
            "$project": {
                "_id": 0,
                "lat": {"$add": ["$_id.lat", grid_size / 2]},  # Center of grid cell
                "lon": {"$add": ["$_id.lon", grid_size / 2]},
                "avg_pm25": {"$round": ["$avg_pm25", 1]},
                "avg_pm10": {"$round": ["$avg_pm10", 1]},
                "max_pm25": {"$round": ["$max_pm25", 1]},
                "min_pm25": {"$round": ["$min_pm25", 1]},
                "count": 1,
                "last_updated": 1
            }
        },
        {"$sort": {"avg_pm25": 1}}  # Sort by air quality (best first)
    ]
    
    try:
        zones = await hardware_location_collection.aggregate(pipeline).to_list(length=500)
        return zones
    except Exception as e:
        print(f"Error in get_zone_heatmap_data: {e}")
        return []


async def get_time_series_data(hours: int = 24, interval_minutes: int = 60, bus_mac: Optional[str] = None):
    """
    Get air quality time series data for trend visualization.
    
    Args:
        hours: Number of hours of data to include
        hours: Number of hours of data to include
        interval_minutes: Aggregation interval in minutes
        bus_mac: Optional MAC address to filter by specific bus
    
    Returns:
        List of time-bucketed averages with timestamp, avg_pm25, avg_pm10
    """
    cutoff_time = datetime.now(timezone.utc) - timedelta(hours=hours)
    
    match_stage = {
        "timestamp": {"$gte": cutoff_time},
        "pm2_5": {"$gt": 0}  # Filter out 0 values
    }
    
    if bus_mac:
        match_stage["bus_mac"] = bus_mac

    pipeline = [
        {
            "$match": match_stage
        },
        {
            "$group": {
                "_id": {
                    "$dateTrunc": {
                        "date": "$timestamp",
                        "unit": "minute",
                        "binSize": interval_minutes
                    }
                },
                "avg_pm25": {"$avg": "$pm2_5"},
                "avg_pm10": {"$avg": "$pm10"},
                "avg_temp": {"$avg": "$temp"},
                "avg_hum": {"$avg": "$hum"},
                "count": {"$sum": 1}
            }
        },
        {
            "$project": {
                "_id": 0,
                "timestamp": "$_id",
                "avg_pm25": {"$round": ["$avg_pm25", 1]},
                "avg_pm10": {"$round": ["$avg_pm10", 1]},
                "avg_temp": {"$round": ["$avg_temp", 1]},
                "avg_hum": {"$round": ["$avg_hum", 0]},
                "count": 1
            }
        },
        {"$sort": {"timestamp": 1}}
    ]
    
    try:
        series = await hardware_location_collection.aggregate(pipeline).to_list(length=500)
        return series
    except Exception as e:
        print(f"Error in get_time_series_data: {e}")
        return []


async def get_overall_stats(hours: int = 24, bus_mac: Optional[str] = None):
    """
    Get overall air quality statistics for the dashboard summary.
    """
    cutoff_time = datetime.now(timezone.utc) - timedelta(hours=hours)
    
    match_stage = {
        "timestamp": {"$gte": cutoff_time},
        "pm2_5": {"$gt": 0}  # Filter out 0 values
    }

    if bus_mac:
        match_stage["bus_mac"] = bus_mac

    pipeline = [
        {
            "$match": match_stage
        },
        {
            "$group": {
                "_id": None,
                "avg_pm25": {"$avg": "$pm2_5"},
                "avg_pm10": {"$avg": "$pm10"},
                "max_pm25": {"$max": "$pm2_5"},
                "min_pm25": {"$min": "$pm2_5"},
                "avg_temp": {"$avg": "$temp"},
                "avg_hum": {"$avg": "$hum"},
                "total_readings": {"$sum": 1}
            }
        },
        {
            "$project": {
                "_id": 0,
                "avg_pm25": {"$round": ["$avg_pm25", 1]},
                "avg_pm10": {"$round": ["$avg_pm10", 1]},
                "max_pm25": {"$round": ["$max_pm25", 1]},
                "min_pm25": {"$round": ["$min_pm25", 1]},
                "avg_temp": {"$round": ["$avg_temp", 1]},
                "avg_hum": {"$round": ["$avg_hum", 0]},
                "total_readings": 1
            }
        }
    ]
    
    try:
        result = await hardware_location_collection.aggregate(pipeline).to_list(length=1)
        if result:
            return result[0]
        return {
            "avg_pm25": 0,
            "avg_pm10": 0,
            "max_pm25": 0,
            "min_pm25": 0,
            "avg_temp": 0,
            "avg_hum": 0,
            "total_readings": 0
        }
    except Exception as e:
        print(f"Error in get_overall_stats: {e}")
        return {"error": str(e)}
