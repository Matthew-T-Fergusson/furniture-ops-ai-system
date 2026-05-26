-- 004_analytics_views.sql
--
-- Synthetic analytics layer for the AI-assisted furniture operations system.
--
-- Background / design intent:
-- - The operating DB keeps normalized source-of-truth tables (`inventory`,
--   `listings`, `cash_flows`, `inventory_status_history`, etc.).
-- - Dashboards should query stable derived views instead of re-implementing
--   ad hoc joins in every report.
-- - Status history is intentionally not just an audit log: it supports
--   operational aging, stale-item triage, transition counts, and cycle times.
-- - Views are materialized so the dashboard layer can be fast and repeatable;
--   writers mutate source tables, then refresh these views.
-- - All data here is synthetic/public-safe. Do not add real customer, address,
--   receipt, storage-code, or partner-secret values to this repo.

DROP MATERIALIZED VIEW IF EXISTS analytics_cash_flow_tax_category_period_mv CASCADE;
DROP MATERIALIZED VIEW IF EXISTS analytics_operating_kpis_period_mv CASCADE;
DROP MATERIALIZED VIEW IF EXISTS analytics_status_cycle_time_mv CASCADE;
DROP MATERIALIZED VIEW IF EXISTS analytics_status_transitions_period_mv CASCADE;
DROP MATERIALIZED VIEW IF EXISTS analytics_status_aging_summary_mv CASCADE;
DROP MATERIALIZED VIEW IF EXISTS analytics_current_status_aging_mv CASCADE;
DROP MATERIALIZED VIEW IF EXISTS analytics_listing_performance_mv CASCADE;
DROP MATERIALIZED VIEW IF EXISTS analytics_sales_margin_period_mv CASCADE;
DROP MATERIALIZED VIEW IF EXISTS analytics_sales_margin_mv CASCADE;
DROP MATERIALIZED VIEW IF EXISTS analytics_inventory_pipeline_mv CASCADE;

-- Current unsold inventory grouped for operational pipeline views.
-- IMPORTANT: this view is grouped. Dashboard item-count cards must SUM(item_count),
-- not COUNT(*) over this view. That exact bug happened in the live private DB and
-- is regression-tested in CI here.
CREATE MATERIALIZED VIEW analytics_inventory_pipeline_mv AS
WITH listing_rollup AS (
  SELECT
    inventory_uid,
    count(*) AS listing_count,
    count(*) FILTER (WHERE status = 'active') AS active_listing_count,
    max(listed_at) AS latest_listed_at,
    max(current_asking_price) FILTER (WHERE status = 'active') AS active_asking_price
  FROM listings
  GROUP BY inventory_uid
)
SELECT
  coalesce(i.status, 'unknown') AS inventory_status,
  coalesce(i.category, 'uncategorized') AS category,
  count(*)::integer AS item_count,
  count(*) FILTER (WHERE coalesce(lr.listing_count,0) > 0)::integer AS ever_listed_count,
  count(*) FILTER (WHERE coalesce(lr.active_listing_count,0) > 0)::integer AS active_listing_count,
  sum(coalesce(i.list_price_target, 0))::numeric(12,2) AS list_price_target_total,
  sum(coalesce(i.expected_sale_price, i.list_price_target, 0))::numeric(12,2) AS expected_sale_price_total,
  sum(coalesce(i.allocated_cost, i.acquisition_cost, i.cost, 0))::numeric(12,2) AS cost_basis_total,
  avg((current_date - i.date_acquired)) FILTER (WHERE i.date_acquired IS NOT NULL)::numeric(10,1) AS avg_days_since_acquired,
  min(i.date_acquired) AS oldest_acquired_date,
  max(lr.latest_listed_at) AS latest_listed_at
FROM inventory i
LEFT JOIN listing_rollup lr ON lr.inventory_uid = i.inventory_uid
WHERE coalesce(i.status, '') NOT IN ('sold_delivered', 'disposed')
GROUP BY coalesce(i.status, 'unknown'), coalesce(i.category, 'uncategorized');

COMMENT ON MATERIALIZED VIEW analytics_inventory_pipeline_mv IS
  'Dashboard-ready grouped current inventory pipeline. Sum item_count for item-level totals.';

