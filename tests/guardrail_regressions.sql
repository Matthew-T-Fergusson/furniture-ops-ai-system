-- Guardrail regression tests for Furniture Ops AI POC.
-- Synthetic-only fixtures. Runs inside one transaction and rolls back.

\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION assert_guardrail(
  expected_entity_type text,
  expected_entity_id text,
  expected_anomaly_type text,
  expected_severity text
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM furniture_db_guardrail_anomalies
    WHERE entity_type = expected_entity_type
      AND entity_id = expected_entity_id
      AND anomaly_type = expected_anomaly_type
      AND severity = expected_severity
  ) THEN
    RAISE EXCEPTION 'Expected guardrail not found: entity_type=%, entity_id=%, anomaly_type=%, severity=%',
      expected_entity_type, expected_entity_id, expected_anomaly_type, expected_severity;
  END IF;
END;
$$;

-- 1) Listing identity: active listings need real listing ID and URL.
INSERT INTO inventory_groups (inventory_group_id, group_type, total_acquisition_cost, cost_allocation_method)
VALUES ('T-LIST-G', 'standalone', 25.00, 'not_allocated');
INSERT INTO inventory (inventory_uid, inventory_group_id, item_title, cost, acquisition_cost, status, sold, cost_basis_source)
VALUES ('T-LIST-1', 'T-LIST-G', 'Synthetic missing listing identity', 25.00, 25.00, 'listed_active', false, 'direct_or_imported');
SELECT assert_guardrail('inventory', 'T-LIST-1', 'listed_status_missing_listing_identity', 'error');

-- 2) Pending sale: should surface missing deposit and missing reserved-until warnings.
INSERT INTO inventory_groups (inventory_group_id, group_type, total_acquisition_cost, cost_allocation_method)
VALUES ('T-PENDING-G', 'standalone', 40.00, 'not_allocated');
INSERT INTO inventory (inventory_uid, inventory_group_id, item_id, cl_url, item_title, cost, acquisition_cost, status, sold, cost_basis_source, note)
VALUES ('T-PENDING-1', 'T-PENDING-G', 'CL-T-PENDING-1', 'https://example.invalid/t-pending-1', 'Synthetic pending missing deposit', 40.00, 40.00, 'pending_sale', false, 'direct_or_imported', 'Synthetic pending sale without deposit details');
SELECT assert_guardrail('inventory', 'T-PENDING-1', 'pending_sale_without_deposit_cashflow', 'warning');
SELECT assert_guardrail('inventory', 'T-PENDING-1', 'pending_sale_missing_reserved_until', 'warning');

-- 3) Sold delivered completeness: requires sold_at and sale cash-flow evidence.
INSERT INTO inventory_groups (inventory_group_id, group_type, total_acquisition_cost, cost_allocation_method)
VALUES ('T-SOLD-G', 'standalone', 55.00, 'not_allocated');
INSERT INTO inventory (inventory_uid, inventory_group_id, item_id, cl_url, item_title, cost, acquisition_cost, status, sold, cost_basis_source)
VALUES ('T-SOLD-1', 'T-SOLD-G', 'CL-T-SOLD-1', 'https://example.invalid/t-sold-1', 'Synthetic sold incomplete', 55.00, 55.00, 'sold_delivered', true, 'direct_or_imported');
SELECT assert_guardrail('inventory', 'T-SOLD-1', 'sold_delivered_missing_sale_date', 'error');
SELECT assert_guardrail('inventory', 'T-SOLD-1', 'sold_delivered_without_sale_cashflow', 'error');

-- 4) Zero-cost basis: free/zero-cost inventory needs explicit cost_basis_source.
INSERT INTO inventory_groups (inventory_group_id, group_type, total_acquisition_cost, cost_allocation_method)
VALUES ('T-ZERO-G', 'standalone', 0.00, 'not_allocated');
INSERT INTO inventory (inventory_uid, inventory_group_id, item_title, cost, acquisition_cost, status, sold)
VALUES ('T-ZERO-1', 'T-ZERO-G', 'Synthetic zero cost missing basis', 0.00, 0.00, 'acquired_unlisted', false);
SELECT assert_guardrail('inventory', 'T-ZERO-1', 'zero_cost_missing_cost_basis_source', 'error');

-- 5) Group allocation: manual child allocation must sum to group total.
INSERT INTO inventory_groups (inventory_group_id, group_type, total_acquisition_cost, cost_allocation_method)
VALUES ('T-GROUP-G', 'set', 100.00, 'manual');
INSERT INTO inventory (inventory_uid, inventory_group_id, item_id, cl_url, item_title, status, sold, cost_basis_source, cost_allocation_method, allocated_cost)
VALUES
  ('T-GROUP-A', 'T-GROUP-G', 'CL-T-GROUP-A', 'https://example.invalid/t-group-a', 'Synthetic group child A', 'listed_active', false, 'bundle_child', 'manual', 60.00),
  ('T-GROUP-B', 'T-GROUP-G', 'CL-T-GROUP-B', 'https://example.invalid/t-group-b', 'Synthetic group child B', 'listed_active', false, 'bundle_child', 'manual', 30.00);
SELECT assert_guardrail('inventory_group', 'T-GROUP-G', 'group_allocated_cost_mismatch', 'error');

-- 6) Sold/status alignment: sold=true only for sold_delivered.
INSERT INTO inventory_groups (inventory_group_id, group_type, total_acquisition_cost, cost_allocation_method)
VALUES ('T-SOLD-FLAG-G', 'standalone', 65.00, 'not_allocated');
INSERT INTO inventory (inventory_uid, inventory_group_id, item_id, cl_url, item_title, cost, acquisition_cost, status, sold, cost_basis_source)
VALUES ('T-SOLD-FLAG-1', 'T-SOLD-FLAG-G', 'CL-T-SOLD-FLAG-1', 'https://example.invalid/t-sold-flag-1', 'Synthetic sold/status mismatch', 65.00, 65.00, 'listed_active', true, 'direct_or_imported');
SELECT assert_guardrail('inventory', 'T-SOLD-FLAG-1', 'sold_flag_status_mismatch', 'error');

ROLLBACK;
\echo 'guardrail_regressions: ok'
