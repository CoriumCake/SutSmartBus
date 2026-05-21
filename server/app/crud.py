from typing import List
from bson import ObjectId
from . import models, schemas
from datetime import datetime, timezone
import logging
from .database import db
from .passenger_rules import (
    clamp_passenger_count,
    is_at_default_parking,
    normalize_passenger_count,
    seats_available_for_count,
)
from core.config import settings

logger = logging.getLogger(__name__)

# Get collections
bus_collection = db.get_collection("buses")
route_collection = db.get_collection("routes")
stop_collection = db.get_collection("stops")
feedback_collection = db.get_collection("feedback")
hardware_location_collection = db.get_collection("hardware_locations")
blocked_mac_collection = db.get_collection("blocked_macs")
pm_zone_collection = db.get_collection("pm_zones")


def _serialize_mongo_document(document):
    if document is None:
        return None

    serialized = dict(document)

    mongo_id = serialized.get("_id")
    if isinstance(mongo_id, ObjectId):
        serialized["_id"] = str(mongo_id)

    route_id = serialized.get("route_id")
    if isinstance(route_id, ObjectId):
        serialized["route_id"] = str(route_id)

    stops = serialized.get("stops")
    if isinstance(stops, list):
        serialized["stops"] = [
            str(stop) if isinstance(stop, ObjectId) else stop
            for stop in stops
        ]

    return serialized


async def get_bus(bus_id: str):
    return _serialize_mongo_document(
        await bus_collection.find_one({"_id": ObjectId(bus_id)})
    )

async def get_bus_by_mac(mac_address: str):
    return _serialize_mongo_document(
        await bus_collection.find_one({"mac_address": mac_address})
    )

async def get_bus_by_bus_id(bus_id: str):
    return _serialize_mongo_document(
        await bus_collection.find_one({"bus_id": bus_id})
    )

async def get_bus_by_name(bus_name: str):
    return _serialize_mongo_document(
        await bus_collection.find_one({"bus_name": bus_name})
    )

async def get_buses(skip: int = 0, limit: int = 100):
    buses = await bus_collection.find().skip(skip).limit(limit).to_list(limit)
    serialized = [_serialize_mongo_document(bus) for bus in buses]
    missing_sensor_count = sum(
        1
        for bus in serialized
        if bus.get("pm2_5") is None
        or bus.get("pm10") is None
        or bus.get("temp") is None
        or bus.get("hum") is None
    )
    zero_sensor_count = sum(
        1
        for bus in serialized
        if bus.get("pm2_5") == 0
        and bus.get("pm10") == 0
        and bus.get("temp") == 0
        and bus.get("hum") == 0
    )
    logger.info(
        "GET /api/buses returning %s buses; missing_sensor_fields=%s zero_sensor_sets=%s",
        len(serialized),
        missing_sensor_count,
        zero_sensor_count,
    )
    for bus in serialized:
        logger.debug(
            "GET /api/buses bus=%s name=%s lat=%s lon=%s pm2_5=%s pm10=%s temp=%s hum=%s updated=%s",
            bus.get("mac_address"),
            bus.get("bus_name"),
            bus.get("current_lat"),
            bus.get("current_lon"),
            bus.get("pm2_5"),
            bus.get("pm10"),
            bus.get("temp"),
            bus.get("hum"),
            bus.get("last_updated"),
        )
    return serialized

async def create_bus(bus: models.Bus):
    bus_dict = bus.model_dump(by_alias=True, exclude=["id"])
    result = await bus_collection.insert_one(bus_dict)
    new_bus = await bus_collection.find_one({"_id": result.inserted_id})
    return _serialize_mongo_document(new_bus)

