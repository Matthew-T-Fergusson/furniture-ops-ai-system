-- 018_awf188_conversation_tags_merge_funnel.sql
-- AWF-188: conversation tags, thread merge support, and lead-source funnel analytics.
--
-- Product decisions:
-- - Additive-only CRM changes; existing operational tables remain canonical.
-- - Realized revenue is strict/payment-only: logged cash_flows Payment/Sale rows.
-- - Pipeline value is separate and unweighted; it must never be mixed with realized revenue.
-- - Merged-away threads remain auditable but funnel/queue consumers should group by
--   canonical_conversation_thread_id.

BEGIN;

ALTER TABLE public.conversation_threads
  ADD COLUMN IF NOT EXISTS merged_into_thread_id bigint REFERENCES public.conversation_threads(conversation_thread_id),
  ADD COLUMN IF NOT EXISTS merged_at timestamptz,
  ADD COLUMN IF NOT EXISTS merged_by text,
  ADD COLUMN IF NOT EXISTS merge_reason text;

ALTER TABLE public.conversation_threads
  DROP CONSTRAINT IF EXISTS conversation_threads_no_self_merge_chk;
ALTER TABLE public.conversation_threads
  ADD CONSTRAINT conversation_threads_no_self_merge_chk
  CHECK (merged_into_thread_id IS NULL OR merged_into_thread_id <> conversation_thread_id);

COMMENT ON COLUMN public.conversation_threads.merged_into_thread_id IS
  'AWF-188: If this thread is a duplicate/child, points to the canonical conversation_thread_id. Do not delete merged-away rows; preserve history.';
COMMENT ON COLUMN public.conversation_threads.merged_at IS
  'AWF-188: Timestamp when this thread was merged into another thread.';
COMMENT ON COLUMN public.conversation_threads.merged_by IS
  'AWF-188: Human/system actor that performed the thread merge.';
COMMENT ON COLUMN public.conversation_threads.merge_reason IS
  'AWF-188: Short reason for merge, e.g. duplicate marketplace thread, same buyer/listing, relay-to-chat continuation.';

CREATE INDEX IF NOT EXISTS idx_conversation_threads_merged_into
  ON public.conversation_threads(merged_into_thread_id)
  WHERE merged_into_thread_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.conversation_tags (
  conversation_tag_id bigserial PRIMARY KEY,
  tag_key text NOT NULL UNIQUE,
  display_name text NOT NULL,
  category text NOT NULL DEFAULT 'general',
  description text,
  color text,
  active boolean NOT NULL DEFAULT true,
  created_by text NOT NULL DEFAULT 'lex',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT conversation_tags_key_chk CHECK (tag_key ~ '^[a-z0-9][a-z0-9_:-]*$'),
  CONSTRAINT conversation_tags_category_chk CHECK (category IN ('lead_quality','sales_stage','logistics','source','ops','risk','general'))
);

COMMENT ON TABLE public.conversation_tags IS
  'AWF-188: Controlled tag dictionary for CRM thread labels. Tags supplement, not replace, canonical stage/lead_quality fields.';

CREATE TABLE IF NOT EXISTS public.conversation_thread_tags (
  conversation_thread_id bigint NOT NULL REFERENCES public.conversation_threads(conversation_thread_id) ON DELETE CASCADE,
  conversation_tag_id bigint NOT NULL REFERENCES public.conversation_tags(conversation_tag_id),
  tagged_at timestamptz NOT NULL DEFAULT now(),
  tagged_by text NOT NULL DEFAULT 'lex',
  note text,
  PRIMARY KEY (conversation_thread_id, conversation_tag_id)
);

COMMENT ON TABLE public.conversation_thread_tags IS
  'AWF-188: Many-to-many CRM tags on conversation threads. Merged-away tags remain on original threads and are also surfaced through canonical rollups.';

CREATE INDEX IF NOT EXISTS idx_conversation_thread_tags_tag
  ON public.conversation_thread_tags(conversation_tag_id, tagged_at DESC);

