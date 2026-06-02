-- Guardrail regression tests for the AI-assisted furniture operations system.
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

-- 7) Tax/reporting taxonomy: missing or review-needed classifications should
-- warn rather than block because business tax treatment can have gray areas.
INSERT INTO cash_flows (cf_record_id, txn_type, txn_date, vendor_or_description, amount, category, tax_category_code, purpose)
VALUES ('T-TAX-EXPENSE-1', 'Expense', current_date - interval '45 days', 'Synthetic uncategorized supplies', 22.00, 'Supplies', 'unknown_needs_review', 'Synthetic tax review test');
SELECT assert_guardrail('cash_flow', 'T-TAX-EXPENSE-1', 'expense_missing_tax_category', 'warning');

INSERT INTO cash_flows (cf_record_id, txn_type, txn_date, vendor_or_description, amount, category, purpose)
VALUES ('T-TAX-REVENUE-1', 'Payment', current_date, 'Synthetic sale missing revenue classification', 99.00, 'Sale', 'Synthetic revenue review test');
SELECT assert_guardrail('cash_flow', 'T-TAX-REVENUE-1', 'revenue_missing_tax_category', 'warning');

INSERT INTO cash_flows (cf_record_id, txn_type, txn_date, vendor_or_description, amount, category, tax_category_code, purpose)
VALUES ('T-TAX-MISMATCH-1', 'Payment', current_date, 'Synthetic sale with expense category', 88.00, 'Sale', 'inventory_cogs', 'Synthetic mismatch test');
SELECT assert_guardrail('cash_flow', 'T-TAX-MISMATCH-1', 'tax_category_kind_mismatch', 'warning');

-- 8) Agent audit trail: synthetic action log rows must round-trip through
-- the recent view with JSON guardrail snapshots and correction feedback.
INSERT INTO agent_action_log (
  skill_name,
  agent_identifier,
  prompt_version,
  chat_input_excerpt,
  operation_summary,
  guardrails_before,
  guardrails_after,
  entity_type,
  entity_id,
  status,
  human_feedback
) VALUES (
  'furniture-status-guardrails',
  'regression-test-agent',
  'test-v1',
  'Synthetic capped excerpt for action-log regression.',
  'Regression inserted a synthetic action-log row and verified recent-view visibility.',
  '{"error": 0, "warning": 0}'::jsonb,
  '{"error": 1, "warning": 0, "anomalies": ["sold_flag_status_mismatch"]}'::jsonb,
  'inventory',
  'T-SOLD-FLAG-1',
  'blocked_by_guardrail',
  'Synthetic reviewer correction: require guardrail evidence before status mutation.'
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM agent_action_log_recent
    WHERE skill_name = 'furniture-status-guardrails'
      AND entity_type = 'inventory'
      AND entity_id = 'T-SOLD-FLAG-1'
      AND status = 'blocked_by_guardrail'
      AND guardrails_after->>'error' = '1'
      AND human_feedback LIKE 'Synthetic reviewer correction:%'
  ) THEN
    RAISE EXCEPTION 'Expected agent_action_log_recent row not found or JSON/feedback did not round-trip';
  END IF;
END;
$$;


-- 9) Conversation queue regression: synthetic conversation-layer rows should
-- surface in the active queue with human-reviewed lead-quality fields. This
-- protects the public smoke test from silently loading the conversation schema
-- while failing to expose the operator review workflow.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM active_conversation_queue
    WHERE platform = 'craigslist_email'
      AND source_thread_id = 'sample-thread-001'
      AND needs_reply IS TRUE
      AND lead_quality_tag = 'actionable'
      AND latest_body_preview LIKE 'Is this still available%'
  ) THEN
    RAISE EXCEPTION 'Expected synthetic conversation queue row with lead-quality fields was not found';
  END IF;
END;
$$;

ROLLBACK;
\echo 'guardrail_regressions: ok'
