from fastapi import APIRouter, Response, HTTPException
from core import config
import os
import psutil
from datetime import datetime, timezone

router = APIRouter(prefix="", tags=["System"])

@router.get("/health")
async def health():
    """Health check endpoint for Docker/Kubernetes."""
    return {"status": "ok", "timestamp": str(datetime.now(timezone.utc))}

@router.get("/api/environment")
async def get_env():
    """Returns application environment name (redacted for security)."""
    env = os.getenv("APP_ENV", "development")
    return {"environment": env, "version": "1.2.0"}

@router.get("/api/system-info")
async def system_info():
    """Returns system status including memory and CPU usage."""
    try:
        cpu = psutil.cpu_percent()
        mem = psutil.virtual_memory().percent
        uptime = psutil.boot_time() # actually system uptime, but good for context
        return {
            "status": "online",
            "cpu_usage": f"{cpu}%",
            "memory_usage": f"{mem}%",
            "uptime": f"{int(datetime.now().timestamp() - uptime)}s",
            "database": "MongoDB (Async) + SQLite (Aggregations)"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