-- Item-level realized margin. Private/live variants can add more taxonomy fields,
-- but this public reference version keeps the calculation readable from generic cash-flow categories.
CREATE MATERIALIZED VIEW analytics_sales_margin_mv AS
WITH revenue AS (
  SELECT
    inventory_uid,
    sum(coalesce(amount, 0)) FILTER (WHERE txn_type = 'Payment' OR category = 'Sale') AS cash_revenue,
    max(txn_date) FILTER (WHERE txn_type = 'Payment' OR category = 'Sale') AS latest_revenue_date
  FROM cash_flows
  WHERE inventory_uid IS NOT NULL
  GROUP BY inventory_uid
), cogs AS (
  SELECT
    inventory_uid,
    sum(coalesce(amount, 0)) FILTER (
      WHERE txn_type = 'Expense'
        AND (category IN ('COGS - Inventory','COGS - Labor','Labor') OR payment_stage IN ('inventory_purchase','labor'))
    ) AS cash_cogs
  FROM cash_flows
  WHERE inventory_uid IS NOT NULL
  GROUP BY inventory_uid
)
SELECT
  i.inventory_uid,
  i.item_title,
  coalesce(i.category, 'uncategorized') AS category,
  coalesce(i.sold_at::date, revenue.latest_revenue_date) AS sale_date,
  date_trunc('month', coalesce(i.sold_at::date, revenue.latest_revenue_date))::date AS sale_month,
  coalesce(revenue.cash_revenue, 0)::numeric(12,2) AS revenue,
  coalesce(cogs.cash_cogs, i.allocated_cost, i.acquisition_cost, i.cost, 0)::numeric(12,2) AS cogs,
  (coalesce(revenue.cash_revenue, 0) - coalesce(cogs.cash_cogs, i.allocated_cost, i.acquisition_cost, i.cost, 0))::numeric(12,2) AS gross_margin,
  CASE
    WHEN coalesce(revenue.cash_revenue, 0) = 0 THEN NULL
    ELSE ((coalesce(revenue.cash_revenue, 0) - coalesce(cogs.cash_cogs, i.allocated_cost, i.acquisition_cost, i.cost, 0)) / coalesce(revenue.cash_revenue, 0))::numeric(10,4)
  END AS gross_margin_pct
FROM inventory i
LEFT JOIN revenue ON revenue.inventory_uid = i.inventory_uid
LEFT JOIN cogs ON cogs.inventory_uid = i.inventory_uid
WHERE i.status = 'sold_delivered' OR i.sold IS TRUE OR revenue.cash_revenue IS NOT NULL;

CREATE MATERIALIZED VIEW analytics_sales_margin_period_mv AS
SELECT
  grain.period_grain,
  grain.period_start,
  count(*)::integer AS sold_item_count,
  sum(coalesce(sm.revenue, 0))::numeric(12,2) AS revenue,
  sum(coalesce(sm.cogs, 0))::numeric(12,2) AS cogs,
  sum(coalesce(sm.gross_margin, 0))::numeric(12,2) AS gross_margin,
  CASE
    WHEN sum(coalesce(sm.revenue, 0)) = 0 THEN NULL
    ELSE (sum(coalesce(sm.gross_margin, 0)) / sum(coalesce(sm.revenue, 0)))::numeric(10,4)
  END AS gross_margin_pct
FROM analytics_sales_margin_mv sm
CROSS JOIN LATERAL (
  VALUES
    ('week'::text, date_trunc('week', sm.sale_date)::date),
    ('month'::text, date_trunc('month', sm.sale_date)::date)
) AS grain(period_grain, period_start)
WHERE sm.sale_date IS NOT NULL
GROUP BY grain.period_grain, grain.period_start;

CREATE MATERIALIZED VIEW analytics_listing_performance_mv AS
SELECT
  l.listing_id,
  l.inventory_uid,
  l.platform,
  l.external_listing_id,
  l.status AS listing_status,
  i.status AS inventory_status,
  l.title,
  l.listing_url,
  l.listed_at,
  l.delisted_at,
  CASE WHEN l.listed_at IS NULL THEN NULL ELSE (current_date - l.listed_at::date) END::integer AS days_since_listed,
  l.current_asking_price,
  i.list_price_target,
  (l.current_asking_price - i.list_price_target)::numeric(12,2) AS asking_vs_target_delta
