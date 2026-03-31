from __future__ import annotations

import redis

from app.settings import settings

_client: redis.Redis | None = None


def get_redis() -> redis.Redis:
    global _client
    if not settings.redis_addr.strip():
        raise RuntimeError("REDIS_ADDR is not set")
    if _client is None:
        url = f"redis://{settings.redis_addr.strip()}"
        _client = redis.Redis.from_url(url, decode_responses=True)
    return _client
