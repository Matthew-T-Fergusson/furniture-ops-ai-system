#!/usr/bin/env python3
"""Public furniture-ops DB CLI.

AWF-189: lightweight migration framework for the public sanitized repo.

Defaults:
- If DATABASE_URL is set, use `psql $DATABASE_URL`.
- Else use FURNITURE_DB_PSQL when provided.
- Else use the local docker-compose Postgres service/container values.

Commands:
  migrate status        Show disk/applied/pending migrations.
  migrate validate      Fail on checksum drift or duplicate migration ids.
  migrate apply         Apply pending sql/*.sql files in lexical order.
  migrate mark-existing Record current sql/*.sql files as applied without executing.
  smoke                 Run the public smoke workflow using the migration runner.
"""
from __future__ import annotations

import argparse
import dataclasses
import hashlib
import os
import shlex
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "sql"
TEST_DIR = ROOT / "tests"

LEDGER_SQL = """
CREATE TABLE IF NOT EXISTS public.schema_migrations (
  migration_id text PRIMARY KEY,
  filename text NOT NULL UNIQUE,
  checksum_sha256 text NOT NULL,
  applied_at timestamptz NOT NULL DEFAULT now(),
  execution_ms integer,
  applied_by text NOT NULL DEFAULT current_user,
  runner text NOT NULL DEFAULT 'scripts/db_cli.py',
  note text
);
COMMENT ON TABLE public.schema_migrations IS
  'Public furniture-ops migration ledger. One row per applied sql/*.sql file.';
"""


@dataclasses.dataclass(frozen=True)
class Migration:
    path: Path
    filename: str
    migration_id: str
    checksum: str


def sql_files() -> list[Migration]:
    migrations: list[Migration] = []
    for path in sorted(p for p in SQL_DIR.glob("*.sql") if p.is_file()):
        data = path.read_bytes()
        migrations.append(
            Migration(
                path=path,
                filename=path.name,
                migration_id=path.stem,
                checksum=hashlib.sha256(data).hexdigest(),
            )
        )
    return migrations


def psql_command() -> list[str]:
    if database_url := os.environ.get("DATABASE_URL"):
        return ["psql", database_url]
    if explicit := os.environ.get("FURNITURE_DB_PSQL"):
        return shlex.split(explicit)
    user = os.environ.get("POSTGRES_USER", "furniture")
    db = os.environ.get("POSTGRES_DB", "furniture_ops_poc")
    container = os.environ.get("FURNITURE_DB_DOCKER_CONTAINER", "furniture-ops-poc-postgres-1")
    return ["docker", "exec", "-i", container, "psql", "-U", user, "-d", db]


def run_sql(sql: str, *, capture: bool = False) -> subprocess.CompletedProcess[str]:
    cmd = psql_command() + ["-v", "ON_ERROR_STOP=1", "-X", "-q"]
    if capture:
        cmd.append("-At")
    return subprocess.run(
        cmd,
        input=sql,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE,
        check=False,
    )


def run_sql_file(path: Path) -> subprocess.CompletedProcess[str]:
    return run_sql(path.read_text())


def require_ok(proc: subprocess.CompletedProcess[str], action: str) -> str:
    if proc.returncode != 0:
        sys.stderr.write(f"{action} failed with exit {proc.returncode}\n")
        if proc.stdout:
            sys.stderr.write(proc.stdout)
        if proc.stderr:
            sys.stderr.write(proc.stderr)
        raise SystemExit(proc.returncode)
    return proc.stdout or ""


def quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def ensure_ledger() -> None:
    require_ok(run_sql(LEDGER_SQL), "ensure schema_migrations")


def applied_rows() -> dict[str, dict[str, str]]:
    ensure_ledger()
    out = require_ok(
        run_sql(
            """
SELECT migration_id || E'\t' || filename || E'\t' || checksum_sha256 || E'\t' || applied_at::text || E'\t' || coalesce(note,'')
FROM public.schema_migrations
ORDER BY filename;
""",
            capture=True,
        ),
        "read schema_migrations",
    )
    rows: dict[str, dict[str, str]] = {}
    for line in out.splitlines():
        if not line.strip():
            continue
        migration_id, filename, checksum, applied_at, note = line.split("\t", 4)
        rows[filename] = {
            "migration_id": migration_id,
            "filename": filename,
            "checksum": checksum,
            "applied_at": applied_at,
            "note": note,
        }
    return rows


