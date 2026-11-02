# SPDX-License-Identifier: AGPL-3.0-or-later
"""Light in-memory per-IP token bucket. There is no auth, so this only stops floods."""
from __future__ import annotations

import threading
import time
from typing import Callable

CLEANUP_EVERY = 30.0  # seconds between sweeps of idle buckets


class TokenBuckets:
    def __init__(self, rate: float, burst: int, clock: Callable[[], float] = time.monotonic):
        self.rate = rate
        self.burst = burst
        self.clock = clock
        self._buckets: dict[str, tuple[float, float]] = {}
        self._lock = threading.Lock()
        self._last_cleanup = clock()

    def allow(self, key: str) -> bool:
        if self.rate <= 0:  # disabled
            return True
        now = self.clock()
        with self._lock:
            tokens, last = self._buckets.get(key, (float(self.burst), now))
            tokens = min(float(self.burst), tokens + (now - last) * self.rate)
            ok = tokens >= 1.0
            if ok:
                tokens -= 1.0
            self._buckets[key] = (tokens, now)
            if now - self._last_cleanup >= CLEANUP_EVERY:  # drop idle, fully refilled buckets
                self._last_cleanup = now
                full = [k for k, (t, ts) in self._buckets.items()
                        if t + (now - ts) * self.rate >= self.burst]
                for k in full:
                    del self._buckets[k]
            return ok
