from fastapi import APIRouter, HTTPException, Depends, Header
from typing import List, Optional
from app import crud, models, constants, schemas
from core import config

router = APIRouter(prefix="/api/admin", tags=["Admin"])

# Very basic password-based authentication for admin operations
# In production, replace with JWT-based Auth
API_KEY_HEADER = "X-Admin-Key"

async def verify_admin(x_admin_key: Optional[str] = Header(None)):
    if not x_admin_key or x_admin_key != config.settings.ADMIN_PASSWORD:
         raise HTTPException(status_code=401, detail="Unauthorized - Invalid Admin Key")
    return True

@router.get("/blocked-macs", response_model=List[models.BlockedMAC])
async def list_blocked_macs(skip: int = 0, limit: int = 100, _=Depends(verify_admin)):
    """Retrieve all blocked MAC addresses."""
    # Note: depends(verify_admin) prevents unauthorized access
    return await crud.blocked_mac_collection.find().skip(skip).limit(limit).to_list(limit)

@router.post("/block-mac", response_model=models.BlockedMAC)
async def block_mac(mac: models.BlockedMAC, _=Depends(verify_admin)):
    """Temporarily block a MAC from being stored/processed."""
    return await crud.block_mac_address(mac)

@router.delete("/clear-locations/{mac_address}")
async def clear_device_locations(mac_address: str, _=Depends(verify_admin)):
    """DEBUG: Clear location history for a specific device."""
    count = await crud.delete_hardware_locations_by_mac(mac_address)
    return {"message": "Locations cleared", "count": count}

@router.post("/login")
async def admin_login(request: schemas.AdminPasswordRequest):
    """
    Simulated admin login.
    In a real app, this should return a JWT token.
    """
    if request.password != config.settings.ADMIN_PASSWORD:
        raise HTTPException(status_code=401, detail="Invalid password")
    return {"token": "ADMIN_SESSION_TOKEN_MOCK", "message": "Login successful"}

@router.post("/logout")
async def admin_logout(_=Depends(verify_admin)):
    """Ends the admin session."""
    return {"message": "Logged out successfully"}

@router.get("/config")
async def get_runtime_config(_=Depends(verify_admin)):
    """Returns the current application settings (sensitive)."""
    # Create copy to redact secret keys
    conf = config.settings.model_dump()
    if "ADMIN_PASSWORD" in conf: conf["ADMIN_PASSWORD"] = "******"
    if "MONGODB_URL" in conf: conf["MONGODB_URL"] = "mongodb://***:***@***"
    return conf
