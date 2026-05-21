import paho.mqtt.client as mqtt
import os
import json
import asyncio
import time
import sqlite3
import logging
from datetime import datetime, timezone
from . import crud, models, constants, state
from .passenger_rules import (
    clamp_passenger_count,
    is_at_default_parking,
    normalize_passenger_count,
    seats_available_for_count,
)
from .security import sign_bus_command
from core.config import settings

logger = logging.getLogger(__name__)
RESET_COUNT_COMMAND_COOLDOWN_SECONDS = 60
_last_reset_count_command_at: dict[str, int] = {}


def _optional_float(payload: dict, key: str) -> float | None:
    if key not in payload or payload.get(key) is None:
        return None
    return float(payload[key])


def _is_status_topic(topic: str) -> bool:
    return topic.startswith("sut/bus/") and topic.endswith("/status")


def _ring_secret() -> str:
    return settings.RING_COMMAND_SECRET or settings.API_SECRET_KEY


def _coerce_location_override(
    *,
    no_gps_mode_enabled: bool,
    lat: float | None,
    lon: float | None,
) -> tuple[float | None, float | None, bool]:
    if no_gps_mode_enabled:
        return None, None, False

    has_payload_location = lat is not None and lon is not None
    return lat, lon, has_payload_location


def bus_document_to_app_payload(bus_doc: dict) -> dict:
    """Normalize a Mongo bus document to the app's MQTT payload shape."""
    if not bus_doc:
        return {}

    return {
        "bus_id": bus_doc.get("bus_id"),
        "bus_mac": bus_doc.get("mac_address"),
        "bus_name": bus_doc.get("bus_name"),
        "lat": bus_doc.get("current_lat"),
        "lon": bus_doc.get("current_lon"),
        "pm2_5": bus_doc.get("pm2_5", 0.0),
        "pm10": bus_doc.get("pm10", 0.0),
        "temp": bus_doc.get("temp", 0.0),
        "hum": bus_doc.get("hum", 0.0),
        "seats_available": bus_doc.get("seats_available", 0),
        "person_count": bus_doc.get("person_count", 0),
        "rssi": bus_doc.get("rssi"),
        "count_source": bus_doc.get("count_source"),
    }


async def resolve_bus_identity(
    bus_mac: str,
    bus_name: str | None,
    bus_id: str | None = None,
):
    bus = None
    if bus_id:
        bus = await crud.get_bus_by_bus_id(bus_id)
    if bus is None:
        bus = await crud.get_bus_by_mac(bus_mac)
    if bus is None and bus_name:
        bus = await crud.get_bus_by_name(bus_name)

    resolved_bus_id = bus.get("bus_id") if bus else bus_id
    resolved_mac = bus.get("mac_address") if bus else bus_mac
    resolved_name = bus.get("bus_name") if bus else bus_name
    return bus, resolved_bus_id, resolved_mac, resolved_name


async def resolve_effective_bus_identity(
    *,
    bus_mac: str,
    bus_name: str | None,
    bus_id: str | None = None,
    no_gps_mode_enabled: bool = False,
    assigned_bus_mac: str | None = None,
):
    requested_assigned_mac = (assigned_bus_mac or "").strip()
    if no_gps_mode_enabled and requested_assigned_mac:
        assigned_bus, assigned_bus_id, assigned_mac, assigned_name = (
            await resolve_bus_identity(
                requested_assigned_mac,
                None,
                None,
            )
        )
        effective_assigned_mac = assigned_mac or requested_assigned_mac
        return (
            assigned_bus,
            assigned_bus_id,
            effective_assigned_mac,
            assigned_name,
        )

    return await resolve_bus_identity(bus_mac, bus_name, bus_id)


def publish_reset_count_command(*, bus_mac: str | None, bus_id: str | None = None):
    secret = _ring_secret()
    if not secret:
        logger.warning("Skipping ESP32-CAM reset command because no command secret is configured")
        return

    targets = []
    for target in (bus_mac, bus_id):
        normalized = (target or "").strip()
        if normalized and normalized not in targets:
            targets.append(normalized)

    timestamp = int(time.time())
    for target in targets:
        last_sent_at = _last_reset_count_command_at.get(target)
        if last_sent_at is not None and timestamp - last_sent_at < RESET_COUNT_COMMAND_COOLDOWN_SECONDS:
            continue

        payload = {
            "command": "reset_count",
            "bus_mac": target,
            "timestamp": timestamp,
            "sig": sign_bus_command(
                command="reset_count",
                secret=secret,
                bus_mac=target,
                timestamp=timestamp,
            ),
        }
        client.publish(constants.ring_topic_for_bus(target), json.dumps(payload), qos=1)
        _last_reset_count_command_at[target] = timestamp
        logger.info("Published ESP32-CAM passenger reset command target=%s", target)

