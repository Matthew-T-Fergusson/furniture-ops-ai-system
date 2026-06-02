-- Synthetic sample data for the AI-assisted furniture operations system

INSERT INTO tax_categories (tax_category_code, display_name, category_kind, schedule_c_hint, default_deductible, public_notes) VALUES
  ('inventory_cogs', 'Inventory cost of goods sold', 'expense', 'Cost of goods sold', true, 'Inventory purchases or allocated acquisition costs tied to resale items.'),
  ('labor_contract', 'Contract labor', 'expense', 'Contract labor', true, 'Mover, repair, refurb, or other non-employee labor.'),
  ('storage', 'Storage', 'expense', 'Rent or lease / storage expense', true, 'Storage unit, warehouse, or inventory holding costs.'),
  ('vehicle_fuel', 'Vehicle fuel', 'expense', 'Car and truck expenses', true, 'Fuel used for sourcing, pickup, delivery, or business errands.'),
  ('vehicle_mileage', 'Vehicle mileage', 'expense', 'Car and truck expenses', true, 'Mileage/trip allocation when using mileage-style tracking.'),
  ('supplies', 'Supplies', 'expense', 'Supplies', true, 'Packing, cleaning, repair, staging, or operational supplies.'),
  ('marketplace_fees', 'Marketplace and payment fees', 'expense', 'Commissions and fees', true, 'Marketplace, payment processor, listing, or platform fees.'),
  ('advertising', 'Advertising and promotion', 'expense', 'Advertising', true, 'Paid promotion, boosts, signs, or marketing.'),
  ('professional_services', 'Professional services', 'expense', 'Legal and professional services', true, 'Accounting, legal, consulting, or professional support.'),
  ('software', 'Software and subscriptions', 'expense', 'Other expenses / software', true, 'Tools, SaaS, hosting, or automation software.'),
  ('insurance', 'Insurance', 'expense', 'Insurance', true, 'Business insurance or liability coverage.'),
  ('taxes_licenses', 'Taxes and licenses', 'expense', 'Taxes and licenses', true, 'Business registration, permits, licenses, or non-income taxes.'),
  ('meals', 'Meals', 'expense', 'Meals', true, 'Business meal category; deductibility may require review/limits.'),
  ('bank_fees', 'Bank and finance fees', 'expense', 'Other expenses / bank fees', true, 'Bank, merchant, or finance charges.'),
  ('gross_sales_revenue', 'Gross sales revenue', 'revenue', 'Gross receipts or sales', false, 'Item sale proceeds before expenses or fees.'),
  ('delivery_revenue', 'Delivery revenue', 'revenue', 'Gross receipts or sales', false, 'Delivery fee income separated from item sale price when known.'),
  ('forfeited_deposit_revenue', 'Forfeited deposit revenue', 'revenue', 'Other income / gross receipts review', false, 'Deposit retained after cancelled sale; review treatment.'),
  ('refund_or_reversal', 'Refund or reversal', 'contra_revenue', 'Returns and allowances / expense offset review', false, 'Refunds, reversals, or negative adjustments requiring review.'),
  ('owner_contribution', 'Owner contribution / capital movement', 'non_tax', 'Balance sheet / owner contribution review', false, 'Partner/owner funding or non-income capital movement.'),
  ('not_deductible', 'Not deductible / non-business', 'non_tax', 'Not deductible', false, 'Known non-deductible or non-business item.'),
  ('other_expense', 'Other business expense', 'expense', 'Other expenses', true, 'Fallback for deductible business expense that does not fit a clearer public category.'),
  ('unknown_needs_review', 'Unknown / needs review', 'review', 'Needs review', false, 'Use when tax/reporting category is ambiguous; should surface as warning, not blocker.')
ON CONFLICT (tax_category_code) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  category_kind = EXCLUDED.category_kind,
  schedule_c_hint = EXCLUDED.schedule_c_hint,
  default_deductible = EXCLUDED.default_deductible,
  public_notes = EXCLUDED.public_notes,
  active = true,
  updated_at = now();

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
  ('INV-0004', 'standalone', '2026-01-04', 125.00, 'not_allocated', 'Synthetic disposed/write-off item'),
  ('GROUP-0003', 'set', '2026-01-05', 500.00, 'manual', 'Synthetic set with allocated children')
ON CONFLICT DO NOTHING;