INSERT INTO public.conversation_tags (tag_key, display_name, category, description, color, created_by) VALUES
  ('hot_lead', 'Hot lead', 'lead_quality', 'High-intent buyer/source requiring strong follow-through.', 'red', 'awf188_seed'),
  ('low_intent', 'Low intent', 'lead_quality', 'Weak buyer signal or casual inquiry.', 'gray', 'awf188_seed'),
  ('price_objection', 'Price objection', 'sales_stage', 'Conversation includes a price complaint/counteroffer.', 'orange', 'awf188_seed'),
  ('pickup_scheduling', 'Pickup scheduling', 'logistics', 'Thread includes pickup or delivery scheduling work.', 'blue', 'awf188_seed'),
  ('needs_merge_review', 'Needs merge review', 'ops', 'Possible duplicate thread that should be reviewed before merging.', 'purple', 'awf188_seed'),
  ('dnc_risk', 'DNC risk', 'risk', 'Conversation/contact may require do-not-contact review.', 'black', 'awf188_seed')
ON CONFLICT (tag_key) DO NOTHING;

DROP VIEW IF EXISTS public.conversation_thread_tag_rollup;
DROP VIEW IF EXISTS public.lead_source_funnel_metrics;
DROP VIEW IF EXISTS public.lead_source_funnel_thread_metrics;
DROP VIEW IF EXISTS public.canonical_conversation_threads;

CREATE VIEW public.canonical_conversation_threads AS
WITH RECURSIVE merge_walk AS (
  SELECT
    t.conversation_thread_id AS original_conversation_thread_id,
    t.conversation_thread_id AS current_conversation_thread_id,
    t.merged_into_thread_id,
    ARRAY[t.conversation_thread_id] AS path,
    0 AS depth
  FROM public.conversation_threads t

  UNION ALL

  SELECT
    mw.original_conversation_thread_id,
    parent.conversation_thread_id AS current_conversation_thread_id,
    parent.merged_into_thread_id,
    mw.path || parent.conversation_thread_id,
    mw.depth + 1
  FROM merge_walk mw
  JOIN public.conversation_threads parent
    ON parent.conversation_thread_id = mw.merged_into_thread_id
  WHERE mw.merged_into_thread_id IS NOT NULL
    AND NOT parent.conversation_thread_id = ANY(mw.path)
    AND mw.depth < 20
), canonical AS (
  SELECT DISTINCT ON (original_conversation_thread_id)
    original_conversation_thread_id,
    current_conversation_thread_id AS canonical_conversation_thread_id,
    depth AS merge_depth,
    path AS merge_path
  FROM merge_walk
  WHERE merged_into_thread_id IS NULL
     OR depth = 20
  ORDER BY original_conversation_thread_id, depth DESC
)
SELECT
  t.*,
  c.canonical_conversation_thread_id,
  (t.merged_into_thread_id IS NOT NULL) AS is_merged_away,
  c.merge_depth,
  c.merge_path
FROM public.conversation_threads t
JOIN canonical c ON c.original_conversation_thread_id = t.conversation_thread_id;

COMMENT ON VIEW public.canonical_conversation_threads IS
  'AWF-188: Conversation threads with resolved canonical_conversation_thread_id for merge-aware queue/funnel reporting. Merged-away source rows remain auditable.';

CREATE VIEW public.conversation_thread_tag_rollup AS
SELECT
  cct.canonical_conversation_thread_id,
  ctt.conversation_thread_id AS tagged_conversation_thread_id,
  array_agg(DISTINCT ct.tag_key ORDER BY ct.tag_key) AS tag_keys,
  jsonb_agg(
    DISTINCT jsonb_build_object(
      'tag_key', ct.tag_key,
      'display_name', ct.display_name,
      'category', ct.category,
      'tagged_thread_id', ctt.conversation_thread_id
    )
  ) AS tags_json
FROM public.conversation_thread_tags ctt
JOIN public.conversation_tags ct ON ct.conversation_tag_id = ctt.conversation_tag_id
JOIN public.canonical_conversation_threads cct ON cct.conversation_thread_id = ctt.conversation_thread_id
WHERE ct.active
GROUP BY cct.canonical_conversation_thread_id, ctt.conversation_thread_id;

