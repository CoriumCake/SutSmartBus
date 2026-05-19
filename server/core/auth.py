"""
API Key Authentication Middleware

If API_SECRET_KEY is set in .env, protected API requests must include the
X-API-Key header. Public mobile app read endpoints stay available without a
client-shipped secret.
"""

from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from core.config import settings

# Paths that don't require authentication for every method.
PUBLIC_PATHS = {
    "/",
    "/health",
    "/openapi.json",
    "/api/admin/login",
}

PUBLIC_PREFIXES = (
    "/docs",
    "/redoc",
    "/dashboard",
    "/count",
    "/static",
)

# Read endpoints needed by the public mobile app.
PUBLIC_GET_PATHS = {
    "/api/environment",
    "/api/system-info",
    "/api/buses",
    "/api/routes",
    "/api/stops",
    "/api/bus-route-mapping",
    "/api/passengers/latest",
    "/api/pm_zones",
}

PUBLIC_GET_PREFIXES = (
    "/api/analytics/",
    "/api/route-file/",
    "/api/pm_zones/",
)

# User-initiated public app actions. These must validate/rate-limit at the
# route level because a mobile app secret cannot be kept private.
PUBLIC_METHOD_PATHS = {
    ("POST", "/api/feedback"),
    ("POST", "/api/rides/start"),
    ("POST", "/api/rides/end"),
    ("POST", "/api/rides/status"),
    ("POST", "/api/ring"),
}


def _is_public_request(method: str, path: str) -> bool:
    if method == "OPTIONS":
        return True

    method = "GET" if method == "HEAD" else method

    if path in PUBLIC_PATHS or any(path.startswith(prefix) for prefix in PUBLIC_PREFIXES):
        return True

    if method == "GET":
        return path in PUBLIC_GET_PATHS or any(
            path.startswith(prefix) for prefix in PUBLIC_GET_PREFIXES
        )

    return (method, path) in PUBLIC_METHOD_PATHS


class APIKeyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # Skip auth if no API key is configured
        if not settings.API_SECRET_KEY:
            return await call_next(request)
        
        # Allow explicit public app/review paths without auth.
        path = request.url.path
        if _is_public_request(request.method, path):
            return await call_next(request)
        
        # Check for API key in header
        api_key = request.headers.get("X-API-Key")
        
        # Fallback: Check query param (useful for OTA/legacy devices)
        if not api_key:
            api_key = request.query_params.get("api_key")
        
        if not api_key:
            return JSONResponse(
                status_code=401,
                content={"detail": "Missing API key. Include X-API-Key header."}
            )
        
        if api_key != settings.API_SECRET_KEY:
            return JSONResponse(
                status_code=403,
                content={"detail": "Invalid API key"}
            )
        
        return await call_next(request)
