-- 014_response_sla_metrics.sql
-- AWF-185: marketplace response SLA metrics for CRM/dashboard reporting.
--
-- Product decisions:
-- - 24h is the primary SLA target; 48h is a secondary severity marker.
-- - Scope is marketplace conversations only, not partner/vendor/internal logistics.
-- - Use normal views for v1 so metrics are always current and need no refresh job.
-- - Preserve raw/test/archive flags in thread-level metrics; dashboard defaults can filter them.
-- - Calculate first-response metrics and all inbound->next-outbound response-pair metrics.

BEGIN;

DROP VIEW IF EXISTS public.response_sla_metrics;
DROP VIEW IF EXISTS public.response_sla_thread_metrics;

CREATE VIEW public.response_sla_thread_metrics AS
WITH marketplace_threads AS (
  SELECT
    ct.conversation_thread_id,
    ct.platform,
    ct.purpose,
    ct.stage,
    ct.priority,
    ct.needs_reply,
    ct.lead_quality_tag,
    ct.created_at,
    ct.last_inbound_at,
    ct.last_outbound_at,
    ct.thread_summary,
    ct.listing_id,
    ct.inventory_uid,
    (ct.stage IN ('archived','spam','dead') OR ct.purpose = 'support_admin') AS is_test_or_archived
  FROM public.conversation_threads ct
  WHERE ct.platform IN ('craigslist_email','craigslist_chat','facebook_marketplace','ebay')
), first_inbound AS (
  SELECT
    mt.conversation_thread_id,
    min(cm.message_at) FILTER (WHERE cm.direction = 'inbound') AS first_inbound_at
  FROM marketplace_threads mt
  LEFT JOIN public.conversation_messages cm USING (conversation_thread_id)
  GROUP BY mt.conversation_thread_id
), first_response AS (
  SELECT
    fi.conversation_thread_id,
    min(cm.message_at) AS first_outbound_after_first_inbound_at
  FROM first_inbound fi
  JOIN public.conversation_messages cm
    ON cm.conversation_thread_id = fi.conversation_thread_id
   AND cm.direction = 'outbound'
   AND fi.first_inbound_at IS NOT NULL
   AND cm.message_at > fi.first_inbound_at
  GROUP BY fi.conversation_thread_id
), inbound_pair_metrics AS (
  SELECT
    pairs.conversation_thread_id,
    count(*) AS inbound_message_count,
    count(pairs.next_outbound_at) AS responded_inbound_message_count,
    round(percentile_cont(0.5) WITHIN GROUP (
      ORDER BY EXTRACT(epoch FROM (pairs.next_outbound_at - pairs.inbound_at)) / 3600.0
    ) FILTER (WHERE pairs.next_outbound_at IS NOT NULL)::numeric, 2) AS median_response_pair_hours,
    round(percentile_cont(0.9) WITHIN GROUP (
      ORDER BY EXTRACT(epoch FROM (pairs.next_outbound_at - pairs.inbound_at)) / 3600.0
    ) FILTER (WHERE pairs.next_outbound_at IS NOT NULL)::numeric, 2) AS p90_response_pair_hours
  FROM (
    SELECT
      cm.conversation_thread_id,
      cm.message_at AS inbound_at,
      (
        SELECT min(outbound.message_at)
        FROM public.conversation_messages outbound
        WHERE outbound.conversation_thread_id = cm.conversation_thread_id
          AND outbound.direction = 'outbound'
          AND outbound.message_at > cm.message_at
      ) AS next_outbound_at
    FROM public.conversation_messages cm
    JOIN marketplace_threads mt USING (conversation_thread_id)
    WHERE cm.direction = 'inbound'
  ) pairs
  GROUP BY pairs.conversation_thread_id
), last_unanswered_inbound AS (
  SELECT DISTINCT ON (cm.conversation_thread_id)
    cm.conversation_thread_id,
    cm.message_at AS last_unanswered_inbound_at
  FROM public.conversation_messages cm
  JOIN marketplace_threads mt USING (conversation_thread_id)
  WHERE cm.direction = 'inbound'
    AND NOT EXISTS (
      SELECT 1
      FROM public.conversation_messages outbound
      WHERE outbound.conversation_thread_id = cm.conversation_thread_id
        AND outbound.direction = 'outbound'
        AND outbound.message_at > cm.message_at
    )
  ORDER BY cm.conversation_thread_id, cm.message_at DESC, cm.conversation_message_id DESC
)
SELECT
  mt.conversation_thread_id,
  mt.platform,
  mt.purpose,
  mt.stage,
  mt.priority,
  mt.needs_reply,
  mt.lead_quality_tag,
  mt.is_test_or_archived,
  mt.listing_id,
  mt.inventory_uid,
  fi.first_inbound_at,
  coalesce(fr.first_outbound_after_first_inbound_at,
    CASE
      WHEN mt.last_outbound_at IS NOT NULL
       AND coalesce(fi.first_inbound_at, mt.last_inbound_at) IS NOT NULL
       AND mt.last_outbound_at > coalesce(fi.first_inbound_at, mt.last_inbound_at)
      THEN mt.last_outbound_at
      ELSE NULL
    END
  ) AS first_response_at,
  round((EXTRACT(epoch FROM (
    coalesce(fr.first_outbound_after_first_inbound_at,
      CASE
        WHEN mt.last_outbound_at IS NOT NULL
         AND coalesce(fi.first_inbound_at, mt.last_inbound_at) IS NOT NULL
         AND mt.last_outbound_at > coalesce(fi.first_inbound_at, mt.last_inbound_at)
        THEN mt.last_outbound_at
        ELSE NULL
      END
    ) - coalesce(fi.first_inbound_at, mt.last_inbound_at)
  )) / 3600.0)::numeric, 2) AS first_response_hours,
  coalesce(ipm.inbound_message_count, 0) AS inbound_message_count,
  coalesce(ipm.responded_inbound_message_count, 0) AS responded_inbound_message_count,
  ipm.median_response_pair_hours,
  ipm.p90_response_pair_hours,
  lui.last_unanswered_inbound_at,
  CASE
    WHEN lui.last_unanswered_inbound_at IS NOT NULL THEN round((EXTRACT(epoch FROM (now() - lui.last_unanswered_inbound_at)) / 3600.0)::numeric, 2)
    ELSE NULL
  END AS open_unanswered_hours,
  (lui.last_unanswered_inbound_at IS NOT NULL AND now() - lui.last_unanswered_inbound_at > interval '24 hours') AS open_breach_24h,
  (lui.last_unanswered_inbound_at IS NOT NULL AND now() - lui.last_unanswered_inbound_at > interval '48 hours') AS open_breach_48h,
  mt.thread_summary
