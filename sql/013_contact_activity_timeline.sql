-- 013_contact_activity_timeline.sql
-- AWF-184: unified CRM contact timeline for public-safe furniture operations data.
--
-- Product decisions:
-- - Include direct and strongly-linked contact activity in one raw/auditable view.
-- - Preserve every message as its own row; downstream agents/dashboards can summarize.
-- - Include cash_flows only when contact_id is explicit to avoid false attribution.
-- - Do not filter archived/test activity in the raw view; dashboards can filter context.
-- - Public seed coverage uses synthetic records only.

BEGIN;

DROP VIEW IF EXISTS public.contact_activity_timeline;

CREATE VIEW public.contact_activity_timeline AS
WITH conversation_message_activity AS (
  SELECT
    cm.message_at AS activity_at,
    'conversation_message'::text AS activity_type,
    coalesce(
      cm.sender_contact_id,
      cm.recipient_contact_id,
      ct.contact_id
    ) AS contact_id,
    'conversation_message'::text AS related_entity_type,
    cm.conversation_message_id::text AS related_entity_id,
    cm.platform AS source_platform,
    cm.direction,
    left(
      concat_ws(
        ' — ',
        nullif(cm.subject, ''),
        nullif(cm.body_preview, ''),
        nullif(cm.sender_raw, '')
      ),
      500
    ) AS summary,
    jsonb_build_object(
      'relationship_strength', CASE
        WHEN cm.sender_contact_id IS NOT NULL OR cm.recipient_contact_id IS NOT NULL THEN 'direct_message_contact'
        WHEN ct.contact_id IS NOT NULL THEN 'inferred_from_conversation_thread'
        ELSE 'unknown'
      END,
      'conversation_thread_id', ct.conversation_thread_id,
      'source_thread_id', cm.source_thread_id,
      'source_message_id', cm.source_message_id,
      'source_conversation_url', ct.source_conversation_url,
      'message_url', cm.message_url,
      'listing_id', ct.listing_id,
      'inventory_uid', ct.inventory_uid,
      'movement_id', ct.movement_id,
      'ingest_status', cm.ingest_status,
      'raw_message_path', cm.raw_message_path,
      'is_raw_test_or_archived_visible', (ct.stage = 'archived' OR ct.purpose = 'support_admin')
    ) AS context
  FROM public.conversation_messages cm
  JOIN public.conversation_threads ct USING (conversation_thread_id)
  WHERE coalesce(cm.sender_contact_id, cm.recipient_contact_id, ct.contact_id) IS NOT NULL
), conversation_thread_activity AS (
  SELECT
    coalesce(ct.last_message_at, ct.updated_at, ct.created_at) AS activity_at,
    'conversation_thread'::text AS activity_type,
    ct.contact_id,
    'conversation_thread'::text AS related_entity_type,
    ct.conversation_thread_id::text AS related_entity_id,
    ct.platform AS source_platform,
    NULL::text AS direction,
    left(
      concat_ws(
        ' — ',
        nullif(ct.thread_summary, ''),
        nullif(l.title, ''),
        nullif(ct.next_action_note, '')
      ),
      500
    ) AS summary,
    jsonb_build_object(
      'relationship_strength', 'direct_thread_contact',
      'source_thread_id', ct.source_thread_id,
      'source_conversation_url', ct.source_conversation_url,
      'purpose', ct.purpose,
      'stage', ct.stage,
      'priority', ct.priority,
      'needs_reply', ct.needs_reply,
      'listing_id', ct.listing_id,
      'listing_title', l.title,
      'listing_url', l.listing_url,
      'external_listing_id', l.external_listing_id,
      'inventory_uid', ct.inventory_uid,
      'inventory_group_id', ct.inventory_group_id,
      'movement_id', ct.movement_id,
      'lead_quality_tag', ct.lead_quality_tag,
      'is_raw_test_or_archived_visible', (ct.stage = 'archived' OR ct.purpose = 'support_admin')
    ) AS context
  FROM public.conversation_threads ct
  LEFT JOIN public.listings l ON l.listing_id = ct.listing_id
  WHERE ct.contact_id IS NOT NULL
), movement_activity AS (
  SELECT
    coalesce(pd.scheduled_start, pd.updated_at, pd.created_at) AS activity_at,
    'movement'::text AS activity_type,
    pd.contact_id,
    'pickup_delivery'::text AS related_entity_type,
    pd.movement_id::text AS related_entity_id,
    pd.source_system AS source_platform,
    NULL::text AS direction,
    left(
      concat_ws(
        ' — ',
        pd.movement_type,
        pd.movement_status,
        nullif(pd.counterparty_name, ''),
        nullif(pd.notes, '')
      ),
      500
    ) AS summary,
    jsonb_build_object(
      'relationship_strength', 'direct_movement_contact',
      'movement_type', pd.movement_type,
      'movement_status', pd.movement_status,
      'inventory_uid', pd.inventory_uid,
      'inventory_group_id', pd.inventory_group_id,
      'scheduled_start', pd.scheduled_start,
      'scheduled_end', pd.scheduled_end,
      'calendar_event_id', pd.calendar_event_id,
      'assigned_to', pd.assigned_to,
      'deposit_required', pd.deposit_required,
      'deposit_received', pd.deposit_received,
      'item_price', pd.item_price,
      'delivery_fee', pd.delivery_fee,
      'balance_owed', pd.balance_owed
    ) AS context
  FROM public.pickups_deliveries pd
  WHERE pd.contact_id IS NOT NULL
), cash_flow_activity AS (
  SELECT
    coalesce(cf.txn_date::timestamptz, cf.imported_at) AS activity_at,
    'cash_flow'::text AS activity_type,
    cf.contact_id,
    'cash_flow'::text AS related_entity_type,
    cf.cf_record_id AS related_entity_id,
    cf.source_system AS source_platform,
    NULL::text AS direction,
    left(
      concat_ws(
        ' — ',
        cf.txn_type,
        nullif(cf.vendor_or_description, ''),
        cf.amount::text,
        nullif(cf.category, ''),
        nullif(cf.payment_stage, '')
      ),
      500
    ) AS summary,
    jsonb_build_object(
      'relationship_strength', 'direct_cash_flow_contact',
      'inventory_uid', cf.inventory_uid,
      'inventory_group_id', cf.inventory_group_id,
      'txn_type', cf.txn_type,
      'txn_date', cf.txn_date,
      'amount', cf.amount,
      'currency', cf.currency,
      'category', cf.category,
      'tax_category_code', cf.tax_category_code,
      'purpose', cf.purpose,
      'payment_method', cf.payment_method,
      'payment_stage', cf.payment_stage,
      'paid_by', cf.paid_by,
      'paid_to', cf.paid_to
    ) AS context
  FROM public.cash_flows cf
  WHERE cf.contact_id IS NOT NULL
)
SELECT
  activity_at,
  activity_type,
  contact_id,
  related_entity_type,
  related_entity_id,
  source_platform,
  direction,
  summary,
  context
FROM conversation_message_activity
UNION ALL
SELECT
  activity_at,
  activity_type,
  contact_id,
  related_entity_type,
  related_entity_id,
  source_platform,
  direction,
  summary,
  context
FROM conversation_thread_activity
UNION ALL
SELECT
  activity_at,
  activity_type,
  contact_id,
  related_entity_type,
  related_entity_id,
  source_platform,
  direction,
  summary,
  context
FROM movement_activity
UNION ALL
SELECT
  activity_at,
  activity_type,
  contact_id,
  related_entity_type,
  related_entity_id,
  source_platform,
  direction,
  summary,
  context
FROM cash_flow_activity;

COMMENT ON VIEW public.contact_activity_timeline IS
  'AWF-184: public-safe raw CRM timeline that shows messages, conversation threads, movement events, and explicitly contact-linked cash flows for a contact. Downstream summaries/dashboards can filter or collapse rows; this raw view preserves auditability, including archived/test activity.';

COMMIT;
