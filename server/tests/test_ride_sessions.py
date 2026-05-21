import asyncio
import importlib
import os
import sqlite3
import sys
import tempfile
import types
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock

config_stub = types.ModuleType("core.config")
config_stub.settings = types.SimpleNamespace(
    DB_FILE="bus_passengers.db",
    MONGODB_URL="mongodb://localhost:27017/test",
    DEFAULT_BUS_LAT=14.878001729445229,
    DEFAULT_BUS_LON=102.02142930035654,
)
sys.modules["core.config"] = config_stub
crud_stub = types.ModuleType("app.crud")
crud_stub.get_bus_by_mac = AsyncMock()
sys.modules["app.crud"] = crud_stub

ride_sessions = importlib.import_module("app.ride_sessions")
settings = config_stub.settings


class StartRideSessionTests(unittest.TestCase):
    def setUp(self) -> None:
        self._temp_dir = tempfile.TemporaryDirectory(ignore_cleanup_errors=True)
        self._previous_db_file = settings.DB_FILE
        settings.DB_FILE = os.path.join(self._temp_dir.name, "test_ride_sessions.db")
        self._create_schema()

    def tearDown(self) -> None:
        settings.DB_FILE = self._previous_db_file
        self._temp_dir.cleanup()

    def _create_schema(self) -> None:
        with sqlite3.connect(settings.DB_FILE) as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS ride_sessions (
                    session_id TEXT PRIMARY KEY,
                    device_id TEXT NOT NULL,
                    bus_mac TEXT NOT NULL,
                    status TEXT NOT NULL,
                    started_at DATETIME NOT NULL,
                    expires_at DATETIME NOT NULL,
                    last_verified_at DATETIME NOT NULL,
                    last_verified_lat REAL NOT NULL,
                    last_verified_lon REAL NOT NULL,
                    ring_count INTEGER NOT NULL DEFAULT 0,
                    last_ring_at DATETIME,
                    ended_at DATETIME
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS passenger_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    bus_mac TEXT NOT NULL,
                    count INTEGER NOT NULL,
                    timestamp TEXT NOT NULL,
                    lat REAL,
                    lon REAL
                )
                """
            )
            conn.commit()

    def _insert_passenger_history(
        self,
        bus_mac: str,
        count: int,
        *,
        age_seconds: int = 0,
    ) -> None:
        timestamp = (
            datetime.now(timezone.utc) - timedelta(seconds=age_seconds)
        ).isoformat()
        with sqlite3.connect(settings.DB_FILE) as conn:
            conn.execute(
                """
                INSERT INTO passenger_history (bus_mac, count, timestamp, lat, lon)
                VALUES (?, ?, ?, ?, ?)
                """,
                (bus_mac, count, timestamp, 0.0, 0.0),
            )
            conn.commit()

    def test_start_ride_allows_effective_distance_within_mobile_threshold(self) -> None:
        bus = {
            "mac_address": "AA:BB:CC:DD:EE:FF",
            "current_lat": 14.8820,
            "current_lon": 102.0207,
            "person_count": 14,
        }
        user_lat = 14.88218
        user_lon = 102.0207
        self.assertLessEqual(
            ride_sessions._distance_m(
                user_lat,
                user_lon,
                bus["current_lat"],
                bus["current_lon"],
            ),
            ride_sessions.RIDE_START_MAX_DISTANCE_M,
        )

        ride_sessions.crud.get_bus_by_mac = AsyncMock(return_value=bus)
        session = asyncio.run(
            ride_sessions.start_ride_session(
                device_id="device-123",
                bus_mac=bus["mac_address"],
                user_lat=user_lat,
                user_lon=user_lon,
                user_accuracy_m=0,
            )
        )

        self.assertEqual(session.bus_mac, bus["mac_address"])
        self.assertEqual(session.status, "active")

    def test_start_ride_uses_recent_passenger_history_when_bus_document_is_stale(self) -> None:
        bus = {
            "mac_address": "AA:BB:CC:DD:EE:FF",
            "current_lat": 14.8820,
            "current_lon": 102.0207,
            "person_count": 0,
        }
        self._insert_passenger_history(bus["mac_address"], 17)

        ride_sessions.crud.get_bus_by_mac = AsyncMock(return_value=bus)
        session = asyncio.run(
            ride_sessions.start_ride_session(
                device_id="device-123",
                bus_mac=bus["mac_address"],
                user_lat=14.8820,
                user_lon=102.0207,
                user_accuracy_m=0,
            )
        )

        self.assertEqual(session.bus_mac, bus["mac_address"])
        self.assertEqual(session.status, "active")

    def test_start_ride_rejects_stale_passenger_history_when_bus_is_empty(self) -> None:
        bus = {
            "mac_address": "AA:BB:CC:DD:EE:FF",
            "current_lat": 14.8820,
            "current_lon": 102.0207,
            "person_count": 0,
        }
        self._insert_passenger_history(
            bus["mac_address"],
            17,
            age_seconds=ride_sessions.RECENT_PASSENGER_COUNT_MAX_AGE_SECONDS + 1,
        )

        ride_sessions.crud.get_bus_by_mac = AsyncMock(return_value=bus)
        with self.assertRaises(ride_sessions.RideSessionForbiddenError):
            asyncio.run(
                ride_sessions.start_ride_session(
                    device_id="device-123",
                    bus_mac=bus["mac_address"],
                    user_lat=14.8820,
                    user_lon=102.0207,
                    user_accuracy_m=0,
                )
            )

    def test_start_ride_uses_recent_empty_history_over_stale_bus_document(self) -> None:
        bus = {
            "mac_address": "AA:BB:CC:DD:EE:FF",
            "current_lat": 14.8820,
            "current_lon": 102.0207,
            "person_count": 17,
        }
        self._insert_passenger_history(bus["mac_address"], 0)

        ride_sessions.crud.get_bus_by_mac = AsyncMock(return_value=bus)
        with self.assertRaises(ride_sessions.RideSessionForbiddenError):
            asyncio.run(
                ride_sessions.start_ride_session(
                    device_id="device-123",
                    bus_mac=bus["mac_address"],
                    user_lat=14.8820,
                    user_lon=102.0207,
                    user_accuracy_m=0,
                )
            )


if __name__ == "__main__":
    unittest.main()