FROM marketplace_threads mt
LEFT JOIN first_inbound fi USING (conversation_thread_id)
LEFT JOIN first_response fr USING (conversation_thread_id)
LEFT JOIN inbound_pair_metrics ipm USING (conversation_thread_id)
LEFT JOIN last_unanswered_inbound lui USING (conversation_thread_id)
WHERE coalesce(fi.first_inbound_at, mt.last_inbound_at) IS NOT NULL;

COMMENT ON VIEW public.response_sla_thread_metrics IS
  'AWF-185: Thread-level marketplace response SLA metrics. Includes raw/test/archive flags so dashboards can filter while the raw view remains auditable.';

CREATE VIEW public.response_sla_metrics AS
SELECT
  platform,
  count(*) AS threads_with_inbound,
  count(*) FILTER (WHERE first_response_at IS NOT NULL) AS threads_responded,
  round((100.0 * count(*) FILTER (WHERE first_response_at IS NOT NULL) / nullif(count(*), 0))::numeric, 2) AS response_rate_pct,
  round(percentile_cont(0.5) WITHIN GROUP (ORDER BY first_response_hours) FILTER (WHERE first_response_hours IS NOT NULL)::numeric, 2) AS median_first_response_hours,
  round(percentile_cont(0.9) WITHIN GROUP (ORDER BY first_response_hours) FILTER (WHERE first_response_hours IS NOT NULL)::numeric, 2) AS p90_first_response_hours,
  sum(inbound_message_count) AS inbound_message_count,
  sum(responded_inbound_message_count) AS responded_inbound_message_count,
  round(percentile_cont(0.5) WITHIN GROUP (ORDER BY median_response_pair_hours) FILTER (WHERE median_response_pair_hours IS NOT NULL)::numeric, 2) AS median_response_pair_hours,
  round(percentile_cont(0.9) WITHIN GROUP (ORDER BY p90_response_pair_hours) FILTER (WHERE p90_response_pair_hours IS NOT NULL)::numeric, 2) AS p90_response_pair_hours,
  count(*) FILTER (WHERE open_breach_24h) AS open_breaches_24h,
  count(*) FILTER (WHERE open_breach_48h) AS open_breaches_48h,
  count(*) FILTER (WHERE is_test_or_archived) AS test_or_archived_threads,
  count(*) FILTER (WHERE NOT is_test_or_archived) AS dashboard_default_threads,
  count(*) FILTER (WHERE NOT is_test_or_archived AND open_breach_24h) AS dashboard_default_open_breaches_24h,
  count(*) FILTER (WHERE NOT is_test_or_archived AND open_breach_48h) AS dashboard_default_open_breaches_48h
FROM public.response_sla_thread_metrics
GROUP BY platform;

COMMENT ON VIEW public.response_sla_metrics IS
  'AWF-185: Marketplace response SLA metrics by platform. 24h is the primary SLA target and 48h is secondary; dashboard defaults should use non-test/non-archived columns while raw counts remain auditable.';

COMMIT;