def insert_ledger_sql(migration: Migration, execution_ms: int | None, note: str) -> str:
    ms = "NULL" if execution_ms is None else str(int(execution_ms))
    return f"""
INSERT INTO public.schema_migrations (migration_id, filename, checksum_sha256, execution_ms, note)
VALUES ({quote(migration.migration_id)}, {quote(migration.filename)}, {quote(migration.checksum)}, {ms}, {quote(note)})
ON CONFLICT (migration_id) DO UPDATE
SET filename = EXCLUDED.filename,
    checksum_sha256 = EXCLUDED.checksum_sha256,
    execution_ms = EXCLUDED.execution_ms,
    note = EXCLUDED.note;
"""


def migrate_validate() -> int:
    migrations = {m.filename: m for m in sql_files()}
    rows = applied_rows()
    problems: list[str] = []
    for filename, row in rows.items():
        migration = migrations.get(filename)
        if migration is None:
            problems.append(f"applied migration missing from disk: {filename}")
        elif row["checksum"] != migration.checksum:
            problems.append(f"checksum mismatch for {filename}: ledger={row['checksum']} disk={migration.checksum}")
    ids = [m.migration_id for m in migrations.values()]
    if len(ids) != len(set(ids)):
        problems.append("duplicate migration_id stems found in sql/*.sql")
    if problems:
        print("migration validation: FAIL")
        for problem in problems:
            print(f"- {problem}")
        return 1
    print("migration validation: ok")
    return 0


def migrate_status() -> int:
    migrations = sql_files()
    rows = applied_rows()
    pending = [m for m in migrations if m.filename not in rows]
    print(f"sql_dir: {SQL_DIR}")
    print(f"disk_migrations: {len(migrations)}")
    print(f"applied_migrations: {len(rows)}")
    if pending:
        print("pending:")
        for migration in pending:
            print(f"- {migration.filename}")
    else:
        print("pending: none")
    changed = [m.filename for m in migrations if m.filename in rows and rows[m.filename]["checksum"] != m.checksum]
    if changed:
        print("checksum_mismatches:")
        for filename in changed:
            print(f"- {filename}")
        return 1
    return 0


def migrate_mark_existing() -> int:
    ensure_ledger()
    migrations = sql_files()
    if not migrations:
        print("no migrations found")
        return 1
    sql = "BEGIN;\n" + "\n".join(
        insert_ledger_sql(m, None, "marked existing by scripts/db_cli.py") for m in migrations
    ) + "\nCOMMIT;\n"
    require_ok(run_sql(sql), "mark existing migrations")
    print(f"marked {len(migrations)} existing migrations as applied")
    return migrate_status()


def migrate_apply() -> int:
    if migrate_validate() != 0:
        return 1
    rows = applied_rows()
    pending = [m for m in sql_files() if m.filename not in rows]
    if not pending:
        print("no pending migrations")
        return 0
    for migration in pending:
        print(f"applying {migration.filename}...")
        start = time.monotonic()
        require_ok(run_sql_file(migration.path), f"apply {migration.filename}")
        elapsed_ms = int((time.monotonic() - start) * 1000)
        require_ok(
            run_sql(insert_ledger_sql(migration, elapsed_ms, "applied by scripts/db_cli.py")),
            f"record {migration.filename}",
        )
        print(f"applied {migration.filename} in {elapsed_ms} ms")
    return migrate_status()


def scalar(sql: str, action: str) -> str:
    return require_ok(run_sql(sql, capture=True), action).strip()


def require_nonzero_count(sql: str, message: str) -> None:
    count = scalar(sql, message)
    if count == "0":
        print(f"CI smoke failed: {message}", file=sys.stderr)
        raise SystemExit(1)