INSERT INTO inventory (inventory_uid, inventory_id, inventory_group_id, item_id, cl_url, item_title, category, brand, date_acquired, list_price_target, cost, acquisition_cost, status, status_updated_at, cost_basis_source, cost_allocation_method, allocated_cost, expected_sale_price, listed_at, pending_at, sold_at, note) VALUES
  ('INV-0001', 'INV-0001', 'INV-0001', 'CL-SAMPLE-001', 'https://example.invalid/listing/001', 'Solid wood media cabinet', 'Cabinet', 'Example Brand', '2026-01-01', 1200.00, 300.00, 300.00, 'pending_sale', now(), 'direct_or_imported', 'not_allocated', NULL, 1100.00, now() - interval '5 days', now(), NULL, 'Synthetic pending sale with deposit'),
  ('INV-0002', 'INV-0002', 'INV-0002', NULL, NULL, 'Free accent chair', 'Chair', NULL, '2026-01-03', 150.00, 0.00, 0.00, 'acquired_unlisted', now(), 'free', 'not_allocated', NULL, NULL, NULL, NULL, NULL, 'Synthetic free item'),
  ('INV-0004', 'INV-0004', 'INV-0004', NULL, NULL, 'Damaged synthetic side table', 'Table', NULL, '2026-01-04', 175.00, 125.00, 125.00, 'disposed', now(), 'direct_or_imported', 'not_allocated', NULL, NULL, NULL, NULL, NULL, 'Synthetic disposed item used to prove zero-revenue inventory write-off reporting'),
  ('INV-0003-A', 'INV-0003-A', 'GROUP-0003', 'CL-SAMPLE-003A', 'https://example.invalid/listing/003a', 'Dining table from set', 'Dining Room Set', 'Example Maker', '2026-01-05', 900.00, NULL, NULL, 'listed_active', now(), 'bundle_child', 'manual', 300.00, NULL, now() - interval '2 days', NULL, NULL, 'Synthetic child item'),
  ('INV-0003-B', 'INV-0003-B', 'GROUP-0003', 'CL-SAMPLE-003B', 'https://example.invalid/listing/003b', 'Six chairs from set', 'Chair', 'Example Maker', '2026-01-05', 700.00, NULL, NULL, 'listed_active', now(), 'bundle_child', 'manual', 200.00, NULL, now() - interval '2 days', NULL, NULL, 'Synthetic child item')
ON CONFLICT DO NOTHING;

INSERT INTO inventory_status_history (inventory_uid, inventory_group_id, from_status, to_status, changed_at, changed_by, reason, notes) VALUES
  ('INV-0001', 'INV-0001', NULL, 'listed_active', now() - interval '5 days', 'agent', 'initial_listing', 'Synthetic status event'),
  ('INV-0001', 'INV-0001', 'listed_active', 'pending_sale', now(), 'agent', 'deposit_received', 'Synthetic deposit moved item to pending'),
  ('INV-0002', 'INV-0002', NULL, 'acquired_unlisted', now(), 'agent', 'acquired', 'Synthetic status event'),
  ('INV-0004', 'INV-0004', NULL, 'disposed', now(), 'agent', 'damaged_beyond_sale', 'Synthetic disposed/write-off status event'),
  ('INV-0003-A', 'GROUP-0003', NULL, 'listed_active', now() - interval '2 days', 'agent', 'listed', 'Synthetic status event'),
  ('INV-0003-B', 'GROUP-0003', NULL, 'listed_active', now() - interval '2 days', 'agent', 'listed', 'Synthetic status event');

INSERT INTO listings (inventory_uid, inventory_group_id, platform, external_listing_id, listing_url, title, status, listed_at, current_asking_price) VALUES
  ('INV-0001', 'INV-0001', 'craigslist', 'CL-SAMPLE-001', 'https://example.invalid/listing/001', 'Solid wood media cabinet', 'pending', now() - interval '5 days', 1200.00),
  ('INV-0003-A', 'GROUP-0003', 'craigslist', 'CL-SAMPLE-003A', 'https://example.invalid/listing/003a', 'Dining table from set', 'active', now() - interval '2 days', 900.00),
  ('INV-0003-B', 'GROUP-0003', 'craigslist', 'CL-SAMPLE-003B', 'https://example.invalid/listing/003b', 'Six chairs from set', 'active', now() - interval '2 days', 700.00);

INSERT INTO listing_price_history (listing_id, price, changed_at, reason)
SELECT listing_id, current_asking_price, listed_at, 'initial_price'
FROM listings;