FROM listings l
JOIN inventory i ON i.inventory_uid = l.inventory_uid;

-- Latest status event matching the current inventory status gives us the time
-- the item entered its current operational state. If missing, fall back to
-- status_updated_at/updated_at so older imports are still measurable.
CREATE MATERIALIZED VIEW analytics_current_status_aging_mv AS
WITH latest_current_status_event AS (
  SELECT DISTINCT ON (ish.inventory_uid)
    ish.inventory_uid,
    ish.changed_at,
    ish.from_status,
    ish.reason,
    ish.notes
  FROM inventory_status_history ish
  JOIN inventory i ON i.inventory_uid = ish.inventory_uid
  WHERE ish.to_status = i.status
  ORDER BY ish.inventory_uid, ish.changed_at DESC, ish.status_history_id DESC
)
SELECT
  i.inventory_uid,
  i.inventory_group_id,
  i.item_title,
  coalesce(i.category, 'uncategorized') AS category,
  i.status AS inventory_status,
  lc.from_status AS previous_status,
  coalesce(lc.changed_at, i.status_updated_at, i.updated_at, i.created_at) AS status_entered_at,
  (current_date - coalesce(lc.changed_at, i.status_updated_at, i.updated_at, i.created_at)::date)::integer AS days_in_status,
  CASE
    WHEN coalesce(lc.changed_at, i.status_updated_at, i.updated_at, i.created_at) IS NULL THEN 'unknown'
    WHEN current_date - coalesce(lc.changed_at, i.status_updated_at, i.updated_at, i.created_at)::date <= 7 THEN '000-007_days'
    WHEN current_date - coalesce(lc.changed_at, i.status_updated_at, i.updated_at, i.created_at)::date <= 14 THEN '008-014_days'
    WHEN current_date - coalesce(lc.changed_at, i.status_updated_at, i.updated_at, i.created_at)::date <= 30 THEN '015-030_days'
    WHEN current_date - coalesce(lc.changed_at, i.status_updated_at, i.updated_at, i.created_at)::date <= 60 THEN '031-060_days'
    ELSE '061_plus_days'
  END AS status_age_bucket,
  CASE
    WHEN i.status = 'pending_sale' AND current_date - coalesce(lc.changed_at, i.status_updated_at, i.updated_at, i.created_at)::date >= 7 THEN true
    WHEN i.status = 'ready_to_list' AND current_date - coalesce(lc.changed_at, i.status_updated_at, i.updated_at, i.created_at)::date >= 14 THEN true
    WHEN i.status = 'listed_active' AND current_date - coalesce(lc.changed_at, i.status_updated_at, i.updated_at, i.created_at)::date >= 30 THEN true
    WHEN i.status = 'hold' AND current_date - coalesce(lc.changed_at, i.status_updated_at, i.updated_at, i.created_at)::date >= 14 THEN true
    WHEN i.status IN ('acquired_unlisted','refurb_needed') AND current_date - coalesce(lc.changed_at, i.status_updated_at, i.updated_at, i.created_at)::date >= 21 THEN true
    ELSE false
  END AS stale_status_flag,
  i.list_price_target,
  coalesce(i.allocated_cost, i.acquisition_cost, i.cost, 0)::numeric(12,2) AS cost_basis,
  lc.reason AS latest_status_reason,
  lc.notes AS latest_status_notes,
  now() AS refreshed_at
FROM inventory i
LEFT JOIN latest_current_status_event lc ON lc.inventory_uid = i.inventory_uid;

CREATE MATERIALIZED VIEW analytics_status_aging_summary_mv AS
SELECT
  inventory_status,
  status_age_bucket,
  stale_status_flag,
  count(*)::integer AS item_count,
  sum(coalesce(list_price_target,0))::numeric(12,2) AS list_price_target_total,
  sum(coalesce(cost_basis,0))::numeric(12,2) AS cost_basis_total,
  avg(days_in_status)::numeric(10,1) AS avg_days_in_status,
  max(days_in_status)::integer AS max_days_in_status
