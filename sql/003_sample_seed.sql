-- Synthetic sample data for the AI-assisted furniture operations system

INSERT INTO contacts (display_name, contact_type, phone, email, notes) VALUES
  ('Alex Partner', 'partner', NULL, 'alex@example.invalid', 'Synthetic partner contact'),
  ('Casey Partner', 'partner', NULL, 'casey@example.invalid', 'Synthetic partner contact'),
  ('Morgan Buyer', 'buyer', '555-0101', NULL, 'Synthetic buyer'),
  ('Riley Mover', 'contractor', '555-0102', NULL, 'Synthetic delivery helper')
ON CONFLICT DO NOTHING;

INSERT INTO contact_roles (contact_id, role)
SELECT contact_id, role
FROM contacts
CROSS JOIN LATERAL (
  SELECT unnest(CASE
    WHEN contact_type='partner' THEN ARRAY['partner','payer','payee']
    WHEN contact_type='buyer' THEN ARRAY['buyer']
    WHEN contact_type='contractor' THEN ARRAY['contractor','delivery_helper']
    ELSE ARRAY['other']
  END) AS role
) roles
ON CONFLICT DO NOTHING;

INSERT INTO inventory_groups (inventory_group_id, group_type, acquisition_date, total_acquisition_cost, cost_allocation_method, notes) VALUES
  ('INV-0001', 'standalone', '2026-01-01', 300.00, 'not_allocated', 'Standalone synthetic item'),
  ('INV-0002', 'standalone', '2026-01-03', 0.00, 'not_allocated', 'Free synthetic item'),
  ('GROUP-0003', 'set', '2026-01-05', 500.00, 'manual', 'Synthetic set with allocated children')
ON CONFLICT DO NOTHING;

INSERT INTO inventory (inventory_uid, inventory_id, inventory_group_id, item_id, cl_url, item_title, category, brand, date_acquired, list_price_target, cost, acquisition_cost, status, status_updated_at, cost_basis_source, cost_allocation_method, allocated_cost, expected_sale_price, listed_at, pending_at, sold_at, note) VALUES
  ('INV-0001', 'INV-0001', 'INV-0001', 'CL-SAMPLE-001', 'https://example.invalid/listing/001', 'Solid wood media cabinet', 'Cabinet', 'Example Brand', '2026-01-01', 1200.00, 300.00, 300.00, 'pending_sale', now(), 'direct_or_imported', 'not_allocated', NULL, 1100.00, now() - interval '5 days', now(), NULL, 'Synthetic pending sale with deposit'),
  ('INV-0002', 'INV-0002', 'INV-0002', NULL, NULL, 'Free accent chair', 'Chair', NULL, '2026-01-03', 150.00, 0.00, 0.00, 'acquired_unlisted', now(), 'free', 'not_allocated', NULL, NULL, NULL, NULL, NULL, 'Synthetic free item'),
  ('INV-0003-A', 'INV-0003-A', 'GROUP-0003', 'CL-SAMPLE-003A', 'https://example.invalid/listing/003a', 'Dining table from set', 'Dining Room Set', 'Example Maker', '2026-01-05', 900.00, NULL, NULL, 'listed_active', now(), 'bundle_child', 'manual', 300.00, NULL, now() - interval '2 days', NULL, NULL, 'Synthetic child item'),
  ('INV-0003-B', 'INV-0003-B', 'GROUP-0003', 'CL-SAMPLE-003B', 'https://example.invalid/listing/003b', 'Six chairs from set', 'Chair', 'Example Maker', '2026-01-05', 700.00, NULL, NULL, 'listed_active', now(), 'bundle_child', 'manual', 200.00, NULL, now() - interval '2 days', NULL, NULL, 'Synthetic child item')
ON CONFLICT DO NOTHING;

INSERT INTO inventory_status_history (inventory_uid, inventory_group_id, from_status, to_status, changed_at, changed_by, reason, notes) VALUES
  ('INV-0001', 'INV-0001', NULL, 'listed_active', now() - interval '5 days', 'agent', 'initial_listing', 'Synthetic status event'),
  ('INV-0001', 'INV-0001', 'listed_active', 'pending_sale', now(), 'agent', 'deposit_received', 'Synthetic deposit moved item to pending'),
  ('INV-0002', 'INV-0002', NULL, 'acquired_unlisted', now(), 'agent', 'acquired', 'Synthetic status event'),
  ('INV-0003-A', 'GROUP-0003', NULL, 'listed_active', now() - interval '2 days', 'agent', 'listed', 'Synthetic status event'),
  ('INV-0003-B', 'GROUP-0003', NULL, 'listed_active', now() - interval '2 days', 'agent', 'listed', 'Synthetic status event');

INSERT INTO listings (inventory_uid, inventory_group_id, platform, external_listing_id, listing_url, title, status, listed_at, current_asking_price) VALUES
  ('INV-0001', 'INV-0001', 'craigslist', 'CL-SAMPLE-001', 'https://example.invalid/listing/001', 'Solid wood media cabinet', 'pending', now() - interval '5 days', 1200.00),
  ('INV-0003-A', 'GROUP-0003', 'craigslist', 'CL-SAMPLE-003A', 'https://example.invalid/listing/003a', 'Dining table from set', 'active', now() - interval '2 days', 900.00),
  ('INV-0003-B', 'GROUP-0003', 'craigslist', 'CL-SAMPLE-003B', 'https://example.invalid/listing/003b', 'Six chairs from set', 'active', now() - interval '2 days', 700.00);