INSERT INTO cash_flows (cf_record_id, inventory_uid, inventory_group_id, contact_id, txn_type, txn_date, vendor_or_description, amount, category, tax_category_code, tax_treatment_notes, purpose, notes, paid_by, paid_to, payment_method, payment_stage) VALUES
  ('CF-0001', 'INV-0001', 'INV-0001', NULL, 'Expense', '2026-01-01', 'Acquisition cost', 300.00, 'COGS - Inventory', 'inventory_cogs', 'Synthetic inventory purchase categorized for COGS reporting.', 'Buy Inventory', 'Synthetic purchase', 'Alex Partner', NULL, 'cash', 'inventory_purchase'),
  ('CF-0002', 'INV-0001', 'INV-0001', (SELECT contact_id FROM contacts WHERE display_name='Morgan Buyer'), 'Payment', '2026-01-06', 'Deposit for media cabinet', 200.00, 'Sale', 'gross_sales_revenue', 'Synthetic customer deposit classified as sale revenue for public reporting example.', 'Sell Inventory', 'Synthetic deposit by buyer', NULL, 'Casey Partner', 'venmo', 'deposit'),
  ('CF-0003', 'INV-0003-A', 'GROUP-0003', NULL, 'Expense', '2026-01-05', 'Allocated set acquisition cost', 300.00, 'COGS - Inventory', 'inventory_cogs', 'Synthetic allocated COGS for child item.', 'Buy Inventory', 'Synthetic allocation', 'Casey Partner', NULL, 'cash', 'inventory_purchase'),
  ('CF-0004', 'INV-0003-B', 'GROUP-0003', NULL, 'Expense', '2026-01-05', 'Allocated set acquisition cost', 200.00, 'COGS - Inventory', 'inventory_cogs', 'Synthetic allocated COGS for child item.', 'Buy Inventory', 'Synthetic allocation', 'Casey Partner', NULL, 'cash', 'inventory_purchase');

INSERT INTO pickups_deliveries (movement_type, inventory_uid, inventory_group_id, contact_id, counterparty_name, counterparty_contact, location_address, scheduled_start, scheduled_end, movement_status, assigned_to, deposit_received, notes) VALUES
  ('buyer_pickup', 'INV-0001', 'INV-0001', (SELECT contact_id FROM contacts WHERE display_name='Morgan Buyer'), 'Morgan Buyer', '555-0101', 'Synthetic address', now() + interval '2 days', now() + interval '2 days 2 hours', 'confirmed', 'Riley Mover', 200.00, 'Synthetic buyer pickup');

