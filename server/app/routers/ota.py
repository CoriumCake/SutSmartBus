from fastapi import APIRouter, HTTPException, Request
from app import schemas, constants
from core import config
from app.mqtt import client as mqtt_client
import json
import socket

router = APIRouter(prefix="/api", tags=["OTA"])

def get_lan_ip():
    """Detect local IP address of the server."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # doesn't even have to be reachable
        s.connect(('10.255.255.255', 1))
        IP = s.getsockname()[0]
    except Exception:
        IP = config.settings.OTA_FALLBACK_IP
    finally:
        s.close()
    return IP


def get_ota_base_url():
    public_base = config.settings.OTA_PUBLIC_BASE_URL
    if public_base:
        return public_base.rstrip("/")

    server_ip = get_lan_ip()
    return f"http://{server_ip}:8000"

@router.post("/trigger-ota", response_model=schemas.FirmwareUpdateResponse)
async def trigger_ota(
    request: Request,
    type: str = "esp32_cam",
    target_mac: str = "ALL",
    version: str = "1.0.0",
):
    """
    Triggers OTA (Over-The-Air) update for field devices.
    - type: 'esp32_cam' or 'pm'
    - target_mac: Specific MAC address or 'ALL'
    """
    topic = constants.TOPIC_OTA_ESP32_CAM if type == "esp32_cam" else constants.TOPIC_OTA_PM
    
    ota_base_url = get_ota_base_url()
    # Construct OTA URL. The devices expect a bin file at this location.
    # Note: ensure actual bin files are hosted at these paths!
    filename = "SUT_BUS_CAM.ino.bin" if type == "esp32_cam" else "SUT_BUS_PM.ino.bin"
    ota_url = f"{ota_base_url}/static/ota/{filename}"
    
    payload = {
        "command": "update",
        "url": ota_url,
        "mac": target_mac,
        "type": type,
        "version": version,
    }
    
    try:
        mqtt_client.publish(topic, json.dumps(payload))
        return {
            "success": True, 
            "message": f"OTA update triggered for {type} ({target_mac})",
            "target_mac": target_mac,
            "ota_url": ota_url,
            "version": version,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to trigger OTA: {str(e)}")
