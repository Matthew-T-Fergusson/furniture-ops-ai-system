#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POSTGRES_USER="${POSTGRES_USER:-furniture}"
POSTGRES_DB="${POSTGRES_DB:-furniture_ops_poc}"

if [[ -n "${DATABASE_URL:-}" ]]; then
  PSQL=(psql "${DATABASE_URL}")
else
  docker compose -f "${ROOT}/docker-compose.yml" up -d postgres >/dev/null
  for _ in {1..30}; do
    if docker compose -f "${ROOT}/docker-compose.yml" exec -T postgres pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  PSQL=(docker compose -f "${ROOT}/docker-compose.yml" exec -T postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}")
fi

run_psql() {
  "${PSQL[@]}" -v ON_ERROR_STOP=1 "$@"
}

run_sql_file() {
  local file="$1"
  run_psql < "${file}"
}

# Make the smoke test repeatable against a reused local Docker volume.
run_psql -c "DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;"

run_sql_file "${ROOT}/sql/001_schema.sql"
run_sql_file "${ROOT}/sql/002_guardrail_views.sql"
run_sql_file "${ROOT}/sql/003_sample_seed.sql"
run_sql_file "${ROOT}/sql/004_analytics_views.sql"

printf '\nGuardrail summary after synthetic seed:\n'
run_psql -c "SELECT * FROM furniture_db_guardrail_summary;"

error_count="$(run_psql -Atc "SELECT count(*) FROM furniture_db_guardrail_summary WHERE severity='error';")"
if [[ "${error_count}" != "0" ]]; then
  echo "CI smoke failed: synthetic seed produced ${error_count} error-severity guardrails" >&2
  exit 1
fi

run_sql_file "${ROOT}/tests/guardrail_regressions.sql"

# KPI regression: analytics_inventory_pipeline_mv is grouped, so the current
# unsold dashboard card must sum item_count. Counting grouped rows undercounts
# real items whenever multiple status/category groups exist.
source_unsold_count="$(run_psql -Atc "SELECT count(*) FROM inventory WHERE coalesce(status,'') NOT IN ('sold_delivered','disposed');")"
kpi_unsold_count="$(run_psql -Atc "SELECT current_unsold_inventory_count FROM analytics_operating_kpis_period_mv WHERE period_grain='month' ORDER BY period_start DESC LIMIT 1;")"
if [[ "${source_unsold_count}" != "${kpi_unsold_count}" ]]; then
  echo "CI smoke failed: KPI unsold count ${kpi_unsold_count} != source unsold count ${source_unsold_count}" >&2
  exit 1
fi

# The status-history layer should be populated from synthetic status events.
status_aging_count="$(run_psql -Atc "SELECT count(*) FROM analytics_current_status_aging_mv;")"
if [[ "${status_aging_count}" == "0" ]]; then
  echo "CI smoke failed: status-history analytics produced zero rows" >&2
  exit 1
fi

# Agent governance regression: the public repository must expose the audit-trail
# pattern with synthetic rows and a recent-action view, proving that agent
# actions are reviewable rather than invisible side effects.
action_log_count="$(run_psql -Atc "SELECT count(*) FROM agent_action_log_recent;")"
if [[ "${action_log_count}" == "0" ]]; then
  echo "CI smoke failed: agent_action_log_recent produced zero rows" >&2
  exit 1
fi
blocked_action_count="$(run_psql -Atc "SELECT count(*) FROM agent_action_log_recent WHERE status='blocked_by_guardrail' AND guardrails_after ? 'anomalies';")"
if [[ "${blocked_action_count}" == "0" ]]; then
  echo "CI smoke failed: no blocked_by_guardrail action with guardrail anomaly summary" >&2
  exit 1
fi

echo "ci-smoke: ok"
