-- AWF-187 message template rendering regression.
-- Synthetic/public-safe only. Verifies template seed, missing-field preview,
-- ready preview, channel/base behavior, and conversation_messages.template_id.

\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION assert_awf187(condition boolean, message text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF NOT condition THEN
    RAISE EXCEPTION 'AWF-187 regression failed: %', message;
  END IF;
END;
$$;

DO $$
DECLARE
  render_row record;
  tmpl_id bigint;
  thread_id bigint;
  msg_id bigint;
BEGIN
  SELECT template_id INTO tmpl_id
  FROM message_templates
  WHERE template_key='still_available'
    AND active;

  PERFORM assert_awf187(tmpl_id IS NOT NULL, 'still_available template missing');

  SELECT * INTO render_row
  FROM render_message_template(
    'still_available',
    'craigslist_email',
    '{"listing_title": "Synthetic walnut side table"}'::jsonb
  );
  PERFORM assert_awf187(render_row.preview_status = 'needs_fields', 'missing pickup_area should produce needs_fields status');
  PERFORM assert_awf187('pickup_area' = ANY(render_row.missing_fields), 'missing_fields should include pickup_area');
  PERFORM assert_awf187(render_row.preview_message LIKE 'Missing required merge fields:%', 'preview_message should explain missing fields');
  PERFORM assert_awf187(render_row.rendered_body LIKE '%{{pickup_area}}%', 'missing required placeholder should remain visible in rendered body');

  SELECT * INTO render_row
  FROM render_message_template(
    'still_available',
    'facebook_marketplace',
    '{"listing_title": "Synthetic walnut side table", "pickup_area": "Frederick", "availability_window": "Tomorrow afternoon can work."}'::jsonb
  );
  PERFORM assert_awf187(render_row.preview_status = 'ready', 'complete fields should produce ready preview');
  PERFORM assert_awf187(render_row.rendered_body LIKE '%Synthetic walnut side table%', 'rendered body should include listing title');
  PERFORM assert_awf187(render_row.rendered_body LIKE '%Frederick%', 'rendered body should include pickup area');
  PERFORM assert_awf187(render_row.rendered_body NOT LIKE '%{{%', 'complete render should not leave placeholders');
  PERFORM assert_awf187(render_row.preview_message LIKE 'Preview ready.%', 'ready preview should still mention approval gate');

  SELECT * INTO render_row
  FROM render_message_template(
    'counteroffer_hold_price',
    'craigslist_chat',
    '{"listing_title": "Synthetic walnut side table", "asking_price": "$250"}'::jsonb
  );
  PERFORM assert_awf187(render_row.preview_status = 'ready', 'counteroffer template should render for craigslist_chat');
  PERFORM assert_awf187(render_row.rendered_body LIKE '%holding at $250 for now%', 'counteroffer wording should hold price without inviting negotiation');

  SELECT conversation_thread_id INTO thread_id
  FROM conversation_threads
  WHERE source_thread_id='sample-thread-sla-001'
  LIMIT 1;

  IF thread_id IS NOT NULL THEN
    INSERT INTO conversation_messages (
      conversation_thread_id,
      platform,
      source_account,
      source_message_id,
      source_thread_id,
      message_at,
      direction,
      body_text,
      body_preview,
      ingest_status,
      source_system,
      template_id
    ) VALUES (
      thread_id,
      'craigslist_email',
      'craigslist-account@example.invalid',
      'sample-message-template-001',
      'sample-thread-sla-001',
      now(),
      'outbound',
      'Synthetic public-safe template-rendered outbound message.',
      'Synthetic public-safe template-rendered outbound message.',
      'parsed',
      'awf187_regression',
      tmpl_id
    ) RETURNING conversation_message_id INTO msg_id;

    PERFORM assert_awf187(
      EXISTS (SELECT 1 FROM conversation_messages WHERE conversation_message_id=msg_id AND template_id=tmpl_id),
      'conversation_messages.template_id should round-trip'
    );
  END IF;

  PERFORM assert_awf187(
    (SELECT use_count FROM message_templates WHERE template_id=tmpl_id) = 0,
    'preview/test inserts should not automatically increment use_count'
  );
END;
$$;

ROLLBACK;
\echo 'message_template_rendering: ok'
