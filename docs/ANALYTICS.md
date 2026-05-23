# Analytics + KPI Layer

This public portfolio version includes a synthetic dashboard-ready analytics layer in `sql/004_analytics_views.sql`.

## Why materialized views?

The source-of-truth tables are intentionally normalized around business events:

- `inventory` — item state, cost basis, target value, sale lifecycle fields
- `inventory_status_history` — state transitions and why they happened
- `listings` / `listing_price_history` — marketplace identity and asking-price changes
- `cash_flows` — expenses, deposits, sale proceeds, reimbursements, and payments
- `pickups_deliveries` — scheduled operational movements

Dashboards should not re-create fragile ad hoc joins each time. The materialized views provide stable, documented surfaces for reporting. Writers mutate source tables; dashboard jobs refresh the views.

## Dashboard surfaces

### `analytics_inventory_pipeline_mv`

Current unsold inventory grouped by status/category:

- item count
- ever-listed and active-listing counts
- target list value
- expected sale value
- cost basis
- acquisition age

Important: this is a grouped view. Use `sum(item_count)` for the current unsold item count, not `count(*)`. The CI regression test protects against this class of dashboard bug.

### `analytics_sales_margin_mv` and `analytics_sales_margin_period_mv`

Item-level and weekly/monthly realized margin:

- revenue
- COGS
- gross margin
- gross margin percentage
- sale date/month

The public reference dataset uses simple synthetic `cash_flows` categories. A private/live deployment can enrich this with explicit operating/tax classifications.

### `analytics_listing_performance_mv`

Listing-level marketplace performance:

- listing status
- inventory status
- days listed
- current ask vs target price
- listing identity and URL

### `analytics_current_status_aging_mv`

Item-level operational aging from `inventory_status_history`:

- current status entry timestamp
- days in status
- age bucket
- stale-status flag
- latest transition context

Status history is not only an audit log. It powers operational triage: what is stuck, stale, or ready for a decision.

### `analytics_status_aging_summary_mv`

Rollup of current unsold inventory by:

- status
- status age bucket
- stale flag
- item count
- target value
- cost basis
- average/max days in status

### `analytics_status_transitions_period_mv`

Weekly/monthly movement counts by `from_status -> to_status`, including how many items moved into listed, pending, sold, hold, or disposed states.

### `analytics_status_cycle_time_mv`

Item-level cycle-time measures:

- acquired → ready
- acquired → listed
- listed → pending
- pending → sold
- acquired → sold

### `analytics_operating_kpis_period_mv`

One dashboard table for weekly/monthly operating health:

- gross receipts
- COGS
- gross margin
- storage cost
- net cash effect
- sold/acquired/listing counts
- status transition counts
- current unsold inventory count/value/cost basis
- stale status count
- cycle-time averages

## Refresh policy

In this public reference version, `make ci-smoke` rebuilds the schema and analytics views from scratch. In a private/live deployment, refresh materialized views after writer/import jobs that change source tables.

Example production-style refresh:

```sql
REFRESH MATERIALIZED VIEW analytics_inventory_pipeline_mv;
REFRESH MATERIALIZED VIEW analytics_sales_margin_mv;
REFRESH MATERIALIZED VIEW analytics_sales_margin_period_mv;
REFRESH MATERIALIZED VIEW analytics_listing_performance_mv;
REFRESH MATERIALIZED VIEW analytics_current_status_aging_mv;
REFRESH MATERIALIZED VIEW analytics_status_aging_summary_mv;
REFRESH MATERIALIZED VIEW analytics_status_transitions_period_mv;
REFRESH MATERIALIZED VIEW analytics_status_cycle_time_mv;
REFRESH MATERIALIZED VIEW analytics_operating_kpis_period_mv;
```

## Privacy and security

Analytics views must not expose private operational secrets such as real addresses, gate codes, lockbox codes, phone numbers, OAuth data, receipt images, or partner-only notes. Keep private data in private deployments; keep this public portfolio version synthetic.
