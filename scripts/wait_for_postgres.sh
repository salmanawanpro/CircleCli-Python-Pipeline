#!/usr/bin/env bash
# Waits for a Postgres sidecar to accept connections before tests run.
set -euo pipefail

HOST="${1:-localhost}"
PORT="${2:-5432}"
TIMEOUT="${3:-30}"

echo "Waiting up to ${TIMEOUT}s for Postgres at ${HOST}:${PORT}..."
elapsed=0
until pg_isready -h "$HOST" -p "$PORT" >/dev/null 2>&1; do
  sleep 1
  elapsed=$((elapsed + 1))
  if [ "$elapsed" -ge "$TIMEOUT" ]; then
    echo "Postgres did not become ready within ${TIMEOUT}s" >&2
    exit 1
  fi
done
echo "Postgres is ready after ${elapsed}s."
