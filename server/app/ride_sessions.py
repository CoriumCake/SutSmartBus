import secrets
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Optional

from app import crud
from app.passenger_rules import normalize_passenger_count
from core.config import settings

# Keep ride start validation aligned with the Flutter boarding gate in
# `MapScreen` so riders do not see an enabled CTA that the backend rejects.
RIDE_START_MAX_DISTANCE_M = 25.0
RIDE_RING_MAX_DISTANCE_M = 18.0
RIDE_GPS_ACCURACY_COMPENSATION_CAP_M = 15.0
RIDE_SESSION_DURATION = timedelta(minutes=30)
RIDE_RING_COOLDOWN = timedelta(seconds=30)
RIDE_MIN_ACTIVE_BEFORE_RING = timedelta(seconds=15)
RIDE_MAX_RINGS_PER_SESSION = 3
RECENT_PASSENGER_COUNT_MAX_AGE_SECONDS = 120


class RideSessionError(Exception):
    pass


class RideSessionNotFoundError(RideSessionError):
    pass


class RideSessionForbiddenError(RideSessionError):
    pass


class RideSessionRateLimitError(RideSessionError):
    pass


@dataclass
class RideSession:
    session_id: str
    device_id: str
    bus_mac: str
    status: str
    started_at: str
    expires_at: str
    last_verified_at: str
    last_verified_lat: float
    last_verified_lon: float
    ring_count: int
    last_ring_at: Optional[str]
    ended_at: Optional[str]

    def to_dict(self) -> dict:
        return {
            "session_id": self.session_id,
            "device_id": self.device_id,
            "bus_mac": self.bus_mac,
            "status": self.status,
            "started_at": self.started_at,
            "expires_at": self.expires_at,
            "last_verified_at": self.last_verified_at,
            "last_verified_lat": self.last_verified_lat,
            "last_verified_lon": self.last_verified_lon,
            "ring_count": self.ring_count,
            "last_ring_at": self.last_ring_at,
            "ended_at": self.ended_at,
        }


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(settings.DB_FILE)
    conn.row_factory = sqlite3.Row
    return conn


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _parse_utc(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    normalized = value if value.endswith("Z") else value.replace("Z", "+00:00")
    return datetime.fromisoformat(normalized)


def _distance_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    from math import atan2, cos, radians, sin, sqrt

    earth_radius_m = 6371000.0
    d_lat = radians(lat2 - lat1)
    d_lon = radians(lon2 - lon1)
    a = (
        sin(d_lat / 2) ** 2
        + cos(radians(lat1)) * cos(radians(lat2)) * sin(d_lon / 2) ** 2
    )
    c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return earth_radius_m * c


def _effective_distance_m(distance_m: float, user_accuracy_m: Optional[float]) -> float:
    if user_accuracy_m is None:
        return distance_m
    return max(
        0.0,
        distance_m - min(max(user_accuracy_m, 0.0), RIDE_GPS_ACCURACY_COMPENSATION_CAP_M),
    )


def _session_from_row(row: sqlite3.Row) -> RideSession:
    return RideSession(
        session_id=row["session_id"],
        device_id=row["device_id"],
        bus_mac=row["bus_mac"],
        status=row["status"],
        started_at=row["started_at"],
        expires_at=row["expires_at"],
        last_verified_at=row["last_verified_at"],
        last_verified_lat=row["last_verified_lat"],
        last_verified_lon=row["last_verified_lon"],
        ring_count=row["ring_count"],
        last_ring_at=row["last_ring_at"],
        ended_at=row["ended_at"],
    )


async def _get_bus_or_raise(bus_mac: str) -> dict:
    bus = await crud.get_bus_by_mac(bus_mac)
    if not bus:
        raise RideSessionNotFoundError("Bus not found")
    if bus.get("current_lat") is None or bus.get("current_lon") is None:
        raise RideSessionForbiddenError("Bus location unavailable")
    return bus


def _latest_passenger_count(
    bus_mac: str,
    max_age_seconds: Optional[int] = None,
) -> Optional[int]:
    if not bus_mac:
        return None

    try:
        with sqlite3.connect(settings.DB_FILE) as conn:
            conn.row_factory = sqlite3.Row
            row = conn.execute(
                """
                SELECT count, timestamp, lat, lon
                FROM passenger_history
                WHERE bus_mac = ?
                ORDER BY id DESC
                LIMIT 1
                """,
                (bus_mac,),
            ).fetchone()
    except sqlite3.Error:
        return None

    if row is None:
        return None

    if max_age_seconds is not None:
        try:
            timestamp = datetime.fromisoformat(
                str(row["timestamp"]).replace("Z", "+00:00"),
            )
            if timestamp.tzinfo is None:
                timestamp = timestamp.replace(tzinfo=timezone.utc)
            age = datetime.now(timezone.utc) - timestamp.astimezone(timezone.utc)
            if age > timedelta(seconds=max_age_seconds):
                return None
        except (TypeError, ValueError):
            return None

    return normalize_passenger_count(
        row["count"],
        row["lat"] if "lat" in row.keys() else None,
        row["lon"] if "lon" in row.keys() else None,
    )


def _recent_passenger_history_count(bus: dict, requested_bus_mac: str) -> Optional[int]:
    candidates = [
        bus.get("mac_address"),
        bus.get("bus_mac"),
        bus.get("bus_id"),
        requested_bus_mac,
        bus.get("bus_name"),
    ]
    seen = set()
    latest_counts = []

    for candidate in candidates:
        if not candidate:
            continue
        key = str(candidate).strip()
        if not key or key in seen:
            continue
        seen.add(key)

        count = _latest_passenger_count(
            key,
            max_age_seconds=RECENT_PASSENGER_COUNT_MAX_AGE_SECONDS,
        )
        if count is None:
            continue
        if count > 0:
            return count
        latest_counts.append(count)

    return latest_counts[0] if latest_counts else None


def _effective_passenger_count(bus: dict, requested_bus_mac: str) -> int:
    stored_count = int(bus.get("person_count") or 0)
    history_count = _recent_passenger_history_count(bus, requested_bus_mac)
    if history_count is not None:
        return history_count

    return stored_count


async def start_ride_session(
    *,
    device_id: str,
    bus_mac: str,
    user_lat: float,
    user_lon: float,
    user_accuracy_m: Optional[float] = None,
) -> RideSession:
    bus = await _get_bus_or_raise(bus_mac)
    if _effective_passenger_count(bus, bus_mac) <= 0:
        raise RideSessionForbiddenError("Cannot start a ride while the bus is empty")
    distance = _distance_m(
        user_lat,
        user_lon,
        float(bus["current_lat"]),
        float(bus["current_lon"]),
    )
    effective_distance = _effective_distance_m(distance, user_accuracy_m)
    if effective_distance > RIDE_START_MAX_DISTANCE_M:
        raise RideSessionForbiddenError("You must be near the bus to start a ride")

    now = _utc_now()
    session_id = secrets.token_urlsafe(24)
    expires_at = now + RIDE_SESSION_DURATION

    with _connect() as conn:
        conn.execute(
            """
            UPDATE ride_sessions
            SET status = 'ended', ended_at = ?
            WHERE device_id = ? AND status = 'active'
            """,
            (now.isoformat(), device_id),
        )
        conn.execute(
            """
            INSERT INTO ride_sessions (
                session_id, device_id, bus_mac, status,
                started_at, expires_at, last_verified_at,
                last_verified_lat, last_verified_lon,
                ring_count, last_ring_at, ended_at
            ) VALUES (?, ?, ?, 'active', ?, ?, ?, ?, ?, 0, NULL, NULL)
            """,
            (
                session_id,
                device_id,
                bus_mac,
                now.isoformat(),
                expires_at.isoformat(),
                now.isoformat(),
                user_lat,
                user_lon,
            ),
        )
        row = conn.execute(
            "SELECT * FROM ride_sessions WHERE session_id = ?",
            (session_id,),
        ).fetchone()
    return _session_from_row(row)


def get_ride_session(*, session_id: str, device_id: str) -> Optional[RideSession]:
    with _connect() as conn:
        row = conn.execute(
            """
            SELECT * FROM ride_sessions
            WHERE session_id = ? AND device_id = ?
            """,
            (session_id, device_id),
        ).fetchone()
    if row is None:
        return None
    return _session_from_row(row)


def get_active_ride_session(*, session_id: str, device_id: str) -> Optional[RideSession]:
    session = get_ride_session(session_id=session_id, device_id=device_id)
    if session is None:
        return None
    expires_at = _parse_utc(session.expires_at)
    if session.status != "active" or expires_at is None or expires_at <= _utc_now():
        return None
    return session


def end_ride_session(*, session_id: str, device_id: str) -> bool:
    with _connect() as conn:
        result = conn.execute(
            """
            UPDATE ride_sessions
            SET status = 'ended', ended_at = ?
            WHERE session_id = ? AND device_id = ? AND status = 'active'
            """,
            (_utc_now().isoformat(), session_id, device_id),
        )
    return result.rowcount > 0


async def verify_session_for_ring(
    *,
    session_id: str,
    device_id: str,
    bus_mac: str,
    user_lat: float,
    user_lon: float,
    user_accuracy_m: Optional[float] = None,
) -> RideSession:
    session = get_active_ride_session(session_id=session_id, device_id=device_id)
    if session is None:
        raise RideSessionForbiddenError("No active ride session")
    if session.bus_mac != bus_mac:
        raise RideSessionForbiddenError("Ride session does not match this bus")

    bus = await _get_bus_or_raise(bus_mac)
    distance = _distance_m(
        user_lat,
        user_lon,
        float(bus["current_lat"]),
        float(bus["current_lon"]),
    )
    effective_distance = _effective_distance_m(distance, user_accuracy_m)
    if effective_distance > RIDE_RING_MAX_DISTANCE_M:
        raise RideSessionForbiddenError("You must stay near the bus to ring")

    now = _utc_now()
    started_at = _parse_utc(session.started_at)
    last_ring_at = _parse_utc(session.last_ring_at)
    if started_at is None or now - started_at < RIDE_MIN_ACTIVE_BEFORE_RING:
        raise RideSessionForbiddenError("Please wait briefly after boarding before ringing")
    if last_ring_at is not None and now - last_ring_at < RIDE_RING_COOLDOWN:
        raise RideSessionRateLimitError("Bell already sent recently")
    if session.ring_count >= RIDE_MAX_RINGS_PER_SESSION:
        raise RideSessionRateLimitError("Bell limit reached for this ride")

    with _connect() as conn:
        conn.execute(
            """
            UPDATE ride_sessions
            SET last_verified_at = ?, last_verified_lat = ?, last_verified_lon = ?,
                last_ring_at = ?, ring_count = ring_count + 1
            WHERE session_id = ? AND device_id = ?
            """,
            (
                now.isoformat(),
                user_lat,
                user_lon,
                now.isoformat(),
                session_id,
                device_id,
            ),
        )
        row = conn.execute(
            "SELECT * FROM ride_sessions WHERE session_id = ? AND device_id = ?",
            (session_id, device_id),
        ).fetchone()
    return _session_from_row(row)