FROM analytics_current_status_aging_mv
WHERE coalesce(inventory_status, '') NOT IN ('sold_delivered', 'disposed')
GROUP BY inventory_status, status_age_bucket, stale_status_flag;

CREATE MATERIALIZED VIEW analytics_status_transitions_period_mv AS
SELECT
  grain.period_grain,
  grain.period_start,
  coalesce(ish.from_status, 'none') AS from_status,
  ish.to_status,
  count(*)::integer AS transition_count,
  count(DISTINCT ish.inventory_uid)::integer AS distinct_item_count
FROM inventory_status_history ish
CROSS JOIN LATERAL (
  VALUES
    ('week'::text, date_trunc('week', ish.changed_at)::date),
    ('month'::text, date_trunc('month', ish.changed_at)::date)
) AS grain(period_grain, period_start)
GROUP BY grain.period_grain, grain.period_start, coalesce(ish.from_status, 'none'), ish.to_status;

CREATE MATERIALIZED VIEW analytics_status_cycle_time_mv AS
WITH milestones AS (
  SELECT
    i.inventory_uid,
    i.item_title,
    i.status AS current_status,
    i.date_acquired::timestamp with time zone AS acquired_at,
    min(ish.changed_at) FILTER (WHERE ish.to_status = 'ready_to_list') AS first_ready_to_list_at,
    min(ish.changed_at) FILTER (WHERE ish.to_status = 'listed_active') AS first_listed_active_at,
    min(ish.changed_at) FILTER (WHERE ish.to_status = 'pending_sale') AS first_pending_sale_at,
    min(ish.changed_at) FILTER (WHERE ish.to_status = 'sold_delivered') AS first_sold_delivered_at
  FROM inventory i
  LEFT JOIN inventory_status_history ish ON ish.inventory_uid = i.inventory_uid
  GROUP BY i.inventory_uid, i.item_title, i.status, i.date_acquired
)
SELECT
  inventory_uid,
  item_title,
  current_status,
  CASE WHEN acquired_at IS NOT NULL AND first_ready_to_list_at IS NOT NULL THEN (first_ready_to_list_at::date - acquired_at::date)::integer END AS days_acquired_to_ready,
  CASE WHEN acquired_at IS NOT NULL AND first_listed_active_at IS NOT NULL THEN (first_listed_active_at::date - acquired_at::date)::integer END AS days_acquired_to_listed,
  CASE WHEN first_listed_active_at IS NOT NULL AND first_pending_sale_at IS NOT NULL THEN (first_pending_sale_at::date - first_listed_active_at::date)::integer END AS days_listed_to_pending,
  CASE WHEN first_pending_sale_at IS NOT NULL AND first_sold_delivered_at IS NOT NULL THEN (first_sold_delivered_at::date - first_pending_sale_at::date)::integer END AS days_pending_to_sold,
  CASE WHEN acquired_at IS NOT NULL AND first_sold_delivered_at IS NOT NULL THEN (first_sold_delivered_at::date - acquired_at::date)::integer END AS days_acquired_to_sold,
  now() AS refreshed_at
FROM milestones;

