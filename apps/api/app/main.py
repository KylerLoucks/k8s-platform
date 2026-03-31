from __future__ import annotations

import json
import os
import uuid
from datetime import UTC, datetime

from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sqlalchemy import select, text
from sqlalchemy.orm import Session

from app.constants import JOBS_QUEUE_KEY
from app.db import engine, get_db
from app.models import DemoCounter, DemoItem, Job
from app.redis_client import get_redis
from app.settings import settings

app = FastAPI(title="platform-api", version="0.1.0")

_cors_origins = ["*"] if settings.cors_allow_origin.strip() == "*" else [settings.cors_allow_origin.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


class ItemCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)


class JobCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)


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
        "service": "api",
        "time": datetime.now(UTC).isoformat(),
        "database_configured": engine is not None,
        "database_ping": db_ok,
        "env_name": os.getenv("ENV_NAME", ""),
    }


@app.get("/api/items")
def list_items(db: Session = Depends(get_db)) -> dict:
    rows = db.scalars(select(DemoItem).order_by(DemoItem.id.desc()).limit(50)).all()
    return {
        "items": [{"id": r.id, "name": r.name, "created_at": r.created_at.isoformat()} for r in rows],
    }


@app.get("/api/jobs")
def list_jobs(db: Session = Depends(get_db)) -> dict:
    rows = db.scalars(select(Job).order_by(Job.created_at.desc()).limit(50)).all()
    return {
        "jobs": [
            {
                "id": r.id,
                "name": r.name,
                "status": r.status,
                "item_id": r.item_id,
                "created_at": r.created_at.isoformat(),
                "completed_at": r.completed_at.isoformat() if r.completed_at else None,
            }
            for r in rows
        ],
    }


@app.post("/api/jobs")
def schedule_job(body: JobCreate, db: Session = Depends(get_db)) -> dict:
    """Enqueue background work: worker creates the demo item and publishes a Redis event for WS fan-out."""
    try:
        get_redis()
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    job_id = str(uuid.uuid4())
    job = Job(
        id=job_id,
        name=body.name.strip(),
        status="pending",
        created_at=datetime.now(UTC),
    )
    db.add(job)
    db.commit()
    db.refresh(job)

    try:
        r = get_redis()
        r.lpush(JOBS_QUEUE_KEY, json.dumps({"job_id": job_id}))
    except Exception as exc:
        job.status = "failed"
        db.commit()
        raise HTTPException(status_code=503, detail=f"redis queue unavailable: {exc}") from exc

    return {
        "job_id": job.id,
        "status": job.status,
        "message": "queued — worker will create the item and broadcast completion",
    }


@app.post("/api/items")
def create_item(body: ItemCreate, db: Session = Depends(get_db)) -> dict:
    item = DemoItem(name=body.name.strip(), created_at=datetime.now(UTC))
    db.add(item)
    db.commit()
    db.refresh(item)
    return {"id": item.id, "name": item.name, "created_at": item.created_at.isoformat()}


@app.get("/api/counter")
def bump_counter(db: Session = Depends(get_db)) -> dict:
    key = "demo:counter"
    row = db.scalars(select(DemoCounter).where(DemoCounter.key == key)).first()
    if row is None:
        row = DemoCounter(key=key, value=0)
        db.add(row)
        db.flush()
    row.value += 1
    db.commit()
    return {"counter": row.value, "service": "api"}