COMMENT ON VIEW public.conversation_thread_tag_rollup IS
  'AWF-188: Active tag rollup by canonical thread and original tagged thread.';

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
), payment_rollup AS (
  SELECT
    canonical_conversation_thread_id,
    sum(amount)::numeric(12,2) AS realized_revenue,
    count(*) AS realized_payment_count,
    max(txn_date) AS latest_realized_payment_date
  FROM payment_candidates
  GROUP BY canonical_conversation_thread_id
), pipeline_rollup AS (
  SELECT
    ct.canonical_conversation_thread_id,
    max(coalesce(l.current_asking_price, i.expected_sale_price, i.list_price_target))::numeric(12,2) AS estimated_pipeline_value,
    max(l.current_asking_price)::numeric(12,2) AS listing_asking_price,
    max(coalesce(i.expected_sale_price, i.list_price_target))::numeric(12,2) AS inventory_expected_price
  FROM canonical_threads ct
  LEFT JOIN public.listings l ON l.listing_id = ct.listing_id
  LEFT JOIN public.inventory i ON i.inventory_uid = ct.inventory_uid
  GROUP BY ct.canonical_conversation_thread_id
), tag_rollup AS (
  SELECT
    cct.canonical_conversation_thread_id,
    array_agg(DISTINCT ct.tag_key ORDER BY ct.tag_key) AS tag_keys
  FROM public.conversation_thread_tags ctt
  JOIN public.conversation_tags ct ON ct.conversation_tag_id = ctt.conversation_tag_id
  JOIN public.canonical_conversation_threads cct ON cct.conversation_thread_id = ctt.conversation_thread_id
  WHERE ct.active
  GROUP BY cct.canonical_conversation_thread_id
)
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
  coalesce(pl.estimated_pipeline_value, 0)::numeric(12,2) AS estimated_pipeline_value,
  pl.listing_asking_price,
  pl.inventory_expected_price,
  CASE WHEN coalesce(pr.realized_payment_count, 0) > 0 THEN true ELSE false END AS has_realized_revenue,
  CASE
    WHEN base.stage IN ('completed') OR coalesce(pr.realized_payment_count, 0) > 0 THEN false
    WHEN base.stage IN ('dead','spam','archived') THEN false
    ELSE coalesce(pl.estimated_pipeline_value, 0) > 0
  END AS counts_as_open_pipeline
FROM canonical_threads base
JOIN canonical_rollup cr ON cr.canonical_conversation_thread_id = base.canonical_conversation_thread_id
LEFT JOIN payment_rollup pr ON pr.canonical_conversation_thread_id = base.canonical_conversation_thread_id
LEFT JOIN pipeline_rollup pl ON pl.canonical_conversation_thread_id = base.canonical_conversation_thread_id
LEFT JOIN tag_rollup tr ON tr.canonical_conversation_thread_id = base.canonical_conversation_thread_id
WHERE base.conversation_thread_id = base.canonical_conversation_thread_id;

COMMENT ON VIEW public.lead_source_funnel_thread_metrics IS
  'AWF-188: One row per canonical conversation thread. Realized revenue is strict Payment/Sale cash_flows only; open pipeline value is separate and unweighted.';

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
  coalesce(sum(estimated_pipeline_value) FILTER (WHERE counts_as_open_pipeline), 0)::numeric(12,2) AS open_pipeline_value_unweighted,
  coalesce(avg(estimated_pipeline_value) FILTER (WHERE counts_as_open_pipeline), 0)::numeric(12,2) AS avg_open_pipeline_value_unweighted,
  round((100.0 * count(*) FILTER (WHERE has_realized_revenue) / nullif(count(*), 0))::numeric, 2) AS realized_conversion_rate_pct
FROM public.lead_source_funnel_thread_metrics
GROUP BY lead_source, platform;

COMMENT ON VIEW public.lead_source_funnel_metrics IS
  'AWF-188: Lead-source funnel rollup. Realized revenue and unweighted open pipeline value are intentionally separate metrics.';

COMMIT;
