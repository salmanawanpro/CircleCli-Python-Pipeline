#!/usr/bin/env bash
# Loads the pipeline-built image and smoke-tests it on CircleCI remote Docker.
# Postgres runs as a sibling container on a shared bridge network (remote
# Docker cannot reach the job's primary-container sidecar on localhost, and
# cannot bind-mount the primary filesystem — so we docker cp the suite in).
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-app:${CIRCLE_SHA1}}"
NETWORK_NAME="${NETWORK_NAME:-smoke-net}"
PG_CONTAINER="${PG_CONTAINER:-smoke-postgres}"
APP_CONTAINER="${APP_CONTAINER:-smoke-app}"
RUNNER_CONTAINER="${RUNNER_CONTAINER:-smoke-runner}"
APP_PORT="${APP_PORT:-5000}"
READY_TIMEOUT="${READY_TIMEOUT:-60}"

cleanup() {
  docker rm -f "$RUNNER_CONTAINER" "$APP_CONTAINER" "$PG_CONTAINER" >/dev/null 2>&1 || true
  docker network rm "$NETWORK_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Creating Docker network ${NETWORK_NAME}..."
docker network create "$NETWORK_NAME"

echo "Starting Postgres sidecar on remote Docker..."
docker run -d \
  --name "$PG_CONTAINER" \
  --network "$NETWORK_NAME" \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=app_test \
  cimg/postgres:16.2

echo "Waiting for Postgres..."
elapsed=0
until docker exec "$PG_CONTAINER" pg_isready -U postgres >/dev/null 2>&1; do
  sleep 1
  elapsed=$((elapsed + 1))
  if [ "$elapsed" -ge "$READY_TIMEOUT" ]; then
    echo "Postgres did not become ready within ${READY_TIMEOUT}s" >&2
    docker logs "$PG_CONTAINER" >&2 || true
    exit 1
  fi
done
echo "Postgres ready after ${elapsed}s."

DATABASE_URL="postgresql://postgres:postgres@${PG_CONTAINER}:5432/app_test"

echo "Starting app image ${IMAGE_TAG}..."
docker run -d \
  --name "$APP_CONTAINER" \
  --network "$NETWORK_NAME" \
  -e "DATABASE_URL=${DATABASE_URL}" \
  -e "PORT=${APP_PORT}" \
  "$IMAGE_TAG"

echo "Waiting for ${APP_CONTAINER}:${APP_PORT}/ready..."
elapsed=0
until docker run --rm --network "$NETWORK_NAME" curlimages/curl:8.7.1 \
  -fsS "http://${APP_CONTAINER}:${APP_PORT}/ready" >/dev/null 2>&1; do
  sleep 1
  elapsed=$((elapsed + 1))
  if [ "$elapsed" -ge "$READY_TIMEOUT" ]; then
    echo "App container failed to become ready within ${READY_TIMEOUT}s" >&2
    docker logs "$APP_CONTAINER" >&2 || true
    exit 1
  fi
done
echo "App ready after ${elapsed}s."

docker exec "$APP_CONTAINER" python -c "from app.app import init_db; init_db()"

echo "Running pytest smoke suite from a sibling container..."
# Use the official Python image (not cimg/*) on remote Docker — convenience
# images expect the CircleCI primary environment and can boot into system
# Python 3.8, which breaks modern pip bootstraps.
docker create \
  --name "$RUNNER_CONTAINER" \
  --network "$NETWORK_NAME" \
  --entrypoint bash \
  -w /work \
  -e "BASE_URL=http://${APP_CONTAINER}:${APP_PORT}" \
  python:3.12-slim \
  -lc 'pip install -q -r requirements.txt -r tests/requirements-test.txt && mkdir -p test-results && pytest --junitxml=test-results/image-junit.xml tests/test_image_smoke.py'

docker cp "${PWD}/requirements.txt" "${RUNNER_CONTAINER}:/work/requirements.txt"
docker cp "${PWD}/app" "${RUNNER_CONTAINER}:/work/app"
docker cp "${PWD}/tests" "${RUNNER_CONTAINER}:/work/tests"

set +e
docker start -a "$RUNNER_CONTAINER"
runner_status=$?
set -e

mkdir -p test-results
docker cp "${RUNNER_CONTAINER}:/work/test-results/." test-results/ 2>/dev/null || true

if [ "$runner_status" -ne 0 ]; then
  echo "Image smoke tests failed" >&2
  exit "$runner_status"
fi

echo "Image smoke tests passed."