# Helper for Point in Polygon (Ray Casting)
def is_point_in_polygon(lat: float, lon: float, polygon: list):
    num_vertices = len(polygon)
    x, y = lon, lat
    inside = False
    
    # Polygon is list of [lat, lon]
    p1 = polygon[0]
    p1x, p1y = p1[1], p1[0]
    
    for i in range(num_vertices + 1):
        p2 = polygon[i % num_vertices]
        p2x, p2y = p2[1], p2[0]
        
        if y > min(p1y, p2y):
            if y <= max(p1y, p2y):
                if x <= max(p1x, p2x):
                    if p1y != p2y:
                        xinters = (y - p1y) * (p2x - p1x) / (p2y - p1y) + p1x
                    if p1x == p2x or x <= xinters:
                        inside = not inside
        p1x, p1y = p2x, p2y
        
    return inside

async def check_pm_zones_logic(bus_mac, lat, lon, pm2_5, pm10, temp, hum):
    try:
        zones = await crud.get_pm_zones()
        for zone in zones:
            is_inside = False
            
            # Check Polygon
            if "points" in zone and zone["points"] and len(zone["points"]) >= 3:
                is_inside = is_point_in_polygon(lat, lon, zone["points"])
            
            # Check Radius (Fallback)
            elif "lat" in zone and "lon" in zone:
                import math
                R = 6371000
                phi1 = lat * math.pi / 180
                phi2 = zone["lat"] * math.pi / 180
                dphi = (zone["lat"] - lat) * math.pi / 180
                dlambda = (zone["lon"] - lon) * math.pi / 180
                a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2) * math.sin(dlambda/2)**2
                c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
                distance = R * c
                if distance <= zone.get("radius", 50.0):
                    is_inside = True

            if is_inside:
                print(f"📍 Bus {bus_mac} inside PM Zone: {zone.get('name')}")
                
                # Log to CSV
                data_dir = "data"
                if not os.path.exists(data_dir):
                    os.makedirs(data_dir)
                    
                filename = os.path.join(data_dir, f"pm_zone_{zone['_id']}.csv")
                file_exists = os.path.exists(filename)
                
                with open(filename, 'a') as f:
                    if not file_exists:
                        f.write("timestamp,bus_mac,pm2_5,pm10,temp,hum\n")
                    timestamp_str = datetime.now(timezone.utc).isoformat()
                    f.write(f"{timestamp_str},{bus_mac},{pm2_5},{pm10},{temp},{hum}\n")
                
                # Update Stats
                current_avg_pm25 = zone.get("avg_pm25", 0.0)
                current_avg_pm10 = zone.get("avg_pm10", 0.0)
                alpha = 0.1
                
                if current_avg_pm25 == 0:
                    new_avg_pm25 = pm2_5
                    new_avg_pm10 = pm10
                else:
                    new_avg_pm25 = (alpha * pm2_5) + ((1 - alpha) * current_avg_pm25)
                    new_avg_pm10 = (alpha * pm10) + ((1 - alpha) * current_avg_pm10)
                
                await crud.update_pm_zone_stats(zone["_id"], new_avg_pm25, new_avg_pm10)

    except Exception as e:
        print(f"Error processing PM Zones: {e}")

def on_connect(client, userdata, flags, rc):
    """Callback for when the client connects to the broker."""
    if rc == 0:
        print("Connected to MQTT Broker!")
        client.subscribe(constants.TOPIC_ESP32_GPS)
        client.subscribe(constants.TOPIC_ESP32_GPS_FAST)
        client.subscribe(constants.TOPIC_IR_TRIGGER)
        client.subscribe(constants.TOPIC_BUS_DOOR_COUNT)
        client.subscribe(constants.TOPIC_BUS_STATUS)
        print(f"Subscribed to basic topics.")
    else:
        print(f"Failed to connect, return code {rc}\n")

def log_future_done(future):
    """Callback for run_coroutine_threadsafe to log errors."""
    try:
        future.result()
    except Exception as e:
        print(f"MQTT Background Task Error: {e}")