DO $feature_seed$
BEGIN
  IF to_regclass('public.listing_scrape_runs') IS NOT NULL
     AND to_regclass('public.conversation_threads') IS NOT NULL THEN
    -- Synthetic marketplace syndication and conversation-layer rows. These are
    -- public-safe examples that exercise the feature migrations without using real
    -- marketplace messages, customer identities, raw captures, or private files.
    INSERT INTO listing_scrape_runs (
      scrape_run_id,
      run_started_at,
      run_finished_at,
      status,
      requested_limit,
      delay_min_seconds,
      delay_max_seconds,
      download_images,
      apply_changes,
      processed_count,
      success_count,
      error_count,
      captcha_count,
      report_path,
      notes
    ) VALUES (
      '11111111-1111-4111-8111-111111111111',
      now() - interval '6 hours',
      now() - interval '5 hours 45 minutes',
      'completed',
      3,
      3.00,
      7.00,
      false,
      false,
      3,
      2,
      1,
      0,
      'local_data/sample_reports/listing_scrape_run.json',
      'Synthetic scrape run for public smoke testing.'
    )
    ON CONFLICT (scrape_run_id) DO NOTHING;

    INSERT INTO listing_events (listing_id, inventory_uid, event_type, event_at, new_status, new_price, source_system, actor, notes, scrape_run_id)
    SELECT listing_id, inventory_uid, 'scraped', now() - interval '5 hours 50 minutes', status, current_asking_price, 'synthetic_seed', 'lex-public-reference', 'Synthetic listing scrape event.', '11111111-1111-4111-8111-111111111111'
    FROM listings
    WHERE external_listing_id = 'CL-SAMPLE-001';

    INSERT INTO listing_content_snapshots (listing_id, inventory_uid, platform, external_listing_id, listing_url, scraped_at, title, description, price, location_text, content_hash, source_status, source_system, scrape_run_id)
    SELECT listing_id, inventory_uid, platform, external_listing_id, listing_url, now() - interval '5 hours 50 minutes', title, 'Synthetic public-safe listing description.', current_asking_price, 'Example City', 'synthetic-content-hash-001', status, 'synthetic_seed', '11111111-1111-4111-8111-111111111111'
    FROM listings
    WHERE external_listing_id = 'CL-SAMPLE-001';

    INSERT INTO listing_media_assets (inventory_uid, listing_id, platform, source_url, local_path, source_quality, media_type, sort_order, sha256, perceptual_hash, width_px, height_px, scrape_run_id, notes)
    SELECT inventory_uid, listing_id, platform, 'https://example.invalid/media/001.jpg', 'local_data/sample_media/001.jpg', 'craigslist_low_res', 'image', 1, repeat('a',64), 'phash-synthetic-001', 800, 600, '11111111-1111-4111-8111-111111111111', 'Synthetic media row.'
    FROM listings
    WHERE external_listing_id = 'CL-SAMPLE-001';

    INSERT INTO listing_price_quotes (inventory_uid, platform, market_region, base_price, delivery_adjustment, platform_fee_adjustment, markup_adjustment, recommended_price, target_margin_pct, approved_by, approved_at, used_for_listing_id, notes)
    SELECT inventory_uid, 'craigslist', 'example-region', current_asking_price, 0, 0, 0, current_asking_price, 0.50, 'Alex Partner', now() - interval '4 hours', listing_id, 'Synthetic approved listing price quote.'
    FROM listings
    WHERE external_listing_id = 'CL-SAMPLE-001';

    INSERT INTO listing_publication_queue (inventory_uid, platform, market_region, desired_action, status, priority, source_listing_id, price_quote_id, assigned_to, due_at, result_listing_id, notes)
    SELECT l.inventory_uid, 'facebook_marketplace', 'example-region', 'create_listing', 'manual_required', 2, l.listing_id, q.quote_id, 'Casey Partner', now() + interval '1 day', NULL, 'Synthetic cross-post queue row requiring manual review.'
    FROM listings l
    JOIN listing_price_quotes q ON q.used_for_listing_id = l.listing_id
    WHERE l.external_listing_id = 'CL-SAMPLE-001';

    INSERT INTO listing_scrape_errors (scrape_run_id, listing_id, inventory_uid, platform, external_listing_id, listing_url, error_stage, error_type, http_status, error_message, response_excerpt, is_cooloff_signal)
    SELECT '11111111-1111-4111-8111-111111111111', listing_id, inventory_uid, platform, external_listing_id, listing_url, 'fetch', 'not_found', 404, 'Synthetic listing unavailable during scrape.', 'Synthetic 404 excerpt.', false
    FROM listings
    WHERE external_listing_id = 'CL-SAMPLE-003B';

    INSERT INTO conversation_threads (
      platform,
      source_account,
      source_thread_id,
      source_conversation_url,
      contact_id,
      inventory_uid,
      inventory_group_id,
      listing_id,
      purpose,
      stage,
      priority,
      assigned_to,
      last_message_at,
      last_inbound_at,
      needs_reply,
      next_action_at,
      next_action_note,
      thread_summary,
      raw_thread_path,
      source_system,
      lead_quality_tag,
      lead_quality_reviewed_by,
      lead_quality_reviewed_at,
      lead_quality_notes
    )
    SELECT
      'craigslist_email',
      'craigslist-account@example.invalid',
      'sample-thread-001',
      'https://example.invalid/conversations/sample-thread-001',
      (SELECT contact_id FROM contacts WHERE display_name='Morgan Buyer'),
      l.inventory_uid,
      l.inventory_group_id,
      l.listing_id,
      'sale_inquiry',
      'needs_reply',
      'high',
      'Alex Partner',
      now() - interval '3 hours',
      now() - interval '3 hours',
      true,
      now() - interval '1 hour',
      'Synthetic buyer needs a reply about pickup availability.',
      'Synthetic buyer asked whether the item is still available and requested pickup options.',
      'local_data/furniture_conversations/raw/craigslist_email/sample-thread-001.json',
      'synthetic_seed',
      'actionable',
      'Casey Partner',
      now() - interval '2 hours',
      'Synthetic high-intent lead.'
    FROM listings l
    WHERE l.external_listing_id = 'CL-SAMPLE-001'
    ON CONFLICT DO NOTHING;

    INSERT INTO conversation_messages (
      conversation_thread_id,
      platform,
      source_account,
      source_message_id,
      source_thread_id,
      message_at,
      direction,
      sender_contact_id,
      recipient_contact_id,
      sender_raw,
      recipient_raw,
      subject,
      body_text,
      body_preview,
      message_url,
      raw_message_path,
      ingest_status,
      source_system
    )
    SELECT
      t.conversation_thread_id,
      t.platform,
      t.source_account,
      'sample-message-001',
      t.source_thread_id,
      now() - interval '3 hours',
      'inbound',
      t.contact_id,
      NULL,
      'Morgan Buyer <buyer@example.invalid>',
      'Craigslist Relay <craigslist-account@example.invalid>',
      'Synthetic inquiry about media cabinet',
      'Synthetic public-safe message: Is this still available, and could pickup work tomorrow?',
      'Is this still available, and could pickup work tomorrow?',
      'https://example.invalid/messages/sample-message-001',
      'local_data/furniture_conversations/normalized/craigslist_email/sample-message-001.normalized.json',
      'parsed',
      'synthetic_seed'
    FROM conversation_threads t
    WHERE t.source_thread_id = 'sample-thread-001'
    ON CONFLICT DO NOTHING;

  END IF;
END
$feature_seed$;

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