CREATE MATERIALIZED VIEW analytics_operating_kpis_period_mv AS
WITH cash_by_period AS (
  SELECT
    grain.period_grain,
    grain.period_start,
    sum(coalesce(amount,0)) FILTER (WHERE txn_type = 'Payment' OR category = 'Sale') AS gross_receipts,
    sum(coalesce(amount,0)) FILTER (
      WHERE txn_type = 'Expense'
        AND (category IN ('COGS - Inventory','COGS - Labor','Labor') OR payment_stage IN ('inventory_purchase','labor'))
    ) AS cogs_cash,
    sum(coalesce(amount,0)) FILTER (WHERE payment_stage = 'storage' OR category = 'Storage') AS storage_cost,
    sum(CASE WHEN txn_type = 'Payment' THEN coalesce(amount,0) WHEN txn_type = 'Expense' THEN -coalesce(amount,0) ELSE 0 END) AS net_cash_effect
  FROM cash_flows cf
  CROSS JOIN LATERAL (
    VALUES
      ('week'::text, date_trunc('week', cf.txn_date)::date),
      ('month'::text, date_trunc('month', cf.txn_date)::date)
  ) AS grain(period_grain, period_start)
  WHERE cf.txn_date IS NOT NULL
  GROUP BY grain.period_grain, grain.period_start
), acquired_by_period AS (
  SELECT
    grain.period_grain,
    grain.period_start,
    count(*)::integer AS acquired_item_count,
    sum(coalesce(i.allocated_cost, i.acquisition_cost, i.cost, 0))::numeric(12,2) AS acquired_cost_basis
  FROM inventory i
  CROSS JOIN LATERAL (
    VALUES
      ('week'::text, date_trunc('week', i.date_acquired)::date),
      ('month'::text, date_trunc('month', i.date_acquired)::date)
  ) AS grain(period_grain, period_start)
  WHERE i.date_acquired IS NOT NULL
  GROUP BY grain.period_grain, grain.period_start
), listings_by_period AS (
  SELECT
    grain.period_grain,
    grain.period_start,
    count(*)::integer AS listings_created_count,
    count(*) FILTER (WHERE status = 'active')::integer AS listings_currently_active_count
  FROM listings l
  CROSS JOIN LATERAL (
    VALUES
      ('week'::text, date_trunc('week', l.listed_at)::date),
      ('month'::text, date_trunc('month', l.listed_at)::date)
  ) AS grain(period_grain, period_start)
  WHERE l.listed_at IS NOT NULL
  GROUP BY grain.period_grain, grain.period_start
), status_transitions_by_period AS (
  SELECT
    period_grain,
    period_start,
    sum(transition_count)::integer AS status_transition_count,
    sum(transition_count) FILTER (WHERE to_status = 'listed_active')::integer AS moved_to_listed_active_count,
    sum(transition_count) FILTER (WHERE to_status = 'pending_sale')::integer AS moved_to_pending_sale_count,
    sum(transition_count) FILTER (WHERE to_status = 'sold_delivered')::integer AS moved_to_sold_delivered_count,
    sum(transition_count) FILTER (WHERE to_status = 'hold')::integer AS moved_to_hold_count,
    sum(transition_count) FILTER (WHERE to_status = 'disposed')::integer AS moved_to_disposed_count
  FROM analytics_status_transitions_period_mv
  GROUP BY period_grain, period_start
), disposed_items AS (
  SELECT
    i.inventory_uid,
    coalesce(
      min(ish.changed_at) FILTER (WHERE ish.to_status = 'disposed'),
      i.status_updated_at,
      i.updated_at,
      i.created_at,
      i.date_acquired::timestamp with time zone
    ) AS disposed_at,
    coalesce(i.allocated_cost, i.acquisition_cost, i.cost, 0)::numeric(12,2) AS disposed_inventory_cogs
  FROM inventory i
  LEFT JOIN inventory_status_history ish ON ish.inventory_uid = i.inventory_uid
  WHERE i.status = 'disposed'
  GROUP BY i.inventory_uid, i.status_updated_at, i.updated_at, i.created_at, i.date_acquired,
           coalesce(i.allocated_cost, i.acquisition_cost, i.cost, 0)
), disposed_by_period AS (
  SELECT
    grain.period_grain,
    grain.period_start,
    count(*)::integer AS disposed_item_count,
    sum(disposed_inventory_cogs)::numeric(12,2) AS disposed_inventory_cogs
  FROM disposed_items di
  CROSS JOIN LATERAL (
    VALUES
      ('week'::text, date_trunc('week', di.disposed_at)::date),
      ('month'::text, date_trunc('month', di.disposed_at)::date)
  ) AS grain(period_grain, period_start)
  WHERE di.disposed_at IS NOT NULL
  GROUP BY grain.period_grain, grain.period_start
), periods AS (
  SELECT period_grain, period_start FROM cash_by_period
  UNION SELECT period_grain, period_start FROM acquired_by_period
  UNION SELECT period_grain, period_start FROM listings_by_period
  UNION SELECT period_grain, period_start FROM analytics_sales_margin_period_mv
  UNION SELECT period_grain, period_start FROM status_transitions_by_period
  UNION SELECT period_grain, period_start FROM disposed_by_period
), current_inventory AS (
  SELECT
    sum(coalesce(item_count,0))::integer AS current_unsold_inventory_count,
    count(*)::integer AS current_unsold_pipeline_group_count,
    sum(coalesce(list_price_target_total,0))::numeric(12,2) AS current_unsold_list_price_target,
    sum(coalesce(cost_basis_total,0))::numeric(12,2) AS current_unsold_cost_basis
  FROM analytics_inventory_pipeline_mv
), current_status_aging AS (
  SELECT
    count(*) FILTER (WHERE stale_status_flag AND coalesce(inventory_status,'') NOT IN ('sold_delivered','disposed'))::integer AS current_stale_status_item_count,
    avg(days_in_status) FILTER (WHERE coalesce(inventory_status,'') NOT IN ('sold_delivered','disposed'))::numeric(10,1) AS current_avg_days_in_status_unsold
  FROM analytics_current_status_aging_mv
), cycle_time AS (
  SELECT
    avg(days_acquired_to_listed) FILTER (WHERE days_acquired_to_listed IS NOT NULL)::numeric(10,1) AS avg_days_acquired_to_listed,
    avg(days_listed_to_pending) FILTER (WHERE days_listed_to_pending IS NOT NULL)::numeric(10,1) AS avg_days_listed_to_pending,
    avg(days_pending_to_sold) FILTER (WHERE days_pending_to_sold IS NOT NULL)::numeric(10,1) AS avg_days_pending_to_sold,
    avg(days_acquired_to_sold) FILTER (WHERE days_acquired_to_sold IS NOT NULL)::numeric(10,1) AS avg_days_acquired_to_sold
  FROM analytics_status_cycle_time_mv
)
SELECT
  p.period_grain,
  p.period_start,
  coalesce(c.gross_receipts, 0)::numeric(12,2) AS gross_receipts,
  coalesce(s.cogs, 0)::numeric(12,2) AS sold_item_cogs,
  coalesce(d.disposed_inventory_cogs, 0)::numeric(12,2) AS disposed_inventory_cogs,
  (coalesce(s.cogs, 0) + coalesce(d.disposed_inventory_cogs, 0))::numeric(12,2) AS cogs,
  (coalesce(c.gross_receipts,0) - coalesce(s.cogs,0) - coalesce(d.disposed_inventory_cogs,0))::numeric(12,2) AS gross_margin,
  CASE
    WHEN coalesce(c.gross_receipts, 0) = 0 THEN NULL
    ELSE ((coalesce(c.gross_receipts,0) - coalesce(s.cogs,0) - coalesce(d.disposed_inventory_cogs,0)) / coalesce(c.gross_receipts,0))::numeric(10,4)
  END AS gross_margin_pct,
  coalesce(c.cogs_cash, 0)::numeric(12,2) AS inventory_purchase_labor_cash_outflow,
  coalesce(c.storage_cost, 0)::numeric(12,2) AS storage_cost,
  coalesce(c.net_cash_effect, 0)::numeric(12,2) AS net_cash_effect,
  coalesce(s.sold_item_count, 0)::integer AS sold_item_count,
  coalesce(d.disposed_item_count, 0)::integer AS disposed_item_count,
  coalesce(a.acquired_item_count, 0)::integer AS acquired_item_count,
  coalesce(l.listings_created_count, 0)::integer AS listings_created_count,
  coalesce(st.status_transition_count, 0)::integer AS status_transition_count,
  coalesce(st.moved_to_listed_active_count, 0)::integer AS moved_to_listed_active_count,
  coalesce(st.moved_to_pending_sale_count, 0)::integer AS moved_to_pending_sale_count,
  coalesce(st.moved_to_sold_delivered_count, 0)::integer AS moved_to_sold_delivered_count,
  coalesce(st.moved_to_hold_count, 0)::integer AS moved_to_hold_count,
  coalesce(st.moved_to_disposed_count, 0)::integer AS moved_to_disposed_count,
  ci.current_unsold_inventory_count,
  ci.current_unsold_pipeline_group_count,
  ci.current_unsold_list_price_target,
  ci.current_unsold_cost_basis,
  csa.current_stale_status_item_count,
  csa.current_avg_days_in_status_unsold,
  ct.avg_days_acquired_to_listed,
  ct.avg_days_listed_to_pending,
  ct.avg_days_pending_to_sold,
  ct.avg_days_acquired_to_sold,
  now() AS refreshed_at
