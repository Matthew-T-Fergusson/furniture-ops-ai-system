-- 019_awf188_pipeline_attribution.sql
-- AWF-188 hardening: attribute pipeline and revenue without double-counting
-- the same sellable item/opportunity across multiple open leads/channels.
--
-- Decision from Matt (2026-06-03): If the same item has interest across
-- multiple conversations/channels, total potential revenue should not be the
-- sum of each conversation's list price. It should be capped at one item-level
-- opportunity value, using a weighted average of active lead/list prices, then
-- allocated back across leads/channels.

BEGIN;

DROP VIEW IF EXISTS public.lead_source_funnel_metrics;
DROP VIEW IF EXISTS public.lead_source_funnel_thread_metrics;

CREATE VIEW public.lead_source_funnel_thread_metrics AS
WITH canonical_threads AS (
  SELECT
    cct.*,
    CASE
      WHEN cct.platform IN ('craigslist_email','craigslist_chat') THEN 'craigslist'
      WHEN cct.platform = 'facebook_marketplace' THEN 'facebook_marketplace'
      WHEN cct.platform = 'ebay' THEN 'ebay'
      WHEN cct.platform = 'gmail' THEN 'gmail'
      WHEN cct.platform = 'sms' THEN 'sms'
      WHEN cct.platform = 'telegram' THEN 'telegram'
      WHEN cct.platform = 'manual' THEN 'manual'
      ELSE 'other'
    END AS lead_source
  FROM public.canonical_conversation_threads cct
), canonical_rollup AS (
  SELECT
    canonical_conversation_thread_id,
    min(created_at) AS first_thread_created_at,
    max(last_message_at) AS latest_message_at,
    bool_or(needs_reply) FILTER (WHERE NOT is_merged_away) AS canonical_needs_reply,
    count(*) AS source_thread_count,
    count(*) FILTER (WHERE is_merged_away) AS merged_source_thread_count,
    array_agg(DISTINCT platform ORDER BY platform) AS source_platforms
  FROM canonical_threads
  GROUP BY canonical_conversation_thread_id
), thread_price AS (
  SELECT
    ct.canonical_conversation_thread_id,
    max(coalesce(l.current_asking_price, i.expected_sale_price, i.list_price_target))::numeric(12,2) AS estimated_pipeline_value,
    max(l.current_asking_price)::numeric(12,2) AS listing_asking_price,
    max(coalesce(i.expected_sale_price, i.list_price_target))::numeric(12,2) AS inventory_expected_price
  FROM canonical_threads ct
  LEFT JOIN public.listings l ON l.listing_id = ct.listing_id
  LEFT JOIN public.inventory i ON i.inventory_uid = ct.inventory_uid
  GROUP BY ct.canonical_conversation_thread_id
), payment_candidates AS (
  SELECT DISTINCT
    ct.canonical_conversation_thread_id,
    cf.cf_record_id,
    cf.amount,
    cf.txn_date
  FROM canonical_threads ct
  JOIN public.cash_flows cf
    ON (
      (ct.inventory_uid IS NOT NULL AND cf.inventory_uid = ct.inventory_uid)
      OR (ct.inventory_group_id IS NOT NULL AND cf.inventory_group_id = ct.inventory_group_id)
      OR (ct.contact_id IS NOT NULL AND cf.contact_id = ct.contact_id)
    )
  WHERE cf.txn_type = 'Payment'
    AND cf.category = 'Sale'
    AND coalesce(cf.payment_stage, '') <> 'refund'
), payment_match_counts AS (
  SELECT
    cf_record_id,
    count(*) AS matched_thread_count
  FROM payment_candidates
  GROUP BY cf_record_id
), payment_allocations AS (
  SELECT
    pc.canonical_conversation_thread_id,
    pc.cf_record_id,
    (pc.amount / nullif(pmc.matched_thread_count, 0))::numeric(12,2) AS attributed_amount,
    pc.txn_date
  FROM payment_candidates pc
  JOIN payment_match_counts pmc USING (cf_record_id)
), payment_rollup AS (
  SELECT
    canonical_conversation_thread_id,
    sum(attributed_amount)::numeric(12,2) AS realized_revenue,
    count(*) AS realized_payment_count,
    max(txn_date) AS latest_realized_payment_date
  FROM payment_allocations
  GROUP BY canonical_conversation_thread_id
), tag_rollup AS (
  SELECT
    cct.canonical_conversation_thread_id,
    array_agg(DISTINCT ct.tag_key ORDER BY ct.tag_key) AS tag_keys
  FROM public.conversation_thread_tags ctt
  JOIN public.conversation_tags ct ON ct.conversation_tag_id = ctt.conversation_tag_id
  JOIN public.canonical_conversation_threads cct ON cct.conversation_thread_id = ctt.conversation_thread_id
  WHERE ct.active
  GROUP BY cct.canonical_conversation_thread_id
), thread_base AS (
  SELECT
    base.conversation_thread_id,
    base.canonical_conversation_thread_id,
    base.platform,
    base.lead_source,
    base.source_account,
    base.source_thread_id,
    base.contact_id,
    base.inventory_uid,
    base.inventory_group_id,
    base.listing_id,
    base.movement_id,
    base.purpose,
    base.stage,
    base.priority,
    base.lead_quality_tag,
    coalesce(tr.tag_keys, ARRAY[]::text[]) AS tag_keys,
    base.is_merged_away,
    cr.source_thread_count,
    cr.merged_source_thread_count,
    cr.source_platforms,
    cr.first_thread_created_at,
    cr.latest_message_at,
    coalesce(pr.realized_revenue, 0)::numeric(12,2) AS realized_revenue,
    coalesce(pr.realized_payment_count, 0) AS realized_payment_count,
    pr.latest_realized_payment_date,
    coalesce(tp.estimated_pipeline_value, 0)::numeric(12,2) AS estimated_pipeline_value,
    tp.listing_asking_price,
    tp.inventory_expected_price,
    CASE WHEN coalesce(pr.realized_payment_count, 0) > 0 THEN true ELSE false END AS has_realized_revenue,
    CASE
      WHEN base.stage IN ('completed') OR coalesce(pr.realized_payment_count, 0) > 0 THEN false
      WHEN base.stage IN ('dead','spam','archived') THEN false
      ELSE coalesce(tp.estimated_pipeline_value, 0) > 0
    END AS counts_as_open_pipeline,
    coalesce(base.inventory_group_id, base.inventory_uid, base.listing_id::text, 'thread:' || base.canonical_conversation_thread_id::text) AS open_pipeline_opportunity_key,
    1.0::numeric AS pipeline_attribution_weight
  FROM canonical_threads base
  JOIN canonical_rollup cr ON cr.canonical_conversation_thread_id = base.canonical_conversation_thread_id
  LEFT JOIN payment_rollup pr ON pr.canonical_conversation_thread_id = base.canonical_conversation_thread_id
  LEFT JOIN thread_price tp ON tp.canonical_conversation_thread_id = base.canonical_conversation_thread_id
  LEFT JOIN tag_rollup tr ON tr.canonical_conversation_thread_id = base.canonical_conversation_thread_id
  WHERE base.conversation_thread_id = base.canonical_conversation_thread_id
), opportunity_rollup AS (
  SELECT
    open_pipeline_opportunity_key,
    sum(pipeline_attribution_weight) AS total_weight,
    count(*) AS open_pipeline_thread_count_for_opportunity,
    (
      sum(estimated_pipeline_value * pipeline_attribution_weight)
      / nullif(sum(pipeline_attribution_weight), 0)
    )::numeric(12,2) AS open_pipeline_opportunity_value_unweighted
  FROM thread_base
  WHERE counts_as_open_pipeline
  GROUP BY open_pipeline_opportunity_key
)
SELECT
  tb.*,
  coalesce(opp.open_pipeline_thread_count_for_opportunity, 0) AS open_pipeline_thread_count_for_opportunity,
  coalesce(opp.open_pipeline_opportunity_value_unweighted, 0)::numeric(12,2) AS open_pipeline_opportunity_value_unweighted,
  CASE
    WHEN tb.counts_as_open_pipeline THEN (
      opp.open_pipeline_opportunity_value_unweighted
      * tb.pipeline_attribution_weight
      / nullif(opp.total_weight, 0)
    )::numeric(12,2)
    ELSE 0::numeric(12,2)
  END AS attributed_open_pipeline_value_unweighted
