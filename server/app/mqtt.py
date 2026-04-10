import paho.mqtt.client as mqtt
import os
import json
import asyncio
import time
import sqlite3
from datetime import datetime, timezone
from . import crud, models, constants, state
from core.config import settings

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
                bus_mac = data.get('bus_mac', constants.BUS_MAC_MOCK)
                current_passengers = data.get('count', 0)
                
                # Store in SQLite history
                from .analytics import record_passenger_count
                record_passenger_count(bus_mac, current_passengers)
                
                # Update global count in shared state
                with state.state.passenger_lock:
                    state.state.current_passengers = current_passengers
                
                print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Door Event - Bus {bus_mac}: {current_passengers} pax")
                
                # Sync with Seats in MongoDB
                if state.state.main_loop:
                    async def sync_seats(mac):
                        seats_available = max(0, constants.TOTAL_SEATS - current_passengers)
                        await crud.update_bus_location(
                            mac_address=mac, lat=None, lon=None,
                            seats_available=seats_available, pm2_5=0, pm10=0,
                            person_count=current_passengers
                        )
                        # Broadcast to App
                        updated_bus = await crud.get_bus_by_mac(mac)
                        if updated_bus:
                             app_payload = updated_bus.dict()
                             print(f"📡 Broadcasting to app: passengers={current_passengers}, seats={seats_available}")
                             client.publish(constants.TOPIC_APP_LOCATION, json.dumps(app_payload))
                    
                    fut = asyncio.run_coroutine_threadsafe(sync_seats(bus_mac), state.state.main_loop)
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
        bus_mac = payload.get("bus_mac")
        if not bus_mac: return

        bus_name = payload.get("bus_name", "").strip() or None
        lat = payload.get("lat")
        lon = payload.get("lon")
        pm2_5 = float(payload.get("pm2_5", 0.0))
        pm10 = float(payload.get("pm10", 0.0))
        temp = float(payload.get("temp", 0.0))
        hum = float(payload.get("hum", 0.0))
        seats_available = int(payload.get("seats_available", 0))
        
        person_count = payload.get("person_count")
        if person_count is None:
            person_count = payload.get("count")
        if person_count is not None:
            person_count = int(person_count)
            
        rssi = payload.get("rssi")
        if rssi is not None:
            rssi = int(rssi)

        if state.state.main_loop:
            async def process_update_async():
                # Update DB
                await crud.update_bus_location(
                    mac_address=bus_mac, bus_name=bus_name, lat=lat, lon=lon,
                    seats_available=seats_available, pm2_5=pm2_5, pm10=pm10, temp=temp, hum=hum,
                    person_count=person_count, rssi=rssi
                )
                # Create history entry
                if lat is not None and lon is not None:
                    hw_loc = models.HardwareLocation(
                        lat=lat, lon=lon, pm2_5=pm2_5, pm10=pm10, 
                        timestamp=datetime.now(timezone.utc), bus_mac=bus_mac
                    )
                    await crud.create_hardware_location(hw_loc)
                
                # Check zones
                if lat is not None and lon is not None:
                    await check_pm_zones_logic(bus_mac, lat, lon, pm2_5, pm10, temp, hum)

            fut = asyncio.run_coroutine_threadsafe(process_update_async(), state.state.main_loop)
            fut.add_done_callback(log_future_done)
            
            # Broadcast to App if not fast GPS
            if msg.topic != constants.TOPIC_ESP32_GPS_FAST:
                app_payload = {
                    "bus_mac": bus_mac, "bus_name": bus_name, "lat": lat, "lon": lon,
                    "pm2_5": pm2_5, "pm10": pm10, "temp": temp, "hum": hum, 
                    "seats_available": seats_available
                }
                client.publish(constants.TOPIC_APP_LOCATION, json.dumps(app_payload))

    except Exception as e:
        print(f"Error in on_message: {e}")

# Configure Client
client = mqtt.Client(client_id="sut-server", clean_session=True)
client.on_connect = on_connect
client.on_message = on_message

def connect_mqtt():
    try:
        client.connect(settings.MQTT_BROKER_HOST, settings.MQTT_BROKER_PORT, 60)
    except Exception as e:
        print(f"Error connecting to MQTT: {e}")

def start_mqtt_loop():
    client.loop_start()

def stop_mqtt_loop():
    client.loop_stop()
