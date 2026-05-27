#!/usr/bin/env python3
"""Export public-safe dashboard context from the synthetic Furniture Ops POC DB.

This script intentionally reads only the public schema/materialized views in this
repository. Private deployments can extend the context, but public exports should
stay synthetic and free of customer/contact/address/credential data.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import shlex
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "reports" / "dashboard" / "dashboard_context.json"


def psql_command() -> list[str]:
    explicit = os.environ.get("FURNITURE_DB_PSQL")
    if explicit:
        return shlex.split(explicit)
    container = os.environ.get("FURNITURE_DB_DOCKER_CONTAINER", "furniture-ops-poc-postgres-1")
    user = os.environ.get("POSTGRES_USER", "furniture")
    db = os.environ.get("POSTGRES_DB", "furniture_ops_poc")
    return ["docker", "exec", "-i", container, "psql", "-U", user, "-d", db]


def query(sql: str) -> list[dict[str, str]]:
    proc = subprocess.run(
        psql_command() + ["-v", "ON_ERROR_STOP=1", "-F", "\t", "-A", "-X", "-q", "-P", "footer=off"],
        input=sql,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=ROOT,
        check=False,
    )
    if proc.returncode:
        raise SystemExit(proc.stderr)
    return list(csv.DictReader(proc.stdout.splitlines(), delimiter="\t"))


def load_optional_work_items(path: str | None) -> list[dict]:
    if not path:
        return []
    p = Path(path)
    if not p.exists():
        raise SystemExit(f"work item file not found: {p}")
    data = json.loads(p.read_text())
    if isinstance(data, dict):
        rows = data.get("issues") or data.get("items") or data.get("work_items") or []
    elif isinstance(data, list):
        rows = data
    else:
        rows = []
    out = []
    for item in rows:
        if not isinstance(item, dict):
            continue
        out.append({
            "key": item.get("key") or item.get("id"),
            "summary": item.get("summary") or item.get("title"),
            "status": item.get("status"),
            "priority": item.get("priority"),
        })
    return out[:100]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", default=str(DEFAULT_OUT))
    ap.add_argument("--work-items-json", help="Optional sanitized Jira/work-item JSON for public/demo dashboards")
    args = ap.parse_args()

    data = {
        "operating_kpis": query("""
SELECT period_grain, period_start, gross_receipts, sold_item_cogs,
       disposed_inventory_cogs, cogs, gross_margin, gross_margin_pct,
       inventory_purchase_labor_cash_outflow, storage_cost, net_cash_effect,
       sold_item_count, disposed_item_count, acquired_item_count,
       listings_created_count, status_transition_count, moved_to_listed_active_count,
       moved_to_pending_sale_count, moved_to_sold_delivered_count,
       moved_to_disposed_count, current_unsold_inventory_count,
       current_unsold_list_price_target, current_unsold_cost_basis,
       current_stale_status_item_count, avg_days_acquired_to_listed, avg_days_acquired_to_sold
FROM analytics_operating_kpis_period_mv
ORDER BY period_grain, period_start;
"""),
        "inventory_pipeline": query("""
SELECT inventory_status, category, item_count, active_listing_count,
       list_price_target_total, expected_sale_price_total, cost_basis_total,
       avg_days_since_acquired, oldest_acquired_date, latest_listed_at
FROM analytics_inventory_pipeline_mv
ORDER BY inventory_status, category;
"""),
        "status_aging": query("""
SELECT inventory_status, status_age_bucket, stale_status_flag, item_count,
       list_price_target_total, cost_basis_total, avg_days_in_status, max_days_in_status
FROM analytics_status_aging_summary_mv
ORDER BY stale_status_flag DESC, inventory_status, status_age_bucket;
"""),
        "stale_items": query("""
SELECT inventory_uid, item_title, category, inventory_status, previous_status,
       days_in_status, status_age_bucket, list_price_target, cost_basis,
       latest_status_reason
FROM analytics_current_status_aging_mv
WHERE stale_status_flag IS TRUE
ORDER BY days_in_status DESC, inventory_uid
LIMIT 50;
"""),
        "sales_margin": query("""
SELECT inventory_uid, item_title, category, sale_date, revenue, cogs,
       gross_margin, gross_margin_pct
FROM analytics_sales_margin_mv
ORDER BY sale_date DESC NULLS LAST, gross_margin DESC;
"""),
        "listing_performance": query("""
SELECT listing_id, inventory_uid, platform, listing_status, inventory_status,
       title, listed_at, days_since_listed, current_asking_price,
       list_price_target, asking_vs_target_delta
FROM analytics_listing_performance_mv
ORDER BY days_since_listed DESC NULLS LAST, listing_id;
"""),
        "tax_category_periods": query("""
SELECT period_grain, period_start, tax_category_code, tax_category_name,
       category_kind, cash_flow_count, gross_amount, expense_amount,
       payment_amount, deductible_expense_amount, needs_review_count
FROM analytics_cash_flow_tax_category_period_mv
ORDER BY period_grain, period_start, tax_category_code;
"""),
        "work_items": load_optional_work_items(args.work_items_json),
    }

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, indent=2, sort_keys=True))
    print(json.dumps({"context": str(out), "tables": sorted(data)}, indent=2))


if __name__ == "__main__":
    main()
