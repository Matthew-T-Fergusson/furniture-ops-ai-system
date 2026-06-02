-- 010_active_conversation_queue.sql
-- Create active furniture conversation queue view for lead/workflow triage.
--
-- Preflight/readback plan:
-- 1. Run: make ci-smoke
-- 2. Apply: apply ordered sql/*.sql in a database session
-- 3. Readback SQL:
--    SELECT conversation_thread_id, platform, stage, needs_reply, queue_reason, queue_urgency
--    FROM public.active_conversation_queue
--    ORDER BY queue_sort_bucket, queue_sort_at NULLS LAST, conversation_thread_id;
--
-- Policy:
-- - SQL view only; no materialized refresh dependency.
-- - Preview text only; full messages remain in conversation_messages.
-- - Dashboard/report integration can consume this view later.

BEGIN;

CREATE OR REPLACE VIEW public.active_conversation_queue AS
WITH latest_message AS (
  SELECT DISTINCT ON (m.conversation_thread_id)
    m.conversation_thread_id,
    m.conversation_message_id AS latest_message_id,
    m.message_at AS latest_message_at,
    m.direction AS latest_message_direction,
    m.subject AS latest_subject,
    m.body_preview AS latest_body_preview,
    m.message_url AS latest_message_url,
    m.raw_message_path AS latest_raw_message_path
  FROM public.conversation_messages m
  ORDER BY m.conversation_thread_id, m.message_at DESC, m.conversation_message_id DESC
), queue_base AS (
  SELECT
    t.conversation_thread_id,
    t.platform,
    t.source_account,
    t.source_thread_id,
    t.source_conversation_url,
    t.contact_id,
    c.display_name AS contact_name,
    c.username AS contact_username,
    c.username_platform,
    c.platform_contact_id,
    t.contact_role_id,
    t.inventory_uid,
    inv.item_title AS inventory_title,
    t.inventory_group_id,
    t.listing_id,
    l.title AS listing_title,
    l.listing_url,
    l.external_listing_id,
    t.movement_id,
    pd.movement_type,
    pd.scheduled_start,
    pd.scheduled_end,
    pd.movement_status,
    t.purpose,
    t.stage,
    t.priority,
    t.assigned_to,
    t.needs_reply,
    t.last_message_at,
    t.last_inbound_at,
    t.last_outbound_at,
    CASE WHEN t.last_message_at IS NOT NULL THEN round(EXTRACT(epoch FROM (now() - t.last_message_at)) / 3600.0, 2) END AS hours_since_last_message,
    CASE WHEN t.last_inbound_at IS NOT NULL THEN round(EXTRACT(epoch FROM (now() - t.last_inbound_at)) / 3600.0, 2) END AS hours_since_last_inbound,
    CASE WHEN t.last_outbound_at IS NOT NULL THEN round(EXTRACT(epoch FROM (now() - t.last_outbound_at)) / 3600.0, 2) END AS hours_since_last_outbound,
    t.next_action_at,
    t.next_action_note,
    t.thread_summary,
    lm.latest_message_id,
    lm.latest_message_at,
    lm.latest_message_direction,
    lm.latest_subject,
    lm.latest_body_preview,
    lm.latest_message_url,
    lm.latest_raw_message_path,
    CASE
      WHEN t.stage = 'new' THEN 'new_thread'
      WHEN t.platform = 'craigslist_chat'
        AND lm.latest_message_direction = 'system'
        AND coalesce(lm.latest_body_preview,'') ILIKE '%new message in craigslist chat%'
        THEN 'craigslist_chat_capture_needed'
      WHEN t.next_action_at IS NOT NULL AND t.next_action_at <= now() THEN 'next_action_due'
      WHEN t.needs_reply THEN 'needs_reply'
      WHEN t.stage = 'waiting_on_other_party'
        AND t.last_outbound_at IS NOT NULL
        AND t.last_outbound_at <= now() - interval '24 hours'
        AND (t.last_inbound_at IS NULL OR t.last_inbound_at < t.last_outbound_at)
        THEN 'follow_up_due_24h'
      WHEN t.stage = 'scheduled' THEN 'scheduled'
      WHEN t.stage = 'negotiating' THEN 'active_negotiation'
      ELSE 'active_thread'
    END AS queue_reason
  FROM public.conversation_threads t
  LEFT JOIN latest_message lm USING (conversation_thread_id)
  LEFT JOIN public.contacts c ON c.contact_id = t.contact_id
  LEFT JOIN public.inventory inv ON inv.inventory_uid = t.inventory_uid
  LEFT JOIN public.listings l ON l.listing_id = t.listing_id
  LEFT JOIN public.pickups_deliveries pd ON pd.movement_id = t.movement_id
  WHERE t.stage NOT IN ('completed','dead','spam','archived')
    AND (
      t.needs_reply
      OR t.stage IN ('new','needs_reply','negotiating','scheduled')
      OR (t.next_action_at IS NOT NULL AND t.next_action_at <= now())
      OR (
        t.stage = 'waiting_on_other_party'
        AND t.last_outbound_at IS NOT NULL
        AND t.last_outbound_at <= now() - interval '24 hours'
        AND (t.last_inbound_at IS NULL OR t.last_inbound_at < t.last_outbound_at)
      )
    )
)
SELECT
  qb.*,
  CASE
    WHEN qb.priority = 'urgent' THEN 'urgent'
    WHEN qb.next_action_at IS NOT NULL AND qb.next_action_at <= now() THEN 'urgent'
    WHEN qb.needs_reply AND qb.last_inbound_at IS NOT NULL AND qb.last_inbound_at <= now() - interval '24 hours' THEN 'urgent'
    WHEN qb.scheduled_start IS NOT NULL AND qb.scheduled_start <= now() + interval '24 hours' AND qb.movement_status IN ('planned','confirmed','rescheduled') THEN 'urgent'
    WHEN qb.priority = 'high' THEN 'high'
    WHEN qb.queue_reason IN ('craigslist_chat_capture_needed','follow_up_due_24h','scheduled') THEN 'high'
    WHEN qb.priority = 'low' AND NOT qb.needs_reply THEN 'low'
    ELSE 'normal'
  END AS queue_urgency,
  CASE
    WHEN qb.priority = 'urgent' THEN 1
    WHEN qb.next_action_at IS NOT NULL AND qb.next_action_at <= now() THEN 1
    WHEN qb.needs_reply AND qb.last_inbound_at IS NOT NULL AND qb.last_inbound_at <= now() - interval '24 hours' THEN 1
    WHEN qb.scheduled_start IS NOT NULL AND qb.scheduled_start <= now() + interval '24 hours' AND qb.movement_status IN ('planned','confirmed','rescheduled') THEN 1
    WHEN qb.priority = 'high' THEN 2
    WHEN qb.queue_reason IN ('craigslist_chat_capture_needed','follow_up_due_24h','scheduled') THEN 2
    WHEN qb.needs_reply THEN 3
    WHEN qb.stage = 'scheduled' THEN 4
    WHEN qb.priority = 'low' THEN 6
    ELSE 5
  END AS queue_sort_bucket,
  COALESCE(qb.next_action_at, qb.scheduled_start, qb.last_inbound_at, qb.last_message_at) AS queue_sort_at
FROM queue_base qb;

COMMENT ON VIEW public.active_conversation_queue IS
  'Active furniture conversation queue for lead/workflow triage. Excludes terminal stages, includes scheduled threads, preview text only, and surfaces platform-specific reasons like craigslist_chat_capture_needed.';

COMMIT;

-- Suggested manual readback after apply:
-- SELECT conversation_thread_id, platform, stage, needs_reply, queue_reason, queue_urgency, latest_body_preview
-- FROM public.active_conversation_queue
-- ORDER BY queue_sort_bucket, queue_sort_at NULLS LAST, conversation_thread_id;
