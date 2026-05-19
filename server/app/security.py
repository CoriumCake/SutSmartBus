import hmac
from collections import defaultdict, deque
from dataclasses import dataclass
from hashlib import sha256
from threading import Lock
from time import monotonic

from fastapi import HTTPException


def sign_ring_command(*, secret: str, bus_mac: str, timestamp: int) -> str:
    payload = f"ring|{bus_mac}|{timestamp}"
    return hmac.new(secret.encode("utf-8"), payload.encode("utf-8"), sha256).hexdigest()


@dataclass(frozen=True)
class LimitRule:
    window_seconds: int
    max_requests: int
    message: str


class InMemoryRateLimiter:
    def __init__(self) -> None:
        self._events: dict[str, deque[float]] = defaultdict(deque)
        self._lock = Lock()

    def enforce(self, *, scope: str, rule: LimitRule) -> None:
        now = monotonic()
        cutoff = now - rule.window_seconds
        with self._lock:
            queue = self._events[scope]
            while queue and queue[0] <= cutoff:
                queue.popleft()
            if len(queue) >= rule.max_requests:
                raise HTTPException(status_code=429, detail=rule.message)
            queue.append(now)
