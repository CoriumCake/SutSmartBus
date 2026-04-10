import asyncio
from motor.motor_asyncio import AsyncIOMotorClient
from datetime import datetime, timezone
import sys

MONGODB_URL = "mongodb://localhost:27017/sut_smart_bus"

async def register_bus(mac_address, bus_name):
    print(f"Connecting to MongoDB...")
    client = AsyncIOMotorClient(MONGODB_URL)
    db = client.get_database("sut_smart_bus")
    bus_collection = db.get_collection("buses")

    bus_data = {
        "mac_address": mac_address,
        "bus_name": bus_name,
        "seats_available": 33,
        "person_count": 0,
        "pm2_5": 0.0,
        "pm10": 0.0,
        "temp": 0.0,
        "hum": 0.0,
        "last_updated": datetime.now(timezone.utc)
    }

    print(f"Registering bus: {bus_name} ({mac_address})...")
    result = await bus_collection.update_one(
        {"mac_address": mac_address},
        {"$set": bus_data},
        upsert=True
    )
    print(f"✅ Successfully registered/updated bus: {bus_name}")
    client.close()

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 register_bus.py <MAC_ADDRESS> <BUS_NAME>")
        sys.exit(1)
    asyncio.run(register_bus(sys.argv[1], sys.argv[2]))
