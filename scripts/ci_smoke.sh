#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POSTGRES_USER="${POSTGRES_USER:-furniture}"
POSTGRES_DB="${POSTGRES_DB:-furniture_ops_poc}"

if [[ -n "${DATABASE_URL:-}" ]]; then
  PSQL=(psql "${DATABASE_URL}")
  export FURNITURE_DB_PSQL="psql ${DATABASE_URL}"
else
  CI_CONTAINER="${FURNITURE_DB_DOCKER_CONTAINER:-furniture-ops-ci-smoke-$RANDOM}"
  export FURNITURE_DB_DOCKER_CONTAINER="${CI_CONTAINER}"
  docker rm -f "${CI_CONTAINER}" >/dev/null 2>&1 || true
  docker run -d \
    --name "${CI_CONTAINER}" \
    -e POSTGRES_DB="${POSTGRES_DB}" \
    -e POSTGRES_USER="${POSTGRES_USER}" \
    -e POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-change_me}" \
    postgres:17 >/dev/null
  trap 'docker rm -f "${CI_CONTAINER}" >/dev/null 2>&1 || true' EXIT
  for _ in {1..60}; do
    if docker exec "${CI_CONTAINER}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -Atc "SELECT 1" >/dev/null 2>&1; then
      sleep 2
      if docker exec "${CI_CONTAINER}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -Atc "SELECT 1" >/dev/null 2>&1; then
        break
      fi
    fi
    sleep 1
  done
  PSQL=(docker exec -i "${CI_CONTAINER}" psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}")
fi

# Make the smoke test repeatable against a reused local Docker volume.
"${PSQL[@]}" -v ON_ERROR_STOP=1 -c "DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;"

python3 "${ROOT}/scripts/db_cli.py" smoke