def smoke() -> int:
    migrate_apply_rc = migrate_apply()
    if migrate_apply_rc != 0:
        return migrate_apply_rc
    print("\nGuardrail summary after synthetic seed:")
    require_ok(run_sql("SELECT * FROM furniture_db_guardrail_summary;"), "guardrail summary")
    error_count = require_ok(
        run_sql("SELECT count(*) FROM furniture_db_guardrail_summary WHERE severity='error';", capture=True),
        "guardrail error count",
    ).strip()
    if error_count != "0":
        print(f"CI smoke failed: synthetic seed produced {error_count} error-severity guardrails", file=sys.stderr)
        return 1
    for test_file in [
        TEST_DIR / "guardrail_regressions.sql",
        TEST_DIR / "message_template_rendering.sql",
        TEST_DIR / "conversation_tags_merge_funnel.sql",
    ]:
        require_ok(run_sql_file(test_file), f"run {test_file.name}")

    source_unsold_count = scalar(
        "SELECT count(*) FROM inventory WHERE coalesce(status,'') NOT IN ('sold_delivered','disposed');",
        "source unsold count",
    )
    kpi_unsold_count = scalar(
        "SELECT current_unsold_inventory_count FROM analytics_operating_kpis_period_mv "
        "WHERE period_grain='month' ORDER BY period_start DESC LIMIT 1;",
        "kpi unsold count",
    )
    if source_unsold_count != kpi_unsold_count:
        print(
            f"CI smoke failed: KPI unsold count {kpi_unsold_count} != source unsold count {source_unsold_count}",
            file=sys.stderr,
        )
        return 1
    require_nonzero_count(
        "SELECT count(*) FROM analytics_operating_kpis_period_mv "
        "WHERE disposed_item_count > 0 AND disposed_inventory_cogs > 0 "
        "AND cogs = sold_item_cogs + disposed_inventory_cogs;",
        "disposed inventory COGS is not separately exposed/included in KPI COGS",
    )
    require_nonzero_count(
        "SELECT count(*) FROM analytics_current_status_aging_mv;",
        "status-history analytics produced zero rows",
    )
    require_nonzero_count(
        "SELECT count(*) FROM listing_status_history WHERE source_system='synthetic_seed';",
        "listing_status_history has no synthetic status events",
    )
    require_nonzero_count(
        "SELECT count(*) FROM listing_status_dashboard "
        "WHERE listing_status='active_verified' AND is_active_verified AND NOT needs_verification;",
        "listing_status_dashboard has no active verified listing",
    )
    require_nonzero_count(
        "SELECT count(*) FROM listing_status_dashboard WHERE ready_but_not_live;",
        "listing_status_dashboard has no ready-but-not-live row",
    )
    require_nonzero_count(
        "SELECT count(*) FROM listing_platform_status_summary "
        "WHERE active_verified_count > 0 AND ready_but_not_live_count > 0;",
        "listing_platform_status_summary missing expected coverage metrics",
    )
    require_nonzero_count(
        "SELECT count(*) FROM contact_activity_timeline cat "
        "JOIN contacts c USING (contact_id) "
        "WHERE c.display_name='Morgan Buyer' AND cat.activity_type='conversation_message';",
        "Morgan Buyer contact timeline has no message activity",
    )
    require_nonzero_count(
        "SELECT count(*) FROM contact_activity_timeline cat "
        "JOIN contacts c USING (contact_id) "
        "WHERE c.display_name='Morgan Buyer' AND cat.activity_type IN ('movement','cash_flow');",
        "Morgan Buyer contact timeline has no operational activity",
    )
    require_nonzero_count(
        "SELECT count(*) FROM response_sla_metrics "
        "WHERE platform='craigslist_email' AND threads_with_inbound > 0 "
        "AND threads_responded > 0 AND median_first_response_hours IS NOT NULL "
        "AND p90_first_response_hours IS NOT NULL;",
        "response_sla_metrics missing expected Craigslist email response metrics",
    )
    require_nonzero_count(
        "SELECT count(*) FROM response_sla_thread_metrics "
        "WHERE platform='craigslist_email' AND inbound_message_count > 0 "
        "AND responded_inbound_message_count > 0 AND first_response_hours IS NOT NULL;",
        "response_sla_thread_metrics missing expected inbound/outbound pair metrics",
    )
    require_nonzero_count(
        "SELECT count(*) FROM agent_action_log_recent;",
        "agent_action_log_recent produced zero rows",
    )
    require_nonzero_count(
        "SELECT count(*) FROM agent_action_log_recent "
        "WHERE status='blocked_by_guardrail' AND guardrails_after ? 'anomalies';",
        "no blocked_by_guardrail action with guardrail anomaly summary",
    )
    tax_category_count = int(scalar("SELECT count(*) FROM tax_categories;", "tax category count"))
    if tax_category_count < 10:
        print(f"CI smoke failed: expected reusable tax category taxonomy, found {tax_category_count} rows", file=sys.stderr)
        return 1
    uncategorized = scalar("SELECT count(*) FROM cash_flows WHERE tax_category_code IS NULL;", "uncategorized cash flow count")
    if uncategorized != "0":
        print(f"CI smoke failed: synthetic cash_flows include {uncategorized} uncategorized tax rows", file=sys.stderr)
        return 1
    require_nonzero_count(
        "SELECT count(*) FROM analytics_cash_flow_tax_category_period_mv;",
        "tax category analytics view produced zero rows",
    )

    require_ok(
        subprocess.run(
            [sys.executable, "-m", "py_compile", str(ROOT / "scripts/generate_kpi_dashboard.py"), str(ROOT / "scripts/export_dashboard_context.py")],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        ),
        "compile dashboard scripts",
    )
    with tempfile.TemporaryDirectory(prefix="furniture_ops_poc_dashboard_") as tmp:
        out_context = Path(tmp) / "dashboard_context.json"
        out_dir = Path(tmp) / "dashboard"
        require_ok(
            subprocess.run(
                [sys.executable, str(ROOT / "scripts/export_dashboard_context.py"), "--output", str(out_context)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            ),
            "export dashboard context",
        )
        require_ok(
            subprocess.run(
                [sys.executable, str(ROOT / "scripts/generate_kpi_dashboard.py"), "--output-dir", str(out_dir), "--as-of", "20260527"],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            ),
            "generate KPI dashboard",
        )
        dashboard = out_dir / "furniture_ops_dashboard_20260527.html"
        if not dashboard.exists() or dashboard.stat().st_size == 0:
            print("CI smoke failed: dashboard generator did not produce expected HTML", file=sys.stderr)
            return 1

    require_ok(
        run_sql(
            "INSERT INTO cash_flows (cf_record_id, txn_type, txn_date, vendor_or_description, amount, category, tax_category_code) "
            "VALUES ('CI-TAX-REVIEW', 'Expense', current_date - interval '45 days', 'Synthetic review expense', 12.34, 'Supplies', 'unknown_needs_review');"
        ),
        "insert tax review warning row",
    )
    review_warning_count = scalar(
        "SELECT count(*) FROM furniture_db_guardrail_anomalies "
        "WHERE entity_type='cash_flow' AND entity_id='CI-TAX-REVIEW' "
        "AND anomaly_type='expense_missing_tax_category' AND severity='warning';",
        "tax review warning count",
    )
    if review_warning_count != "1":
        print("CI smoke failed: unknown tax category did not surface as a warning", file=sys.stderr)
        return 1
    require_ok(run_sql("DELETE FROM cash_flows WHERE cf_record_id='CI-TAX-REVIEW';"), "delete tax review warning row")

    print("ci-smoke: ok")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Public furniture-ops DB CLI")
    sub = parser.add_subparsers(dest="command", required=True)
    migrate = sub.add_parser("migrate", help="Manage sql/*.sql migrations")
    migrate_sub = migrate.add_subparsers(dest="migrate_command", required=True)
    for command in ["status", "validate", "apply", "mark-existing"]:
        migrate_sub.add_parser(command)
    sub.add_parser("smoke", help="Run public smoke checks after applying migrations")
    args = parser.parse_args(argv)
    if args.command == "smoke":
        return smoke()
    if args.command == "migrate":
        if args.migrate_command == "status":
            return migrate_status()
        if args.migrate_command == "validate":
            return migrate_validate()
        if args.migrate_command == "apply":
            return migrate_apply()
        if args.migrate_command == "mark-existing":
            return migrate_mark_existing()
    raise AssertionError(args)


if __name__ == "__main__":
    raise SystemExit(main())
