#!/usr/bin/env python3
"""Generate a public-safe static Furniture Ops KPI dashboard.

The dashboard is intentionally built from the synthetic materialized views in
this repository. Use --analysis-file to inject human/operator-written commentary;
Python should render metrics and charts, not invent executive analysis.
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import html
import json
import os
import shlex
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "reports" / "dashboard"


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


def esc(value) -> str:
    return html.escape(str(value if value is not None else ""))


def num(value) -> float:
    if value in (None, ""):
        return 0.0
    return float(value)


def money(value) -> str:
    return f"${num(value):,.2f}"


def pct(value) -> str:
    if value in (None, ""):
        return "—"
    return f"{num(value) * 100:.1f}%"


def table(headers: list[str], rows: list[list[str]]) -> str:
    thead = "".join(f"<th>{esc(h)}</th>" for h in headers)
    body = "".join("<tr>" + "".join(f"<td>{cell}</td>" for cell in row) + "</tr>" for row in rows)
    return f"<table><thead><tr>{thead}</tr></thead><tbody>{body}</tbody></table>"


def load_analysis(path: str | None) -> dict:
    if not path:
        return {}
    p = Path(path)
    if not p.exists():
        raise SystemExit(f"analysis file not found: {p}")
    data = json.loads(p.read_text())
    if not isinstance(data, dict):
        raise SystemExit("analysis file must contain a JSON object")
    return data


def analysis_html(analysis: dict, key: str, fallback: str = "") -> str:
    value = analysis.get(key, fallback)
    return str(value or fallback)


def section_commentary(analysis: dict, key: str) -> str:
    sections = analysis.get("section_commentary") if isinstance(analysis.get("section_commentary"), dict) else {}
    value = sections.get(key)
    if not value:
        return ""
    return f"<div class='commentary-box'>{value}</div>"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output-dir", default=str(DEFAULT_OUT))
    ap.add_argument("--analysis-file", help="JSON file containing operator-written commentary")
    ap.add_argument("--as-of", default=dt.date.today().strftime("%Y%m%d"))
    args = ap.parse_args()

    analysis = load_analysis(args.analysis_file)

    kpis = query("""
SELECT period_grain, period_start, gross_receipts, sold_item_cogs,
       disposed_inventory_cogs, cogs, gross_margin, gross_margin_pct,
       inventory_purchase_labor_cash_outflow, storage_cost, net_cash_effect,
       sold_item_count, disposed_item_count, acquired_item_count,
       listings_created_count, status_transition_count, current_unsold_inventory_count,
       current_unsold_list_price_target, current_unsold_cost_basis,
       current_stale_status_item_count, avg_days_acquired_to_listed, avg_days_acquired_to_sold
FROM analytics_operating_kpis_period_mv
WHERE period_grain = 'month'
ORDER BY period_start;
""")
    latest = kpis[-1] if kpis else {}

    pipeline = query("""
SELECT inventory_status, category, item_count, active_listing_count,
       list_price_target_total, cost_basis_total, avg_days_since_acquired
FROM analytics_inventory_pipeline_mv
ORDER BY inventory_status, category;
""")
    stale = query("""
SELECT inventory_uid, item_title, category, inventory_status, days_in_status,
       list_price_target, cost_basis, latest_status_reason
FROM analytics_current_status_aging_mv
WHERE stale_status_flag IS TRUE
ORDER BY days_in_status DESC, inventory_uid
LIMIT 25;
""")
    top_margin = query("""
SELECT inventory_uid, item_title, category, sale_date, revenue, cogs,
       gross_margin, gross_margin_pct
FROM analytics_sales_margin_mv
ORDER BY gross_margin DESC
LIMIT 10;
""")
    worst_margin = query("""
SELECT inventory_uid, item_title, category, sale_date, revenue, cogs,
       gross_margin, gross_margin_pct
FROM analytics_sales_margin_mv
ORDER BY gross_margin ASC
LIMIT 10;
""")
    listing_perf = query("""
SELECT listing_id, inventory_uid, platform, listing_status, inventory_status,
       title, listed_at, days_since_listed, current_asking_price,
       asking_vs_target_delta