async def update_bus_location(
    mac_address: str,
    lat: float | None,
    lon: float | None,
    seats_available: int | None,
    bus_id: str | None = None,
    pm2_5: float | None = None,
    pm10: float | None = None,
    bus_name: str = None,
    temp: float | None = None,
    hum: float | None = None,
    person_count: int = None,
    rssi: int = None,
    apply_parking_reset: bool = True,
    use_default_location_if_missing: bool = True,
):
    # This is an 'upsert' operation: it updates a bus if it exists, or creates it if it doesn't.
    # This is useful for when a bus device comes online for the first time.
    existing_bus = await get_bus_by_mac(mac_address)

    update_data = {
        "last_updated": datetime.now(timezone.utc)
    }

    if bus_id:
        update_data["bus_id"] = bus_id

    sensor_update = {
        "pm2_5": pm2_5,
        "pm10": pm10,
        "temp": temp,
        "hum": hum,
    }
    for field, value in sensor_update.items():
        if value is not None:
            update_data[field] = value

    if all(value is None for value in sensor_update.values()):
        logger.debug(
            "Bus %s update has no sensor values; preserving previous PM/temp/hum fields",
            mac_address,
        )
    else:
        logger.info(
            "Bus %s sensor update pm2_5=%s pm10=%s temp=%s hum=%s",
            mac_address,
            pm2_5,
            pm10,
            temp,
            hum,
        )
    
    if rssi is not None:
        update_data["rssi"] = rssi
    
    # Only update location if valid coordinates are provided
    if lat is not None:
        update_data["current_lat"] = lat
    if lon is not None:
        update_data["current_lon"] = lon

    # When a device comes online before GPS/PM hardware reports a real location,
    # place it at a predictable fallback point so the app can still render it.
    if use_default_location_if_missing and lat is None and lon is None:
        if not existing_bus or existing_bus.get("current_lat") is None or existing_bus.get("current_lon") is None:
            update_data["current_lat"] = settings.DEFAULT_BUS_LAT
            update_data["current_lon"] = settings.DEFAULT_BUS_LON

    effective_lat = update_data.get("current_lat", existing_bus.get("current_lat") if existing_bus else None)
    effective_lon = update_data.get("current_lon", existing_bus.get("current_lon") if existing_bus else None)

    if person_count is not None:
        normalized_count = (
            normalize_passenger_count(person_count, effective_lat, effective_lon)
            if apply_parking_reset
            else clamp_passenger_count(person_count)
        )
        update_data["person_count"] = normalized_count
        update_data["seats_available"] = seats_available_for_count(normalized_count)
    else:
        current_count = existing_bus.get("person_count", 0) if existing_bus else 0
        if apply_parking_reset and is_at_default_parking(effective_lat, effective_lon):
            update_data["person_count"] = 0
            update_data["seats_available"] = seats_available_for_count(0)
        else:
            if seats_available is not None:
                update_data["seats_available"] = max(0, seats_available)
            if existing_bus and current_count is not None:
                update_data.setdefault("person_count", current_count)

    if bus_name:
        # Prevent overwriting a good name with a default "Bus-MAC" name
        # Only update if the new name is NOT a generated default, OR if we are creating a new bus
        # This logic is tricky in an upsert, so we rely on the caller or check existence first?
        # Simpler approach: If the caller passed a name, trust it? 
        # No, mqtt.py generates a default. We should filter it there or here.
        # Let's filter here: access DB to check existing name if new one is generic.
        
        # Actually, let's keep it simple: Update name if provided. 
        # But we will rely on mqtt.py to NOT pass a default name if it's not in the payload.
        update_data["bus_name"] = bus_name
        
    result = await bus_collection.update_one(
        {"mac_address": mac_address},
        {"$set": update_data},
        upsert=True
    )
    logger.info(
        "update_bus_location bus=%s matched=%s upserted=%s modified=%s fields=%s",
        mac_address,
        result.matched_count,
        result.upserted_id,
        result.modified_count,
        sorted(update_data.keys()),
    )
    if result.matched_count == 1 or result.upserted_id:
        updated_bus = await get_bus_by_mac(mac_address)
        logger.debug(
            "Stored bus=%s pm2_5=%s pm10=%s temp=%s hum=%s lat=%s lon=%s",
            mac_address,
            updated_bus.get("pm2_5") if updated_bus else None,
            updated_bus.get("pm10") if updated_bus else None,
            updated_bus.get("temp") if updated_bus else None,
            updated_bus.get("hum") if updated_bus else None,
            updated_bus.get("current_lat") if updated_bus else None,
            updated_bus.get("current_lon") if updated_bus else None,
        )
        return updated_bus
    return None

async def delete_bus(mac_address: str):
    result = await bus_collection.delete_one({"mac_address": mac_address})
    return result.deleted_count > 0

async def get_route(route_id: str):
    return await route_collection.find_one({"_id": ObjectId(route_id)})

async def get_routes(skip: int = 0, limit: int = 100):
    return await route_collection.find().skip(skip).limit(limit).to_list(limit)

