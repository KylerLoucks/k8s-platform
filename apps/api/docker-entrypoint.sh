#!/bin/sh
set -e
if [ -n "${DB_HOST:-}" ]; then
  alembic upgrade head
fi
exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}"