FROM periods p
LEFT JOIN cash_by_period c USING (period_grain, period_start)
LEFT JOIN analytics_sales_margin_period_mv s USING (period_grain, period_start)
LEFT JOIN disposed_by_period d USING (period_grain, period_start)
LEFT JOIN acquired_by_period a USING (period_grain, period_start)
LEFT JOIN listings_by_period l USING (period_grain, period_start)
LEFT JOIN status_transitions_by_period st USING (period_grain, period_start)
CROSS JOIN current_inventory ci
CROSS JOIN current_status_aging csa
CROSS JOIN cycle_time ct;

COMMENT ON MATERIALIZED VIEW analytics_operating_kpis_period_mv IS
  'Weekly/monthly KPI dashboard. COGS separates sold-item COGS from disposed-inventory write-offs; current_unsold_inventory_count intentionally sums grouped pipeline item_count.';

CREATE INDEX IF NOT EXISTS idx_analytics_inventory_pipeline_status ON analytics_inventory_pipeline_mv(inventory_status, category);
CREATE INDEX IF NOT EXISTS idx_analytics_status_aging_summary_status ON analytics_status_aging_summary_mv(inventory_status, status_age_bucket, stale_status_flag);
CREATE INDEX IF NOT EXISTS idx_analytics_operating_kpis_period ON analytics_operating_kpis_period_mv(period_grain, period_start);