async def create_route(route: models.Route):
    route_dict = route.model_dump(by_alias=True, exclude=["id"])
    result = await route_collection.insert_one(route_dict)
    new_route = await route_collection.find_one({"_id": result.inserted_id})
    return new_route

async def get_stop(stop_id: str):
    return await stop_collection.find_one({"_id": ObjectId(stop_id)})

async def get_stops(skip: int = 0, limit: int = 100):
    return await stop_collection.find().skip(skip).limit(limit).to_list(limit)

async def create_stop(stop: models.Stop):
    stop_dict = stop.model_dump(by_alias=True, exclude=["id"])
    result = await stop_collection.insert_one(stop_dict)
    new_stop = await stop_collection.find_one({"_id": result.inserted_id})
    return new_stop

async def save_route(route_data: schemas.RouteCreate):
    """Upsert a route by its ID (from Flutter app)."""
    route_dict = route_data.model_dump()
    route_id = route_dict.get("route_id")
    if not route_id:
        return False
    
    # Map Flutter field names to MongoDB models if needed
    # In this case, we use the raw dict but ensure ID is mapped
    await route_collection.update_one(
        {"id": route_id},
        {"$set": route_dict},
        upsert=True
    )
    return True

async def delete_route(route_id: str):
    """Delete a route by its ID."""
    result = await route_collection.delete_one({"id": route_id})
    return result.deleted_count > 0

async def get_stops_for_route(route_id: str):
    route = await get_route(route_id)
    if route and "stops" in route:
        stop_ids = route["stops"]
        return await stop_collection.find({"_id": {"$in": stop_ids}}).to_list(length=None)
    return []

async def create_feedback(feedback: models.Feedback):
    feedback_dict = feedback.model_dump(by_alias=True, exclude=["id"])
    result = await feedback_collection.insert_one(feedback_dict)
    new_feedback = await feedback_collection.find_one({"_id": result.inserted_id})
    return new_feedback

async def get_feedback(skip: int = 0, limit: int = 100):
    return await feedback_collection.find().sort("created_at", -1).skip(skip).limit(limit).to_list(limit)

async def create_hardware_location(location: models.HardwareLocation):
    location_dict = location.model_dump(by_alias=True, exclude=["id"])
    result = await hardware_location_collection.insert_one(location_dict)
    new_location = await hardware_location_collection.find_one({"_id": result.inserted_id})
    logger.debug(
        "Created hardware_location bus=%s lat=%s lon=%s pm2_5=%s pm10=%s rssi=%s",
        location_dict.get("bus_mac"),
        location_dict.get("lat"),
        location_dict.get("lon"),
        location_dict.get("pm2_5"),
        location_dict.get("pm10"),
        location_dict.get("rssi"),
    )
    return new_location

async def get_hardware_locations(skip: int = 0, limit: int = 100):
    return await hardware_location_collection.find().sort("timestamp", -1).skip(skip).limit(limit).to_list(limit)

# --- MAC Address Blocking ---
async def block_mac_address(mac: models.BlockedMAC):
    mac_dict = mac.model_dump(by_alias=True, exclude=["id"])
    await blocked_mac_collection.update_one(
        {"mac_address": mac.mac_address},
        {"$set": mac_dict},
        upsert=True
    )
    return await blocked_mac_collection.find_one({"mac_address": mac.mac_address})

async def is_mac_blocked(mac_address: str) -> bool:
    return await blocked_mac_collection.find_one({"mac_address": mac_address}) is not None


# --- Heatmap Data ---
async def get_heatmap_data(limit: int = 2000, start_time: datetime = None):
    # Fetch recent hardware locations for heatmap
    # We only need lat, lon, and pm2_5
    query = {"lat": {"$ne": None}, "lon": {"$ne": None}, "pm2_5": {"$gt": 0}}
    
    if start_time:
        query["timestamp"] = {"$gte": start_time}
        
    cursor = hardware_location_collection.find(query).sort("timestamp", -1).limit(limit)
    
    points = []
    async for doc in cursor:
        points.append({
            "latitude": doc["lat"],
            "longitude": doc["lon"],
            "weight": doc["pm2_5"]
        })
    return points

