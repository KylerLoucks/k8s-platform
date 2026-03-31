"""
Background worker: Redis queue (BRPOP) -> Postgres -> Redis pub/sub (jobs:events).
Admin HTTP on ADMIN_PORT for /health, /ready, /metrics.
"""

from __future__ import annotations

import json
import logging
import os
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import urlparse

import psycopg2
import redis

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("worker")

JOBS_QUEUE_KEY = "jobs:queue"
JOBS_EVENTS_CHANNEL = "jobs:events"

_ticks = 0
_last_err: str | None = None
_last_beat_ms = 0
_metrics_lock = threading.Lock()


def redis_addr() -> str:
    return os.environ.get("REDIS_ADDR", "127.0.0.1:6379").strip()


def admin_port() -> str:
    return os.environ.get("ADMIN_PORT", "8080").strip()


def tick_interval_seconds() -> float:
    raw = os.environ.get("TICK_INTERVAL", "15s").strip().lower()
    if raw.endswith("s"):
        try:
            return float(raw[:-1])
        except ValueError:
            pass
    return 15.0


def job_process_seconds() -> float:
    v = os.environ.get("JOB_PROCESS_SECONDS", "").strip()
    if v.isdigit():
        return max(1.0, float(v))
    return 2.0


def pg_dsn() -> str:
    host = os.environ.get("DB_HOST", "").strip()
    port = os.environ.get("DB_PORT", "5432").strip()
    user = os.environ.get("DB_USER", "").strip()
    password = os.environ.get("DB_PASSWORD", "")
    name = os.environ.get("DB_NAME", "").strip()
    if not host or not user or not name:
        raise RuntimeError("DB_HOST, DB_USER, DB_NAME are required for job processing")
    return (
        f"host={host} port={port} user={user} password={password} dbname={name} sslmode=disable"
    )


def redis_client() -> redis.Redis:
    url = f"redis://{redis_addr()}"
    return redis.Redis.from_url(url, decode_responses=True)


def process_job(rdb: redis.Redis, job_id: str) -> None:
    delay = job_process_seconds()
    conn = psycopg2.connect(pg_dsn())
    name: str | None = None
    try:
        conn.autocommit = False
        with conn.cursor() as cur:
            cur.execute(
                "SELECT name FROM jobs WHERE id = %s AND status = 'pending'",
                (job_id,),
            )
            row = cur.fetchone()
            if not row:
                conn.rollback()
                log.warning("job %s: not found or not pending", job_id)
                return
            (name,) = row
            cur.execute("UPDATE jobs SET status = %s WHERE id = %s", ("processing", job_id))
        conn.commit()
    except Exception:
        log.exception("job %s: mark processing", job_id)
        conn.rollback()
        return
    finally:
        conn.close()

    assert name is not None
    log.info("job %s: processing %r (simulated work %ss)", job_id, name, delay)
    time.sleep(delay)

    conn = psycopg2.connect(pg_dsn())
    item_id: int | None = None
    try:
        conn.autocommit = False
        now = datetime.now(timezone.utc)
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO demo_items (name, created_at) VALUES (%s, %s) RETURNING id",
                (name, now),
            )
            item_id = cur.fetchone()[0]
            cur.execute(
                """
                UPDATE jobs SET status = %s, item_id = %s, completed_at = %s
                WHERE id = %s
                """,
                ("completed", item_id, now, job_id),
            )
        conn.commit()
    except Exception:
        log.exception("job %s: insert item / complete job", job_id)
        conn.rollback()
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE jobs SET status = %s, completed_at = %s WHERE id = %s",
                    ("failed", datetime.now(timezone.utc), job_id),
                )
            conn.commit()
        except Exception:
            log.exception("job %s: mark failed", job_id)
            conn.rollback()
        return
    finally:
        conn.close()

    assert item_id is not None
    ev = {
        "type": "job.completed",
        "job_id": job_id,
        "item_id": int(item_id),
        "name": name,
    }
    payload = json.dumps(ev, separators=(",", ":"))
    try:
        rdb.publish(JOBS_EVENTS_CHANNEL, payload)
        log.info("job %s: completed item_id=%s, published to %s", job_id, item_id, JOBS_EVENTS_CHANNEL)
    except redis.RedisError as exc:
        log.error("job %s: publish: %s", job_id, exc)


def run_job_loop(rdb: redis.Redis) -> None:
    while True:
        try:
            out = rdb.brpop(JOBS_QUEUE_KEY, timeout=0)
            if not out:
                continue
            _, raw = out
            try:
                payload = json.loads(raw)
            except json.JSONDecodeError:
                log.warning("bad queue payload: %s", raw)
                continue
            job_id = str(payload.get("job_id", "")).strip()
            if not job_id:
                continue
            process_job(rdb, job_id)
        except redis.RedisError as exc:
            log.error("BRPop: %s", exc)
            time.sleep(1)


def run_heartbeat_loop(rdb: redis.Redis) -> None:
    global _ticks, _last_err, _last_beat_ms
    interval = tick_interval_seconds()
    while True:
        time.sleep(interval)
        _ticks += 1
        try:
            ttl = int(max(2 * interval, 30))
            rdb.setex(
                "demo:worker:last_beat",
                ttl,
                datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
            )
            with _metrics_lock:
                _last_err = None
                _last_beat_ms = int(time.time() * 1000)
            log.info("heartbeat written to redis (%s)", redis_addr())
        except redis.RedisError as exc:
            with _metrics_lock:
                _last_err = str(exc)
            log.warning("worker tick failed: %s", exc)


def make_handler(rdb: redis.Redis, dsn: str) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format: str, *args: Any) -> None:  # noqa: A003
            log.debug("%s - %s", self.address_string(), format % args)

        def do_GET(self) -> None:  # noqa: N802
            path = urlparse(self.path).path.rstrip("/") or "/"
            if path == "/health":
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"ok\n")
                return
            if path == "/ready":
                try:
                    rdb.ping()
                except redis.RedisError as exc:
                    self.send_error(503, f"redis unavailable: {exc}")
                    return
                try:
                    conn = psycopg2.connect(dsn)
                    try:
                        with conn.cursor() as cur:
                            cur.execute("SELECT 1")
                    finally:
                        conn.close()
                except Exception as exc:  # noqa: BLE001
                    self.send_error(503, f"postgres unavailable: {exc}")
                    return
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"ready\n")
                return
            if path == "/metrics":
                with _metrics_lock:
                    body = {
                        "ticks": _ticks,
                        "last_error": _last_err,
                        "last_beat_ms": _last_beat_ms,
                        "redis_addr": redis_addr(),
                    }
                data = json.dumps(body).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            self.send_error(404)

    return Handler


def main() -> None:
    rdb = redis_client()
    rdb.ping()

    try:
        dsn = pg_dsn()
        conn = psycopg2.connect(dsn)
        conn.close()
    except Exception as exc:  # noqa: BLE001
        log.exception("postgres: %s", exc)
        raise SystemExit(1) from exc

    threading.Thread(target=run_heartbeat_loop, args=(rdb,), daemon=True).start()
    threading.Thread(target=run_job_loop, args=(rdb,), daemon=True).start()

    Handler = make_handler(rdb, dsn)
    server = ThreadingHTTPServer(("0.0.0.0", int(admin_port())), Handler)
    log.info("worker admin on :%s (redis=%s, postgres ok)", admin_port(), redis_addr())
    server.serve_forever()


if __name__ == "__main__":
    main()