FROM analytics_listing_performance_mv
ORDER BY days_since_listed DESC NULLS LAST, listing_id
LIMIT 25;
""")

    kpi_cards = [
        ("Gross receipts", money(latest.get("gross_receipts"))),
        ("Gross margin", money(latest.get("gross_margin"))),
        ("GM %", pct(latest.get("gross_margin_pct"))),
        ("Sold COGS", money(latest.get("sold_item_cogs"))),
        ("Disposed COGS", money(latest.get("disposed_inventory_cogs"))),
        ("Net cash effect", money(latest.get("net_cash_effect"))),
        ("Current unsold", esc(latest.get("current_unsold_inventory_count", "0"))),
        ("Stale statuses", esc(latest.get("current_stale_status_item_count", "0"))),
    ]
    cards_html = "".join(f"<div class='card'><b>{label}</b><span>{value}</span></div>" for label, value in kpi_cards)

    kpi_rows = [[
        esc(r["period_start"]), money(r["gross_receipts"]), money(r["sold_item_cogs"]),
        money(r["disposed_inventory_cogs"]), money(r["cogs"]), money(r["gross_margin"]),
        pct(r["gross_margin_pct"]), money(r["storage_cost"]), money(r["net_cash_effect"]),
        esc(r["sold_item_count"]), esc(r["disposed_item_count"]), esc(r["acquired_item_count"]),
    ] for r in kpis]

    pipeline_rows = [[
        esc(r["inventory_status"]), esc(r["category"]), esc(r["item_count"]),
        esc(r["active_listing_count"]), money(r["list_price_target_total"]),
        money(r["cost_basis_total"]), esc(r["avg_days_since_acquired"]),
    ] for r in pipeline]

    stale_rows = [[
        esc(r["inventory_uid"]), esc(r["item_title"]), esc(r["category"]), esc(r["inventory_status"]),
        esc(r["days_in_status"]), money(r["list_price_target"]), money(r["cost_basis"]), esc(r["latest_status_reason"]),
    ] for r in stale]

    margin_headers = ["UID", "Item", "Category", "Sale date", "Revenue", "COGS", "GM $", "GM %"]
    top_rows = [[esc(r["inventory_uid"]), esc(r["item_title"]), esc(r["category"]), esc(r["sale_date"]), money(r["revenue"]), money(r["cogs"]), money(r["gross_margin"]), pct(r["gross_margin_pct"])] for r in top_margin]
    worst_rows = [[esc(r["inventory_uid"]), esc(r["item_title"]), esc(r["category"]), esc(r["sale_date"]), money(r["revenue"]), money(r["cogs"]), money(r["gross_margin"]), pct(r["gross_margin_pct"])] for r in worst_margin]

    listing_rows = [[
        esc(r["listing_id"]), esc(r["inventory_uid"]), esc(r["platform"]), esc(r["listing_status"]),
        esc(r["inventory_status"]), esc(r["title"]), esc(r["days_since_listed"]),
        money(r["current_asking_price"]), money(r["asking_vs_target_delta"]),
    ] for r in listing_perf]

    anomaly_cues = analysis.get("anomaly_action_cues") if isinstance(analysis.get("anomaly_action_cues"), list) else []
    work_cues = analysis.get("jira_work_cues") if isinstance(analysis.get("jira_work_cues"), list) else []

    trend_labels = [r["period_start"] for r in kpis]
    revenue = [num(r["gross_receipts"]) for r in kpis]
    gross_margin = [num(r["gross_margin"]) for r in kpis]
    net_cash = [num(r["net_cash_effect"]) for r in kpis]

    html_doc = f"""<!doctype html>