INSERT INTO listing_price_history (listing_id, price, changed_at, reason)
SELECT listing_id, current_asking_price, listed_at, 'initial_price'
FROM listings;

INSERT INTO cash_flows (cf_record_id, inventory_uid, inventory_group_id, contact_id, txn_type, txn_date, vendor_or_description, amount, category, purpose, notes, paid_by, paid_to, payment_method, payment_stage) VALUES
  ('CF-0001', 'INV-0001', 'INV-0001', NULL, 'Expense', '2026-01-01', 'Acquisition cost', 300.00, 'COGS - Inventory', 'Buy Inventory', 'Synthetic purchase', 'Alex Partner', NULL, 'cash', 'inventory_purchase'),
  ('CF-0002', 'INV-0001', 'INV-0001', (SELECT contact_id FROM contacts WHERE display_name='Morgan Buyer'), 'Payment', '2026-01-06', 'Deposit for media cabinet', 200.00, 'Sale', 'Sell Inventory', 'Synthetic deposit by buyer', NULL, 'Casey Partner', 'venmo', 'deposit'),
  ('CF-0003', 'INV-0003-A', 'GROUP-0003', NULL, 'Expense', '2026-01-05', 'Allocated set acquisition cost', 300.00, 'COGS - Inventory', 'Buy Inventory', 'Synthetic allocation', 'Casey Partner', NULL, 'cash', 'inventory_purchase'),
  ('CF-0004', 'INV-0003-B', 'GROUP-0003', NULL, 'Expense', '2026-01-05', 'Allocated set acquisition cost', 200.00, 'COGS - Inventory', 'Buy Inventory', 'Synthetic allocation', 'Casey Partner', NULL, 'cash', 'inventory_purchase');

INSERT INTO pickups_deliveries (movement_type, inventory_uid, inventory_group_id, contact_id, counterparty_name, counterparty_contact, location_address, scheduled_start, scheduled_end, movement_status, assigned_to, deposit_received, notes) VALUES
  ('buyer_pickup', 'INV-0001', 'INV-0001', (SELECT contact_id FROM contacts WHERE display_name='Morgan Buyer'), 'Morgan Buyer', '555-0101', 'Synthetic address', now() + interval '2 days', now() + interval '2 days 2 hours', 'confirmed', 'Riley Mover', 200.00, 'Synthetic buyer pickup');

-- Synthetic agent action audit rows.
-- These examples demonstrate the public-safe governance pattern: enough detail
-- to replicate the action, capped/sanitized input excerpts, summarized
-- guardrail state, and explicit outcomes. They intentionally do not contain real
-- chat text, customer data, receipt images, credentials, or private SQL values.
INSERT INTO agent_action_log (
  skill_name,
  agent_identifier,
  prompt_version,
  chat_input_excerpt,
  operation_summary,
  sql_emitted,
  guardrails_before,
  guardrails_after,
  entity_type,
  entity_id,
  status,
  human_feedback,
  created_at
) VALUES
  (
    'expense-receipt-capture',
    'lex-public-reference',
    'receipt-capture-v1',
    'Synthetic request: log an example acquisition receipt for INV-0001.',
    'Created synthetic expense cash_flow CF-0001 and linked it to inventory item INV-0001.',
    'INSERT INTO cash_flows (...) VALUES (... synthetic public-safe values ...)',
    '{"error": 0, "warning": 0}'::jsonb,
    '{"error": 0, "warning": 0}'::jsonb,
    'cash_flow',
    'CF-0001',
    'success',
    'Public seed demonstrates sanitized receipt logging; real receipts stay out of this repo.',
    now() - interval '3 days'
  ),
  (
    'furniture-listing-price-sync',
    'lex-public-reference',
    'listing-sync-v1',
    'Synthetic request: preview a markdown for CL-SAMPLE-003A.',
    'Previewed listing price update for listing CL-SAMPLE-003A without writing because human confirmation was required.',
    NULL,
    '{"error": 0, "warning": 0}'::jsonb,
    '{"error": 0, "warning": 0}'::jsonb,
    'listing',
    'CL-SAMPLE-003A',
    'preview_only',
    'Preview-first behavior is required before public/external listing changes.',
    now() - interval '2 days'
  ),
  (
    'furniture-status-guardrails',
    'lex-public-reference',
    'status-guardrails-v1',
    'Synthetic request: mark a listed item sold without sale payment evidence.',
    'Blocked status transition because guardrails require sold_at and sale cash-flow evidence before sold_delivered.',
    NULL,
    '{"error": 0, "warning": 1}'::jsonb,
    '{"error": 2, "warning": 1, "anomalies": ["sold_delivered_missing_sale_date", "sold_delivered_without_sale_cashflow"]}'::jsonb,
    'inventory',
    'SYNTHETIC-BLOCKED-SALE',
    'blocked_by_guardrail',
    'Reviewer feedback: never infer completed sale from ambiguous notes; require payment/date evidence or leave pending review.',
    now() - interval '1 day'
  )
ON CONFLICT DO NOTHING;