-- Tax/category reporting view for operational dashboards.
-- This keeps tax/reporting buckets separate from operational `cash_flows.category`
-- so a resale business can analyze deductible expenses, revenue classes, and
-- review-needed rows without losing source transaction semantics.
CREATE MATERIALIZED VIEW analytics_cash_flow_tax_category_period_mv AS
SELECT
  grain.period_grain,
  grain.period_start,
  coalesce(cf.tax_category_code, 'uncategorized') AS tax_category_code,
  coalesce(tc.display_name, 'Uncategorized') AS tax_category_name,
  coalesce(tc.category_kind, 'review') AS category_kind,
  coalesce(tc.schedule_c_hint, 'Needs review') AS schedule_c_hint,
  count(*)::integer AS cash_flow_count,
  sum(coalesce(cf.amount,0))::numeric(12,2) AS gross_amount,
  sum(coalesce(cf.amount,0)) FILTER (WHERE cf.txn_type='Expense')::numeric(12,2) AS expense_amount,
  sum(coalesce(cf.amount,0)) FILTER (WHERE cf.txn_type='Payment')::numeric(12,2) AS payment_amount,
  sum(coalesce(cf.amount,0)) FILTER (
    WHERE cf.txn_type='Expense'
      AND coalesce(cf.deductible_override, tc.default_deductible, false)
  )::numeric(12,2) AS deductible_expense_amount,
  count(*) FILTER (WHERE cf.tax_category_code IS NULL OR cf.tax_category_code='unknown_needs_review')::integer AS needs_review_count,
  now() AS refreshed_at
FROM cash_flows cf
LEFT JOIN tax_categories tc ON tc.tax_category_code = cf.tax_category_code
CROSS JOIN LATERAL (
  VALUES
    ('week'::text, date_trunc('week', cf.txn_date)::date),
    ('month'::text, date_trunc('month', cf.txn_date)::date)
) AS grain(period_grain, period_start)
WHERE cf.txn_date IS NOT NULL
GROUP BY
  grain.period_grain,
  grain.period_start,
  coalesce(cf.tax_category_code, 'uncategorized'),
  coalesce(tc.display_name, 'Uncategorized'),
  coalesce(tc.category_kind, 'review'),
  coalesce(tc.schedule_c_hint, 'Needs review');

COMMENT ON MATERIALIZED VIEW analytics_cash_flow_tax_category_period_mv IS
  'Weekly/monthly cash-flow tax/reporting category view for operational and tax-aware dashboards. Not tax advice.';

CREATE INDEX IF NOT EXISTS idx_analytics_cash_flow_tax_category_period
  ON analytics_cash_flow_tax_category_period_mv(period_grain, period_start, tax_category_code);