<html lang='en'>
<head>
<meta charset='utf-8'>
<meta name='viewport' content='width=device-width, initial-scale=1'>
<title>Furniture Ops KPI Dashboard</title>
<script src='https://cdn.jsdelivr.net/npm/chart.js'></script>
<style>
body {{ font-family: Inter, system-ui, -apple-system, Segoe UI, sans-serif; margin: 24px; color: #172033; background: #f6f8fb; }}
h1, h2, h3 {{ color: #101828; }}
.card-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 12px; margin: 16px 0; }}
.card {{ background: white; border: 1px solid #d9e1ec; border-radius: 12px; padding: 14px; box-shadow: 0 1px 2px rgba(16,24,40,.06); }}
.card b {{ display: block; font-size: 12px; color: #667085; text-transform: uppercase; letter-spacing: .04em; }}
.card span {{ display: block; font-size: 22px; font-weight: 750; margin-top: 6px; }}
section {{ background: white; border: 1px solid #d9e1ec; border-radius: 14px; padding: 18px; margin: 18px 0; }}
.commentary-box {{ background: #f0f6ff; border-left: 4px solid #2f6fed; padding: 12px 14px; border-radius: 8px; margin: 12px 0; }}
table {{ border-collapse: collapse; width: 100%; font-size: 13px; margin: 12px 0; }}
th, td {{ border-bottom: 1px solid #e4e7ec; padding: 8px; text-align: left; vertical-align: top; }}
th {{ background: #f9fafb; color: #475467; }}
.two {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 16px; }}
.note {{ color: #667085; font-size: 13px; }}
canvas {{ max-height: 360px; }}
</style>
</head>
<body>
<h1>Furniture Ops KPI Dashboard</h1>
<p class='note'>Synthetic public-reference dashboard generated {esc(dt.datetime.now(dt.UTC).isoformat(timespec='seconds').replace('+00:00', ''))}Z. Private deployments should inject operator-written analysis with <code>--analysis-file</code>.</p>
<section>
<h2>Executive summary</h2>
<div class='commentary-box'>{analysis_html(analysis, 'executive_summary', 'Analysis file not supplied. Metrics below are synthetic/public-safe; add operator-written commentary with --analysis-file before sharing as an executive report.')}</div>
<div class='card-grid'>{cards_html}</div>
</section>
<section>
<h2>Monthly P&L + cash trend</h2>
{section_commentary(analysis, 'pl_cash_trend')}
<canvas id='trend'></canvas>
{table(['Month','Revenue','Sold COGS','Disposed COGS','Total COGS','GM $','GM %','Storage','Net cash','Sold','Disposed','Acquired'], kpi_rows)}
</section>
<section>
<h2>Operational commentary: anomalies, trends, outstanding work</h2>
<div class='commentary-box'>{analysis_html(analysis, 'operational_commentary', 'Analysis file not supplied. Review stale statuses, aged listings, write-offs, and margin outliers before treating this as a decision-ready report.')}</div>
<div class='two'>
<div><h3>Anomaly/action cues</h3>{table(['Cue'], [[str(x)] for x in anomaly_cues] or [['No operator-written anomaly cues supplied.']])}</div>
<div><h3>Work-item cues</h3>{table(['Cue'], [[str(x)] for x in work_cues] or [['No operator-written work-item cues supplied.']])}</div>
</div>
</section>
<section>
<h2>Current inventory pipeline</h2>
{section_commentary(analysis, 'current_inventory')}
{table(['Status','Category','Items','Active listings','Target value','Cost basis','Avg days since acquired'], pipeline_rows)}
</section>
<section>
<h2>Stale status items</h2>
{section_commentary(analysis, 'stale_status')}
{table(['UID','Item','Category','Status','Days','Target','Cost basis','Reason'], stale_rows)}
</section>
<section>
<h2>Profitability</h2>
{section_commentary(analysis, 'profitability')}
<div class='two'><div><h3>Top item margins</h3>{table(margin_headers, top_rows)}</div><div><h3>Worst margins by dollar GM</h3>{table(margin_headers, worst_rows)}</div></div>
</section>
<section>
<h2>Aging inventory</h2>
{section_commentary(analysis, 'aging_inventory')}
{table(['Listing ID','UID','Platform','Listing status','Inventory status','Title','Days listed','Ask','Ask vs target'], listing_rows)}
</section>
<script>
new Chart(document.getElementById('trend'), {{
  type: 'line',
  data: {{ labels: {json.dumps(trend_labels)}, datasets: [
    {{ label: 'Revenue', data: {json.dumps(revenue)}, borderColor: '#2563eb', backgroundColor: '#2563eb22', tension: .25 }},
    {{ label: 'Gross margin', data: {json.dumps(gross_margin)}, borderColor: '#16a34a', backgroundColor: '#16a34a22', tension: .25 }},
    {{ label: 'Net cash effect', data: {json.dumps(net_cash)}, borderColor: '#dc6803', backgroundColor: '#dc680322', tension: .25 }}
  ] }},
  options: {{ responsive: true, interaction: {{ mode: 'index', intersect: false }}, plugins: {{ tooltip: {{ enabled: true }} }} }}
}});
</script>
</body>
</html>
"""

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    html_path = out_dir / f"furniture_ops_dashboard_{args.as_of}.html"
    md_path = out_dir / f"furniture_ops_dashboard_{args.as_of}.md"
    html_path.write_text(html_doc)
    md_path.write_text(f"# Furniture Ops KPI Dashboard\n\nOpen `{html_path.name}` in a browser.\n")
    print(json.dumps({"html": str(html_path), "markdown": str(md_path)}, indent=2))


if __name__ == "__main__":
    main()
