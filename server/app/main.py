import asyncio
import os
import time
import sqlite3
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app import crud, state
from app.routers import (
    buses, routes, ota, analytics, passengers, 
    system, admin, dashboard, feedback, pm_zones
)
from app.mqtt import client as mqtt_client, connect_mqtt, start_mqtt_loop, stop_mqtt_loop
from core.config import settings
from core.auth import APIKeyMiddleware

def init_sqlite():
    """Ensure the local passenger counting database exists."""
    with sqlite3.connect(settings.DB_FILE) as conn:
        conn.execute("CREATE TABLE IF NOT EXISTS counts (time TEXT, direction TEXT, total INTEGER)")
        conn.commit()
    print(f"[OK] SQLite Database Initialized ({settings.DB_FILE})")

def init_static():
    """Ensure static directories exist."""
    if not os.path.exists("static"):
        os.makedirs("static", exist_ok=True)
    if not os.path.exists("static/ota"):
        os.makedirs("static/ota", exist_ok=True)
    print("[OK] Static directories initialized.")

# Initialization
init_static()

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    print("🚀 SUT Smart Bus Server is starting...")
    init_sqlite()
    
    # Pass lifecycle loop to async tasks
    state.state.main_loop = asyncio.get_running_loop()
    
    # Initialize MongoDB Indexes
    try:
        await crud.bus_collection.create_index("mac_address", unique=True)
        await crud.blocked_mac_collection.create_index("mac_address", unique=True)
        print("[OK] Database indexes verified.")
    except Exception as e:
        print(f"[WARN] Index creation skipped: {e}")

    # Set up MQTT
    connect_mqtt()
    start_mqtt_loop()
        
    yield
    
    # Shutdown
    print("🛑 Shutting down services...")
    stop_mqtt_loop()
    mqtt_client.disconnect()

# --- App Instance ---
app = FastAPI(
    title="SUT Smart Bus API",
    version="1.2.0",
    description="Refactored backend for campus bus tracking and PM monitoring.",
    lifespan=lifespan
)

# --- Middlewares ---
app.add_middleware(APIKeyMiddleware)

cors_origins = settings.CORS_ORIGINS.split(",") if settings.CORS_ORIGINS != "*" else ["*"]
if "*" in cors_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=".*", # This acts like a wildcard but reflects the request origin
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
else:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

@app.middleware("http")
async def add_process_time_header(request: Request, call_next):
    start_time = time.time()
    response = await call_next(request)
    process_time = time.time() - start_time
    response.headers["X-Process-Time"] = f"{process_time:.4f}s"
    return response

# --- Router Inclusions ---
app.include_router(system.router)
app.include_router(dashboard.router)
app.include_router(buses.router)
app.include_router(routes.router)
app.include_router(ota.router)
app.include_router(analytics.router)
app.include_router(passengers.router)
app.include_router(feedback.router)
app.include_router(pm_zones.router)
app.include_router(admin.router)

# --- Static Assets ---
app.mount("/static", StaticFiles(directory="static"), name="static")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