FROM thread_base tb
LEFT JOIN opportunity_rollup opp USING (open_pipeline_opportunity_key);

COMMENT ON VIEW public.lead_source_funnel_thread_metrics IS
  'AWF-188: One row per canonical conversation thread. Realized revenue is allocated by cash_flow row to avoid double-counting across matched threads. Open pipeline is opportunity/item-level: same-item open leads share one weighted-average item value instead of each counting full list price.';

CREATE VIEW public.lead_source_funnel_metrics AS
SELECT
  lead_source,
  platform,
  count(*) AS canonical_thread_count,
  count(*) FILTER (WHERE purpose = 'sale_inquiry') AS sale_inquiry_thread_count,
  count(*) FILTER (WHERE stage IN ('new','needs_reply','negotiating','scheduled','waiting_on_other_party')) AS active_thread_count,
  count(*) FILTER (WHERE stage = 'completed') AS completed_thread_count,
  count(*) FILTER (WHERE stage IN ('dead','spam','archived')) AS closed_lost_or_archived_thread_count,
  sum(source_thread_count) AS source_thread_count_including_merged,
  sum(merged_source_thread_count) AS merged_source_thread_count,
  count(*) FILTER (WHERE has_realized_revenue) AS realized_revenue_thread_count,
  coalesce(sum(realized_revenue), 0)::numeric(12,2) AS realized_revenue,
  count(*) FILTER (WHERE counts_as_open_pipeline) AS open_pipeline_thread_count,
  count(DISTINCT open_pipeline_opportunity_key) FILTER (WHERE counts_as_open_pipeline) AS open_pipeline_opportunity_count,
  coalesce(sum(attributed_open_pipeline_value_unweighted) FILTER (WHERE counts_as_open_pipeline), 0)::numeric(12,2) AS open_pipeline_value_unweighted,
  coalesce(avg(attributed_open_pipeline_value_unweighted) FILTER (WHERE counts_as_open_pipeline), 0)::numeric(12,2) AS avg_open_pipeline_value_unweighted,
  round((100.0 * count(*) FILTER (WHERE has_realized_revenue) / nullif(count(*), 0))::numeric, 2) AS realized_conversion_rate_pct
FROM public.lead_source_funnel_thread_metrics
GROUP BY lead_source, platform;

COMMENT ON VIEW public.lead_source_funnel_metrics IS
  'AWF-188: Lead-source funnel rollup. Realized revenue and open pipeline values are attributed so the same sale/item opportunity is not double-counted across conversations/channels.';

COMMIT;
