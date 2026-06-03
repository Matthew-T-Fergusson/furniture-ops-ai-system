-- AWF-188 conversation tags, thread merge, and lead-source funnel regression.
-- Synthetic/public-safe only.

\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION assert_awf188(condition boolean, message text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF NOT condition THEN
    RAISE EXCEPTION 'AWF-188 regression failed: %', message;
  END IF;
END;
$$;

DO $$
DECLARE
  canonical_id bigint;
  duplicate_id bigint;
  hot_tag_id bigint;
  funnel_row record;
  expected_realized numeric(12,2) := 200.00;
  syn_contact_id bigint;
  syn_listing_id bigint;
BEGIN
  SELECT conversation_thread_id INTO canonical_id
  FROM conversation_threads
  WHERE source_thread_id='sample-thread-001'
  LIMIT 1;

  IF canonical_id IS NULL THEN
    expected_realized := 125.00;

    INSERT INTO contacts (display_name, contact_type, phone, email, notes, source_system)
    VALUES ('AWF188 Synthetic Buyer', 'buyer', '555-0188', 'awf188-buyer@example.invalid', 'Synthetic AWF-188 regression buyer', 'awf188_regression')
    RETURNING contact_id INTO syn_contact_id;

    SELECT listing_id INTO syn_listing_id
    FROM listings
    WHERE external_listing_id='CL-SYN-00001'
    LIMIT 1;

    PERFORM assert_awf188(syn_listing_id IS NOT NULL, 'CL-SYN-00001 listing missing for self-contained regression');

    INSERT INTO cash_flows (
      cf_record_id, inventory_uid, inventory_group_id, contact_id, txn_type,
      txn_date, vendor_or_description, amount, currency, category, purpose,
      notes, paid_by, paid_to, source_system, payment_stage
    )
    SELECT
      'SYN-CF-AWF188-SALE', l.inventory_uid, l.inventory_group_id, syn_contact_id,
      'Payment', DATE '2026-01-08', 'Synthetic AWF-188 sale payment', expected_realized,
      'USD', 'Sale', 'Sell Inventory', 'Synthetic AWF-188 sale payment row',
      'AWF188 Synthetic Buyer', 'Business', 'awf188_regression', 'deposit'
    FROM listings l
    WHERE l.listing_id=syn_listing_id;

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
      last_message_at,
      last_inbound_at,
      needs_reply,
      thread_summary,
      raw_thread_path,
      source_system
    )
    SELECT
      'craigslist_email',
      'craigslist-account@example.invalid',
      'sample-thread-awf188-self-contained',
      'https://example.invalid/conversations/sample-thread-awf188-self-contained',
      syn_contact_id,
      l.inventory_uid,
      l.inventory_group_id,
      l.listing_id,
      'sale_inquiry',
      'needs_reply',
      'high',
      now(),
      now(),
      true,
      'Synthetic self-contained AWF-188 lead thread.',
      'local_data/furniture_conversations/raw/craigslist_email/sample-thread-awf188-self-contained.json',
      'awf188_regression'
    FROM listings l
    WHERE l.listing_id=syn_listing_id
    RETURNING conversation_thread_id INTO canonical_id;
  END IF;

  PERFORM assert_awf188(canonical_id IS NOT NULL, 'sample canonical thread missing');

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
    last_message_at,
    last_inbound_at,
    needs_reply,
    thread_summary,
    raw_thread_path,
    source_system,
    merged_into_thread_id,
    merged_at,
    merged_by,
    merge_reason
  )
  SELECT
    'craigslist_chat',
    'craigslist-account@example.invalid',
    'sample-thread-001-chat-duplicate-awf188-' || canonical_id,
    'https://example.invalid/conversations/sample-thread-001-chat-duplicate-awf188',
    contact_id,
    inventory_uid,
    inventory_group_id,
    listing_id,
    'sale_inquiry',
    'needs_reply',
    'high',
    now(),
    now(),
    true,
    'Synthetic duplicate chat continuation merged into canonical AWF-188 thread.',
    'local_data/furniture_conversations/raw/craigslist_chat/sample-thread-001-chat-duplicate-awf188.json',
    'awf188_regression',
    canonical_id,
    now(),
    'lex-test',
    'Synthetic duplicate thread for AWF-188 regression.'
  FROM conversation_threads
  WHERE conversation_thread_id=canonical_id
  RETURNING conversation_thread_id INTO duplicate_id;

  SELECT conversation_tag_id INTO hot_tag_id
  FROM conversation_tags
  WHERE tag_key='hot_lead';

  PERFORM assert_awf188(hot_tag_id IS NOT NULL, 'hot_lead seed tag missing');

  INSERT INTO conversation_thread_tags (conversation_thread_id, conversation_tag_id, tagged_by, note)
  VALUES (duplicate_id, hot_tag_id, 'lex-test', 'Synthetic tag on merged-away child thread.');

  PERFORM assert_awf188(
    (SELECT canonical_conversation_thread_id FROM canonical_conversation_threads WHERE conversation_thread_id=duplicate_id) = canonical_id,
    'duplicate thread should resolve to canonical thread'
  );

  SELECT * INTO funnel_row
  FROM lead_source_funnel_thread_metrics
  WHERE canonical_conversation_thread_id=canonical_id;

  PERFORM assert_awf188(funnel_row.conversation_thread_id = canonical_id, 'thread metrics should be one row for canonical thread');
  PERFORM assert_awf188(funnel_row.lead_source = 'craigslist', 'craigslist_email/chat should normalize to craigslist lead_source');
  PERFORM assert_awf188(funnel_row.merged_source_thread_count >= 1, 'merged source thread count should include duplicate');
  PERFORM assert_awf188(funnel_row.source_thread_count >= 2, 'source thread count should include canonical + merged duplicate');
  PERFORM assert_awf188('hot_lead' = ANY(funnel_row.tag_keys), 'canonical funnel row should include tag assigned to merged child');
  PERFORM assert_awf188(funnel_row.realized_revenue > 0 AND funnel_row.realized_revenue <= expected_realized, 'realized revenue should be attributed from synthetic Payment/Sale cash_flow without exceeding the payment amount');
  PERFORM assert_awf188(funnel_row.estimated_pipeline_value > 0, 'pipeline value should be separate and based on listing/inventory expected value');
  PERFORM assert_awf188(funnel_row.has_realized_revenue IS TRUE, 'payment should mark thread as having realized revenue');
  PERFORM assert_awf188(funnel_row.counts_as_open_pipeline IS FALSE, 'realized revenue thread should not also count as open pipeline');

  PERFORM assert_awf188(
    EXISTS (
      SELECT 1
      FROM lead_source_funnel_metrics
      WHERE lead_source='craigslist'
        AND realized_revenue >= expected_realized
        AND realized_revenue_thread_count >= 1
    ),
    'lead-source rollup should expose strict payment-only realized revenue'
  );

  PERFORM assert_awf188(
    EXISTS (
      SELECT 1
      FROM lead_source_funnel_metrics
      WHERE lead_source='craigslist'
        AND open_pipeline_value_unweighted >= 0
    ),
    'lead-source rollup should expose separate unweighted pipeline metric'
  );

  -- Multi-lead same-item pipeline attribution regression: two open leads on
  -- the same item at $200 and $300 should create one $250 item opportunity,
  -- allocated $125/$125 across the two channel leads, not $500 total pipeline.
  INSERT INTO inventory_groups (inventory_group_id, group_type, acquisition_date, total_acquisition_cost, cost_allocation_method, notes)
  VALUES ('AWF188-PIPE-GROUP', 'standalone', DATE '2026-01-09', 50.00, 'not_allocated', 'Synthetic AWF-188 pipeline attribution group');

  INSERT INTO inventory (
    inventory_uid,
    inventory_id,
    inventory_group_id,
    item_id,
    item_title,
    category,
    list_price_target,
    cost,
    acquisition_cost,
    status,
    status_updated_at,
    cost_basis_source,
    cost_allocation_method,
    expected_sale_price,
    note
  ) VALUES (
    'AWF188-PIPE-ITEM',
    'AWF188-PIPE-ITEM',
    'AWF188-PIPE-GROUP',
    'AWF188-PIPE-ITEM',
    'Synthetic AWF-188 multi-channel item',
    'Table',
    250.00,
    50.00,
    50.00,
    'listed_active',
    now(),
    'direct_or_imported',
    'not_allocated',
    250.00,
    'Synthetic item for same-item multi-lead pipeline attribution regression.'
  );

  INSERT INTO listings (
    inventory_uid,
    inventory_group_id,
    platform,
    external_listing_id,
    listing_url,
    title,
    status,
    listed_at,
    current_asking_price,
    source_system,
    listing_series_id
  ) VALUES
    ('AWF188-PIPE-ITEM', 'AWF188-PIPE-GROUP', 'craigslist', 'AWF188-PIPE-CL', 'https://example.invalid/awf188-pipe-cl', 'Synthetic AWF-188 item Craigslist', 'active', now(), 200.00, 'awf188_regression', gen_random_uuid()),
    ('AWF188-PIPE-ITEM', 'AWF188-PIPE-GROUP', 'facebook_marketplace', 'AWF188-PIPE-FB', 'https://example.invalid/awf188-pipe-fb', 'Synthetic AWF-188 item Facebook', 'active', now(), 300.00, 'awf188_regression', gen_random_uuid());

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
    last_message_at,
    last_inbound_at,
    needs_reply,
    thread_summary,
    raw_thread_path,
    source_system
  )
  SELECT
    CASE WHEN l.platform='craigslist' THEN 'craigslist_chat' ELSE 'facebook_marketplace' END,
    'awf188-pipeline@example.invalid',
    'awf188-pipeline-' || l.platform,
    'https://example.invalid/conversations/awf188-pipeline-' || l.platform,
    NULL,
    l.inventory_uid,
    l.inventory_group_id,
    l.listing_id,
    'sale_inquiry',
    'needs_reply',
    'normal',
    now(),
    now(),
    true,
    'Synthetic open lead for AWF-188 same-item pipeline attribution.',
    'local_data/furniture_conversations/raw/' || l.platform || '/awf188-pipeline.json',
    'awf188_regression'
  FROM listings l
  WHERE l.external_listing_id IN ('AWF188-PIPE-CL', 'AWF188-PIPE-FB');

  PERFORM assert_awf188(
    (SELECT count(*) FROM lead_source_funnel_thread_metrics WHERE open_pipeline_opportunity_key='AWF188-PIPE-GROUP' AND counts_as_open_pipeline) = 2,
    'same item should have two open lead rows in thread metrics'
  );

  PERFORM assert_awf188(
    (SELECT max(open_pipeline_opportunity_value_unweighted) FROM lead_source_funnel_thread_metrics WHERE open_pipeline_opportunity_key='AWF188-PIPE-GROUP') = 250.00,
    'same item opportunity value should be weighted average of 200 and 300 list prices'
  );

  PERFORM assert_awf188(
    (SELECT sum(attributed_open_pipeline_value_unweighted) FROM lead_source_funnel_thread_metrics WHERE open_pipeline_opportunity_key='AWF188-PIPE-GROUP') = 250.00,
    'same item attributed pipeline should sum to one opportunity value, not duplicate list prices'
  );

  PERFORM assert_awf188(
    (SELECT count(*) FROM lead_source_funnel_thread_metrics WHERE open_pipeline_opportunity_key='AWF188-PIPE-GROUP' AND attributed_open_pipeline_value_unweighted=125.00) = 2,
    'same item equal-weight v1 attribution should allocate 125 to each of two open leads'
  );
END;
$$;

ROLLBACK;
\echo 'conversation_tags_merge_funnel: ok'