def on_message(client, userdata, msg):
    """Callback for when a message is received from a subscribed topic."""
    # Process the incoming data
    try:
        payload_str = msg.payload.decode()
        
        # 1. Handle Door Count (Special case)
        if msg.topic == constants.TOPIC_BUS_DOOR_COUNT:
            try:
                data = json.loads(payload_str)
                bus_id = (data.get('bus_id') or '').strip() or None
                bus_mac = (data.get('bus_mac') or '').strip()
                bus_name = (data.get('bus_name') or '').strip() or None
                current_passengers = data.get('count', 0)

                resolved_bus = None
                should_reset_at_terminal_stop = True
                no_gps_mode_enabled = False
                assigned_bus_mac = None
                if state.state.main_loop:
                    async def resolve_bus():
                        developer_settings = await crud.get_developer_settings()
                        bus, _, _, _ = await resolve_effective_bus_identity(
                            bus_mac=bus_mac,
                            bus_name=bus_name,
                            bus_id=bus_id,
                            no_gps_mode_enabled=bool(
                                developer_settings["no_gps_mode_enabled"]
                            ),
                            assigned_bus_mac=developer_settings.get("assigned_bus_mac"),
                        )
                        return bus

                    resolved_bus = asyncio.run_coroutine_threadsafe(
                        resolve_bus(),
                        state.state.main_loop,
                    ).result(timeout=1)
                    should_reset_at_terminal_stop = asyncio.run_coroutine_threadsafe(
                        crud.get_reset_passenger_count_at_terminal_stop(),
                        state.state.main_loop,
                    ).result(timeout=1)
                    no_gps_mode_enabled = asyncio.run_coroutine_threadsafe(
                        crud.get_no_gps_mode_enabled(),
                        state.state.main_loop,
                    ).result(timeout=1)
                    assigned_bus_mac = asyncio.run_coroutine_threadsafe(
                        crud.get_developer_settings(),
                        state.state.main_loop,
                    ).result(timeout=1).get("assigned_bus_mac")

                resolved_mac = resolved_bus.get("mac_address") if resolved_bus else (
                    assigned_bus_mac or bus_mac
                )
                if not resolved_mac:
                    logger.warning(
                        "Skipping door count message without a resolvable bus identity: bus_id=%s bus_name=%s",
                        bus_id,
                        bus_name,
                    )
                    return
                payload_lat = data.get("lat")
                payload_lon = data.get("lon")
                payload_lat, payload_lon, has_payload_location = _coerce_location_override(
                    no_gps_mode_enabled=no_gps_mode_enabled,
                    lat=payload_lat,
                    lon=payload_lon,
                )
                resolved_lat = payload_lat
                resolved_lon = payload_lon
                if resolved_lat is None and resolved_bus is not None:
                    resolved_lat = resolved_bus.get("current_lat")
                if resolved_lon is None and resolved_bus is not None:
                    resolved_lon = resolved_bus.get("current_lon")
                current_passengers = (
                    normalize_passenger_count(current_passengers, payload_lat, payload_lon)
                    if has_payload_location and should_reset_at_terminal_stop
                    else clamp_passenger_count(current_passengers)
                )
                
                # Store in SQLite history
                from .analytics import record_passenger_count
                record_passenger_count(
                    resolved_mac,
                    current_passengers,
                    resolved_lat if has_payload_location else 0.0,
                    resolved_lon if has_payload_location else 0.0,
                    apply_parking_reset=(
                        has_payload_location and should_reset_at_terminal_stop
                    ),
                )
                
                # Update global count in shared state
                with state.state.passenger_lock:
                    state.state.current_passengers = current_passengers
                
                print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Door Event - Bus {resolved_mac}: {current_passengers} pax")
                
                # Sync with Seats in MongoDB
                if state.state.main_loop:
                    async def sync_seats(mac):
                        seats_available = seats_available_for_count(current_passengers)
                        updated_bus = await crud.update_bus_location(
                            mac_address=mac,
                            lat=payload_lat if has_payload_location else None,
                            lon=payload_lon if has_payload_location else None,
                            bus_id=bus_id,
                            seats_available=seats_available, pm2_5=None, pm10=None,
                            temp=None, hum=None,
                            person_count=current_passengers,
                            count_source="door",
                            apply_parking_reset=(
                                has_payload_location and should_reset_at_terminal_stop
                            ),
                            use_default_location_if_missing=has_payload_location,
                        )
                        # Broadcast to App
                        if updated_bus:
                             app_payload = bus_document_to_app_payload(updated_bus)
                             if not has_payload_location:
                                 app_payload["lat"] = None
                                 app_payload["lon"] = None
                             app_payload["count_source"] = "door"
                             print(f"📡 Broadcasting to app: passengers={current_passengers}, seats={seats_available}")
                             client.publish(constants.TOPIC_APP_LOCATION, json.dumps(app_payload))
                    
                    fut = asyncio.run_coroutine_threadsafe(sync_seats(resolved_mac), state.state.main_loop)
                    fut.add_done_callback(log_future_done)
                
                # Compatibility with testing screen
                detection_payload = {
                    "entering": 0, "exiting": 0, "total_unique_persons": state.state.current_passengers,
                    "boxes": [], "processing_time_ms": 0
                }
                client.publish(constants.TOPIC_PERSON_DETECTION, json.dumps(detection_payload))
                
            except Exception as e:
                print(f"Error processing door count: {e}")
            return

        # 2. Handle GPS/Status
        payload = json.loads(payload_str)
        
        bus_id = (payload.get("bus_id") or "").strip() or None
        bus_mac = (payload.get("bus_mac") or "").strip()
        if not bus_mac:
            logger.warning(
                "Skipping MQTT message without bus_mac on topic=%s payload=%s",
                msg.topic,
                payload,
            )
            return
        
        print(f"📥 Device MSG: {bus_mac} | Topic: {msg.topic}")

        bus_name = payload.get("bus_name", "").strip() or None
        lat = payload.get("lat")
        lon = payload.get("lon")
        has_payload_location = lat is not None and lon is not None
        is_status_message = _is_status_topic(msg.topic)
        pm2_5 = _optional_float(payload, "pm2_5")
        pm10 = _optional_float(payload, "pm10")
        temp = _optional_float(payload, "temp")
        hum = _optional_float(payload, "hum")
        seats_available = int(payload.get("seats_available", 0))
        should_reset_at_terminal_stop = True
        no_gps_mode_enabled = False
        assigned_bus_mac = None
        if state.state.main_loop:
            try:
                developer_settings = asyncio.run_coroutine_threadsafe(
                    crud.get_developer_settings(),
                    state.state.main_loop,
                ).result(timeout=1)
                should_reset_at_terminal_stop = asyncio.run_coroutine_threadsafe(
                    crud.get_reset_passenger_count_at_terminal_stop(),
                    state.state.main_loop,
                ).result(timeout=1)
                no_gps_mode_enabled = bool(
                    developer_settings.get("no_gps_mode_enabled")
                )
                assigned_bus_mac = developer_settings.get("assigned_bus_mac")
            except Exception:
                should_reset_at_terminal_stop = True
                no_gps_mode_enabled = False
                assigned_bus_mac = None
        lat, lon, has_payload_location = _coerce_location_override(
            no_gps_mode_enabled=no_gps_mode_enabled,
            lat=lat,
            lon=lon,
        )
        missing_sensor_fields = [
            key
            for key in ("pm2_5", "pm10", "temp", "hum")
            if key not in payload or payload.get(key) is None
        ]
        if missing_sensor_fields:
            logger.info(
                "MQTT %s bus=%s missing sensor fields=%s; previous stored values will be preserved",
                msg.topic,
                bus_mac,
                ",".join(missing_sensor_fields),
            )
        else:
            logger.info(
                "MQTT %s bus=%s sensors pm2_5=%s pm10=%s temp=%s hum=%s",
                msg.topic,
                bus_mac,
                pm2_5,
                pm10,
                temp,
                hum,
            )
        
        person_count = payload.get("person_count")
        if person_count is None:
            person_count = payload.get("count")
        if person_count is not None:
            person_count = (
                normalize_passenger_count(person_count, lat, lon)
                if has_payload_location and should_reset_at_terminal_stop
                else clamp_passenger_count(person_count)
            )
            if is_status_message and not has_payload_location and person_count == 0:
                person_count = None
                seats_available = None
            if "seats_available" not in payload or (
                has_payload_location
                and should_reset_at_terminal_stop
                and is_at_default_parking(lat, lon)
            ):
                if person_count is not None:
                    seats_available = seats_available_for_count(person_count)
        elif (
            has_payload_location
            and should_reset_at_terminal_stop
            and is_at_default_parking(lat, lon)
        ):
            person_count = 0
            seats_available = seats_available_for_count(0)
            
        rssi = payload.get("rssi")
        if rssi is not None:
            rssi = int(rssi)

        if state.state.main_loop:
            async def process_update_async():
                resolved_bus, resolved_bus_id, resolved_mac, resolved_name = await resolve_effective_bus_identity(
                    bus_mac=bus_mac,
                    bus_name=bus_name,
                    bus_id=bus_id,
                    no_gps_mode_enabled=no_gps_mode_enabled,
                    assigned_bus_mac=assigned_bus_mac,
                )
                previous_bus = resolved_bus
                # Update DB
                updated_bus = await crud.update_bus_location(
                    mac_address=resolved_mac,
                    bus_id=resolved_bus_id or bus_id,
                    bus_name=resolved_name,
                    lat=lat,
                    lon=lon,
                    seats_available=seats_available, pm2_5=pm2_5, pm10=pm10, temp=temp, hum=hum,
                    person_count=person_count,
                    rssi=rssi,
                    count_source="status" if is_status_message else "telemetry",
                    apply_parking_reset=(
                        has_payload_location and should_reset_at_terminal_stop
                    ),
                    use_default_location_if_missing=person_count is None and not is_status_message,
                )
                current_at_parking = (
                    is_at_default_parking(
                        updated_bus.get("current_lat"),
                        updated_bus.get("current_lon"),
                    )
                    if updated_bus
                    else False
                )
                if (
                    updated_bus
                    and current_at_parking
                    and should_reset_at_terminal_stop
                ):
                    if int((previous_bus or {}).get("person_count", 0) or 0) > 0:
                        from .analytics import record_passenger_count
                        record_passenger_count(
                            resolved_mac,
                            0,
                            updated_bus.get("current_lat") or 0.0,
                            updated_bus.get("current_lon") or 0.0,
                        )
                    publish_reset_count_command(
                        bus_mac=resolved_mac,
                        bus_id=resolved_bus_id or bus_id,
                    )
                # Create history entry
                if lat is not None and lon is not None:
                    hw_loc = models.HardwareLocation(
                        lat=lat, lon=lon, pm2_5=pm2_5 or 0.0, pm10=pm10 or 0.0, 
                        rssi=rssi,
                        timestamp=datetime.now(timezone.utc), bus_mac=resolved_mac
                    )
                    await crud.create_hardware_location(hw_loc)
                
                # Check zones
                if lat is not None and lon is not None:
                    await check_pm_zones_logic(
                        resolved_mac,
                        lat,
                        lon,
                        pm2_5 or 0.0,
                        pm10 or 0.0,
                        temp or 0.0,
                        hum or 0.0,
                    )

                if updated_bus and msg.topic != constants.TOPIC_ESP32_GPS_FAST:
                    app_payload = bus_document_to_app_payload(updated_bus)
                    app_payload["count_source"] = (
                        "status" if is_status_message else "telemetry"
                    )
                    logger.debug(
                        "Publishing app payload bus=%s pm2_5=%s pm10=%s temp=%s hum=%s lat=%s lon=%s",
                        resolved_mac,
                        app_payload.get("pm2_5"),
                        app_payload.get("pm10"),
                        app_payload.get("temp"),
                        app_payload.get("hum"),
                        app_payload.get("lat"),
                        app_payload.get("lon"),
                    )
                    client.publish(constants.TOPIC_APP_LOCATION, json.dumps(app_payload))

                return resolved_bus_id, resolved_mac, resolved_name, updated_bus

            fut = asyncio.run_coroutine_threadsafe(process_update_async(), state.state.main_loop)
            fut.add_done_callback(log_future_done)

    except Exception as e:
        print(f"Error in on_message (topic={msg.topic}): {e}")
        print(f"Payload was: {msg.payload.decode() if msg.payload else 'EMPTY'}")

# Configure Client
client = mqtt.Client(client_id="sut-server", clean_session=True)
client.on_connect = on_connect
client.on_message = on_message
if settings.MQTT_USERNAME:
    client.username_pw_set(
        username=settings.MQTT_USERNAME,
        password=settings.MQTT_PASSWORD,
    )

def connect_mqtt():
    try:
        client.connect(settings.MQTT_BROKER_HOST, settings.MQTT_BROKER_PORT, 60)
    except Exception as e:
        print(f"Error connecting to MQTT: {e}")

def start_mqtt_loop():
    client.loop_start()

def stop_mqtt_loop():
    client.loop_stop()