async def get_wifi_heatmap_data(limit: int = 2000, start_time: datetime = None):
    # Fetch recent hardware locations with Wi-Fi RSSI for connection testing.
    query = {"lat": {"$ne": None}, "lon": {"$ne": None}, "rssi": {"$ne": None}}

    if start_time:
        query["timestamp"] = {"$gte": start_time}

    cursor = hardware_location_collection.find(query).sort("timestamp", -1).limit(limit)

    points = []
    async for doc in cursor:
        points.append({
            "latitude": doc["lat"],
            "longitude": doc["lon"],
            "rssi": doc["rssi"],
            "bus_mac": doc.get("bus_mac"),
        })
    return points

async def get_pm_grid_data(limit: int = 10000, start_time: datetime = None, grid_size_degrees: float = 0.001):
    """
    Fetch PM data aggregated into grid cells using MongoDB aggregation pipeline.
    Grid size in degrees (0.001° ≈ 111m at equator)
    Returns: [{ latitude, longitude, avg_pm2_5, count, last_updated }]
    """
    match_stage = {"lat": {"$ne": None}, "lon": {"$ne": None}, "pm2_5": {"$gt": 0}}
    if start_time:
        match_stage["timestamp"] = {"$gte": start_time}
    
    pipeline = [
        {"$match": match_stage},
        {"$sort": {"timestamp": -1}},
        {"$limit": limit},
        {
            "$group": {
                "_id": {
                    "lat": {
                        "$add": [
                            {
                                "$subtract": [
                                    "$lat",
                                    {"$mod": ["$lat", grid_size_degrees]}
                                ]
                            },
                            {"$divide": [grid_size_degrees, 2]}
                        ]
                    },
                    "lon": {
                        "$add": [
                            {
                                "$subtract": [
                                    "$lon",
                                    {"$mod": ["$lon", grid_size_degrees]}
                                ]
                            },
                            {"$divide": [grid_size_degrees, 2]}
                        ]
                    }
                },
                "avg_pm2_5": {"$avg": "$pm2_5"},
                "count": {"$sum": 1},
                "last_updated": {"$max": "$timestamp"}
            }
        },
        {
            "$project": {
                "_id": 0,
                "latitude": "$_id.lat",
                "longitude": "$_id.lon",
                "avg_pm2_5": {"$round": ["$avg_pm2_5", 2]},
                "count": 1,
                "last_updated": 1
            }
        }
    ]
    
    cursor = hardware_location_collection.aggregate(pipeline)
    result = []
    async for doc in cursor:
        if doc.get("last_updated"):
            doc["last_updated"] = doc["last_updated"].isoformat()
        result.append(doc)
        
    return result
    
async def delete_hardware_locations_by_mac(mac_address: str):
    """Delete all location history for a specific device (used for debug cleanup)"""
    result = await hardware_location_collection.delete_many({"bus_mac": mac_address})
    return result.deleted_count


# --- PM Zones ---
async def get_pm_zones(skip: int = 0, limit: int = 100):
    return await pm_zone_collection.find().skip(skip).limit(limit).to_list(limit)

async def get_pm_zone(zone_id: str):
    return await pm_zone_collection.find_one({"_id": ObjectId(zone_id)})

async def create_pm_zone(zone: models.PMZone):
    zone_dict = zone.model_dump(by_alias=True, exclude=["id"])
    result = await pm_zone_collection.insert_one(zone_dict)
    return await pm_zone_collection.find_one({"_id": result.inserted_id})

async def update_pm_zone(zone_id: str, zone_data: dict):
    # Ensure we don't try to update the ID
    if "_id" in zone_data: del zone_data["_id"]
    if "id" in zone_data: del zone_data["id"]
    
    zone_data["last_updated"] = datetime.now(timezone.utc)
    
    result = await pm_zone_collection.update_one(
        {"_id": ObjectId(zone_id)},
        {"$set": zone_data}
    )
    if result.matched_count == 0:
        return None
    return await get_pm_zone(zone_id)

async def delete_pm_zone(zone_id: str):
    result = await pm_zone_collection.delete_one({"_id": ObjectId(zone_id)})
    return result.deleted_count > 0

async def update_pm_zone_stats(zone_id: ObjectId | str, avg_pm25: float, avg_pm10: float):
    """Update rolling averages for a specific zone."""
    z_id = ObjectId(zone_id) if isinstance(zone_id, str) else zone_id
    await pm_zone_collection.update_one(
        {"_id": z_id},
        {
            "$set": {
                "avg_pm25": avg_pm25,
                "avg_pm10": avg_pm10,
                "last_updated": datetime.now(timezone.utc)
            }
        }
    )

