-- Guardrail views for AI-assisted database writes

CREATE OR REPLACE VIEW furniture_db_guardrail_anomalies AS
WITH group_cost AS (
  SELECT
    g.inventory_group_id,
    g.group_type,
    g.total_acquisition_cost,
    sum(coalesce(i.allocated_cost,0)) AS allocated_cost_sum,
    count(i.*) AS item_count
  FROM inventory_groups g
  LEFT JOIN inventory i ON i.inventory_group_id = g.inventory_group_id
  GROUP BY g.inventory_group_id, g.group_type, g.total_acquisition_cost
), sale_cf AS (
  SELECT
    inventory_uid,
    inventory_group_id,
    count(*) FILTER (WHERE txn_type='Payment' AND category='Sale') AS sale_payment_count,
    count(*) FILTER (WHERE txn_type='Payment' AND category='Sale' AND payment_stage='deposit') AS deposit_count
  FROM cash_flows
  GROUP BY inventory_uid, inventory_group_id
)
SELECT
  'inventory'::text AS entity_type,
  i.inventory_uid AS entity_id,
  i.inventory_group_id,
  'listed_status_missing_listing_identity'::text AS anomaly_type,
  'error'::text AS severity,
  'listed_active/pending_sale inventory should have a real external listing ID and URL unless explicitly non-marketplace.'::text AS message
FROM inventory i
WHERE i.status IN ('listed_active','pending_sale')
  AND (
    NULLIF(btrim(coalesce(i.item_id,'')), '') IS NULL
    OR lower(coalesce(i.item_id,'')) IN ('n/a','na','tbd')
    OR NULLIF(btrim(coalesce(i.cl_url,'')), '') IS NULL
    OR lower(coalesce(i.cl_url,'')) IN ('n/a','na','tbd')
  )

UNION ALL
SELECT
  'inventory', i.inventory_uid, i.inventory_group_id,
  'pending_sale_without_deposit_cashflow', 'warning',
  'pending_sale should normally start only once a deposit exists; ask for deposit amount, method, paid_to, buyer, and pickup/delivery timeline.'
FROM inventory i
LEFT JOIN sale_cf cf ON cf.inventory_uid = i.inventory_uid OR (cf.inventory_uid IS NULL AND cf.inventory_group_id = i.inventory_group_id)
WHERE i.status = 'pending_sale'
  AND coalesce(cf.deposit_count,0) = 0

UNION ALL
SELECT
  'inventory', i.inventory_uid, i.inventory_group_id,
  'sold_delivered_missing_sale_date', 'error',
  'sold_delivered requires a sold_at timestamp.'
FROM inventory i
WHERE i.status = 'sold_delivered' AND i.sold_at IS NULL

UNION ALL
SELECT
  'inventory', i.inventory_uid, i.inventory_group_id,
  'sold_delivered_without_sale_cashflow', 'error',
  'sold_delivered requires final/full sale payment cash-flow record(s), unless explicitly zero-sale/disposal.'
FROM inventory i
LEFT JOIN sale_cf cf ON cf.inventory_uid = i.inventory_uid OR (cf.inventory_uid IS NULL AND cf.inventory_group_id = i.inventory_group_id)
WHERE i.status = 'sold_delivered'
  AND coalesce(cf.sale_payment_count,0) = 0

UNION ALL
SELECT
  'inventory', i.inventory_uid, i.inventory_group_id,
  'zero_cost_missing_cost_basis_source', 'error',
  'Zero-cost inventory must declare cost_basis_source.'
FROM inventory i
WHERE coalesce(i.acquisition_cost, i.cost, 0) = 0
  AND NULLIF(btrim(coalesce(i.cost_basis_source,'')), '') IS NULL

UNION ALL
SELECT
  'inventory_group', gc.inventory_group_id, gc.inventory_group_id,
  'group_allocated_cost_mismatch', 'error',
  'For multi-item groups/lots, sum(child allocated_cost) should equal inventory_groups.total_acquisition_cost unless intentionally unresolved.'
FROM group_cost gc
WHERE gc.item_count > 1
  AND gc.total_acquisition_cost IS NOT NULL
  AND abs(coalesce(gc.allocated_cost_sum,0) - gc.total_acquisition_cost) > 0.01

UNION ALL
SELECT
  'cash_flow', cf.cf_record_id, cf.inventory_group_id,
  'sale_payment_missing_payment_method', 'warning',
  'Sale/payment cash-flow records should record payment_method: cash, venmo, zelle, card, etc.'
FROM cash_flows cf
WHERE cf.txn_type='Payment' AND cf.category='Sale' AND cf.payment_method IS NULL

UNION ALL
SELECT
  'cash_flow', cf.cf_record_id, cf.inventory_group_id,
  'sale_payment_missing_paid_to', 'warning',
  'Sale/payment cash-flow records should record who received the money.'
FROM cash_flows cf
WHERE cf.txn_type='Payment' AND cf.category='Sale' AND cf.paid_to IS NULL;

CREATE OR REPLACE VIEW furniture_db_guardrail_summary AS
SELECT anomaly_type, severity, count(*) AS anomaly_count
FROM furniture_db_guardrail_anomalies
GROUP BY anomaly_type, severity
ORDER BY CASE severity WHEN 'error' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END, anomaly_count DESC, anomaly_type;
