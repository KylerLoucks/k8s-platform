from __future__ import annotations

import asyncio
import json
import os
from contextlib import asynccontextmanager
from datetime import UTC, datetime

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from sqlalchemy import text

from app.constants import JOBS_EVENTS_CHANNEL
from app.db import SessionLocal, engine
from app.models import WsEvent
from app.settings import settings

rooms: dict[str, set[WebSocket]] = {}
room_lock = asyncio.Lock()


def origin_allowed(origin: str | None) -> bool:
    raw = settings.ws_allowed_origins.strip()
    if raw == "" or raw == "*":
        return True
    allowed = {o.strip() for o in raw.split(",") if o.strip()}
    if not allowed:
        return True
    return (origin or "") in allowed


def persist_event(room: str, payload: str) -> None:
    if SessionLocal is None:
        return
    db = SessionLocal()
    try:
        ev = WsEvent(
            room=room[:128],
            payload=payload[:10000],
            created_at=datetime.now(UTC),
        )
        db.add(ev)
        db.commit()
    finally:
        db.close()


async def register(room: str, ws: WebSocket) -> None:
    async with room_lock:
        rooms.setdefault(room, set()).add(ws)


async def unregister(room: str, ws: WebSocket) -> None:
    async with room_lock:
        bucket = rooms.get(room)
        if not bucket:
            return
        bucket.discard(ws)
        if not bucket:
            rooms.pop(room, None)


async def broadcast(room: str, message: str, sender: WebSocket | None = None) -> None:
    async with room_lock:
        targets = list(rooms.get(room, set()))
    for peer in targets:
        if peer is sender:
            continue
        try:
            await peer.send_text(message)
        except Exception:  # noqa: BLE001
            continue


async def redis_listener() -> None:
    """Subscribe to Redis pub/sub so every ws replica broadcasts job events to connected browsers."""
    url = settings.redis_url.strip()
    if not url:
        return
    import redis.asyncio as aioredis

    client = aioredis.from_url(url, decode_responses=True)
    pubsub = client.pubsub()
    await pubsub.subscribe(JOBS_EVENTS_CHANNEL)
    try:
        while True:
            msg = await pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0)
            if msg is None:
                continue
            if msg.get("type") != "message":
                continue
            data = msg.get("data")
            if not data:
                continue
            if isinstance(data, bytes):
                data = data.decode()
            await broadcast("notifications", data, sender=None)
    except asyncio.CancelledError:
        raise
    finally:
        try:
            await pubsub.unsubscribe(JOBS_EVENTS_CHANNEL)
            await pubsub.close()
        except Exception:  # noqa: BLE001
            pass
        try:
            await client.aclose()
        except Exception:  # noqa: BLE001
            pass


@asynccontextmanager
async def lifespan(_app: FastAPI):
    task = asyncio.create_task(redis_listener())
    yield
    task.cancel()
    try:
        await task
    except asyncio.CancelledError:
        pass


app = FastAPI(title="platform-ws", version="0.1.0", lifespan=lifespan)


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/readyz")
def readyz() -> dict[str, str]:
    if engine is None:
        raise HTTPException(status_code=503, detail="database not configured")
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=503, detail=f"database unavailable: {exc}") from exc
    return {"status": "ready"}


@app.get("/api/info")
def api_info() -> dict:
    db_ok = False
    if engine is not None:
        try:
            with engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            db_ok = True
        except Exception:  # noqa: BLE001
            db_ok = False
    return {
        "service": "ws",
        "time": datetime.now(UTC).isoformat(),
        "database_configured": engine is not None,
        "database_ping": db_ok,
        "redis_pubsub": bool(settings.redis_url.strip()),
        "env_name": os.getenv("ENV_NAME", ""),
    }


@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket, room: str = "default") -> None:
    origin = websocket.headers.get("origin")
    if not origin_allowed(origin):
        await websocket.close(code=1008)
        return

    room_key = (room or "default").strip()[:128] or "default"
    await websocket.accept()
    await register(room_key, websocket)
    welcome = json.dumps(
        {"type": "system", "room": room_key, "message": "connected"},
        separators=(",", ":"),
    )
    try:
        await websocket.send_text(welcome)
        if room_key != "notifications":
            await broadcast(room_key, welcome, sender=websocket)

        if room_key == "notifications":
            # Read loop keeps the socket open; job events arrive via Redis pub/sub -> broadcast() in another task.
            while True:
                await websocket.receive_text()
        else:
            while True:
                msg = await websocket.receive_text()
                loop = asyncio.get_running_loop()
                await loop.run_in_executor(None, lambda m=msg: persist_event(room_key, m))
                out = json.dumps(
                    {"type": "message", "room": room_key, "text": msg},
                    separators=(",", ":"),
                )
                await websocket.send_text(out)
                await broadcast(room_key, out, sender=websocket)
    except WebSocketDisconnect:
        pass
    finally:
        await unregister(room_key, websocket)
