import math

from core.config import settings
from . import constants

MAX_BUS_PASSENGERS = 40
PARKING_RESET_RADIUS_METERS = 35.0


def _to_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _distance_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    earth_radius_m = 6371000.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)

    a = (
        math.sin(dphi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return earth_radius_m * c


def is_at_default_parking(lat, lon) -> bool:
    normalized_lat = _to_float(lat)
    normalized_lon = _to_float(lon)
    if normalized_lat is None or normalized_lon is None:
        return False

    distance = _distance_meters(
        normalized_lat,
        normalized_lon,
        settings.DEFAULT_BUS_LAT,
        settings.DEFAULT_BUS_LON,
    )
    return distance <= PARKING_RESET_RADIUS_METERS


def clamp_passenger_count(count) -> int:
    normalized_count = _to_float(count)
    if normalized_count is None:
        return 0
    return max(0, min(MAX_BUS_PASSENGERS, int(normalized_count)))


def normalize_passenger_count(count, lat=None, lon=None) -> int:
    if is_at_default_parking(lat, lon):
        return 0
    return clamp_passenger_count(count)


def seats_available_for_count(count: int) -> int:
    return max(0, constants.TOTAL_SEATS - clamp_passenger_count(count))
