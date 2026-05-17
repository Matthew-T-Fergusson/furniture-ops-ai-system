-- Guardrail views for AI-assisted database writes

CREATE OR REPLACE VIEW furniture_db_guardrail_anomalies AS
WITH group_cost AS (
  SELECT
    g.inventory_group_id,
    g.group_type,
    g.total_acquisition_cost,
    g.cost_allocation_method,
    sum(coalesce(i.allocated_cost,0)) AS allocated_cost_sum,
    count(i.*) AS item_count
  FROM inventory_groups g
  LEFT JOIN inventory i ON i.inventory_group_id = g.inventory_group_id
  GROUP BY g.inventory_group_id, g.group_type, g.total_acquisition_cost, g.cost_allocation_method
), sale_cf AS (
  SELECT
    inventory_uid,
    inventory_group_id,
    count(*) FILTER (WHERE txn_type='Payment' AND category='Sale') AS sale_payment_count,
    count(*) FILTER (WHERE txn_type='Payment' AND category='Sale' AND payment_stage='deposit') AS deposit_count,
    count(*) FILTER (WHERE txn_type='Payment' AND category='Sale' AND payment_stage IN ('final_payment','final_or_full_payment')) AS final_payment_count
  FROM cash_flows
  GROUP BY inventory_uid, inventory_group_id
), movement AS (
  SELECT
    inventory_uid,
    inventory_group_id,
    count(*) FILTER (WHERE movement_type IN ('buyer_pickup','seller_delivery','contractor_delivery')) AS buyer_movement_count,
    count(*) FILTER (WHERE movement_type IN ('buyer_pickup','seller_delivery','contractor_delivery') AND movement_status IN ('planned','confirmed','rescheduled')) AS open_movement_count,
    count(*) FILTER (WHERE movement_type IN ('buyer_pickup','seller_delivery','contractor_delivery') AND movement_status='completed') AS completed_movement_count,
    count(*) FILTER (WHERE movement_type IN ('buyer_pickup','seller_delivery','contractor_delivery') AND NULLIF(btrim(coalesce(counterparty_name,'')), '') IS NOT NULL) AS movement_with_customer_count,
    count(*) FILTER (WHERE movement_type IN ('buyer_pickup','seller_delivery','contractor_delivery') AND NULLIF(btrim(coalesce(location_address,'')), '') IS NOT NULL) AS movement_with_address_count,
    count(*) FILTER (WHERE movement_type IN ('buyer_pickup','seller_delivery','contractor_delivery') AND calendar_event_id IS NOT NULL) AS movement_with_calendar_count
  FROM pickups_deliveries
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
  'sold_flag_status_mismatch', 'error',
  'inventory.sold is a Y/N supplement to inventory.status and must align: sold=true only for sold_delivered; all other statuses sold=false.'
FROM inventory i
WHERE (i.status = 'sold_delivered' AND i.sold IS DISTINCT FROM true)
   OR (coalesce(i.status,'') <> 'sold_delivered' AND i.sold IS DISTINCT FROM false)

UNION ALL
SELECT
  'inventory', i.inventory_uid, i.inventory_group_id,
  'pending_sale_without_deposit_cashflow', 'warning',
  'pending_sale should normally start once a deposit exists; ask for amount, method, paid-to party, buyer, price, delivery fee, balance owed, and pickup/delivery timeline.'
FROM inventory i
LEFT JOIN sale_cf cf ON cf.inventory_uid = i.inventory_uid OR (cf.inventory_uid IS NULL AND cf.inventory_group_id = i.inventory_group_id)
WHERE i.status = 'pending_sale'
  AND coalesce(cf.deposit_count,0) = 0

UNION ALL
SELECT
  'inventory', i.inventory_uid, i.inventory_group_id,
  'pending_sale_missing_reserved_until', 'warning',
  'Pending sale has no reserved_until/hold deadline. This is a reminder only; ask for buyer deadline when useful.'
FROM inventory i
WHERE i.status = 'pending_sale'
  AND i.reserved_until IS NULL

UNION ALL
SELECT
  'inventory', i.inventory_uid, i.inventory_group_id,
  'pending_sale_missing_pickup_delivery_record', 'warning',
  'Pending sale has deposit/payment evidence but no buyer pickup/delivery row. Scheduling details may arrive later.'
FROM inventory i
LEFT JOIN sale_cf cf ON cf.inventory_uid = i.inventory_uid OR (cf.inventory_uid IS NULL AND cf.inventory_group_id = i.inventory_group_id)
LEFT JOIN movement m ON m.inventory_uid = i.inventory_uid OR (m.inventory_uid IS NULL AND m.inventory_group_id = i.inventory_group_id)
WHERE i.status = 'pending_sale'
  AND coalesce(cf.sale_payment_count,0) > 0
  AND coalesce(m.buyer_movement_count,0) = 0

UNION ALL
SELECT
  'inventory', i.inventory_uid, i.inventory_group_id,
  'pending_sale_movement_missing_customer_or_address', 'warning',
  'Pending sale has pickup/delivery row but is missing customer name and/or address.'
FROM inventory i
JOIN movement m ON m.inventory_uid = i.inventory_uid OR (m.inventory_uid IS NULL AND m.inventory_group_id = i.inventory_group_id)
WHERE i.status = 'pending_sale'
  AND coalesce(m.buyer_movement_count,0) > 0
  AND (coalesce(m.movement_with_customer_count,0) = 0 OR coalesce(m.movement_with_address_count,0) = 0)

UNION ALL
SELECT
  'inventory', i.inventory_uid, i.inventory_group_id,
  'pending_sale_movement_missing_calendar_event', 'warning',
  'Pending sale has scheduled pickup/delivery but no calendar_event_id.'
FROM inventory i
JOIN movement m ON m.inventory_uid = i.inventory_uid OR (m.inventory_uid IS NULL AND m.inventory_group_id = i.inventory_group_id)
WHERE i.status = 'pending_sale'
  AND coalesce(m.open_movement_count,0) > 0
  AND coalesce(m.movement_with_calendar_count,0) = 0

UNION ALL
SELECT
  'inventory', i.inventory_uid, i.inventory_group_id,
  'pending_sale_final_payment_recorded', 'warning',
  'Final/full sale payment exists while item remains pending_sale. Confirm whether pickup/delivery is still open or item should move to sold_delivered.'
FROM inventory i
LEFT JOIN sale_cf cf ON cf.inventory_uid = i.inventory_uid OR (cf.inventory_uid IS NULL AND cf.inventory_group_id = i.inventory_group_id)
WHERE i.status = 'pending_sale'
  AND coalesce(cf.final_payment_count,0) > 0

UNION ALL
SELECT
  'inventory', i.inventory_uid, i.inventory_group_id,
  'pending_sale_completed_movement', 'warning',
  'Pickup/delivery is marked completed while item remains pending_sale. Confirm final payment/status.'
FROM inventory i
JOIN movement m ON m.inventory_uid = i.inventory_uid OR (m.inventory_uid IS NULL AND m.inventory_group_id = i.inventory_group_id)
WHERE i.status = 'pending_sale'
  AND coalesce(m.completed_movement_count,0) > 0

UNION ALL
SELECT
  'inventory', i.inventory_uid, i.inventory_group_id,
  'pending_sale_missing_balance_note', 'warning',
  'Pending-sale notes should include price + delivery fee = total owed and balance owed when known.'
FROM inventory i
WHERE i.status = 'pending_sale'
  AND NOT (coalesce(i.note,'') ~* 'balance owed|total owed|delivery fee|deposit')

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
  'Zero-cost inventory must declare cost_basis_source such as free, gifted, split_child_zero_cogs, bundle_child_zero_cogs, parent_absorbed, or unknown_needs_review.'
FROM inventory i
WHERE coalesce(i.acquisition_cost, i.cost, 0) = 0
  AND NULLIF(btrim(coalesce(i.cost_basis_source,'')), '') IS NULL

UNION ALL
SELECT
  'inventory_group', gc.inventory_group_id, gc.inventory_group_id,
  'group_allocated_cost_mismatch', 'error',
  'For proportional/manual allocation groups, sum(child allocated_cost) should equal inventory_groups.total_acquisition_cost. Parent-absorbed / child-zero-COGS groups are intentionally exempt.'
FROM group_cost gc
WHERE gc.item_count > 1
  AND coalesce(gc.cost_allocation_method,'') NOT IN ('zero_child','parent_absorbed','split_child_zero_cogs','bundle_child_zero_cogs')
  AND gc.total_acquisition_cost IS NOT NULL
  AND abs(coalesce(gc.allocated_cost_sum,0) - gc.total_acquisition_cost) > 0.01

UNION ALL
SELECT
  'cash_flow', cf.cf_record_id, cf.inventory_group_id,
  'sale_payment_missing_payment_method', 'warning',
  'Sale/payment cash-flow records should record payment_method when known.'
FROM cash_flows cf
WHERE cf.txn_type='Payment' AND cf.category='Sale' AND cf.payment_method IS NULL

UNION ALL
SELECT
  'cash_flow', cf.cf_record_id, cf.inventory_group_id,
  'sale_payment_missing_paid_to', 'warning',
  'Sale/payment cash-flow records should record who receives partner/accounting credit.'
FROM cash_flows cf
WHERE cf.txn_type='Payment' AND cf.category='Sale' AND cf.paid_to IS NULL;

CREATE OR REPLACE VIEW furniture_db_guardrail_summary AS
SELECT anomaly_type, severity, count(*) AS anomaly_count
FROM furniture_db_guardrail_anomalies
GROUP BY anomaly_type, severity
ORDER BY CASE severity WHEN 'error' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END, anomaly_count DESC, anomaly_type;
