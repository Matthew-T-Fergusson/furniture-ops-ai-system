-- 015_listing_stage_status_tracking.sql
-- AWF-142: listing stage/status tracking across marketplaces.
--
-- Decisions:
-- - Track both current listing lifecycle status and status history.
-- - Store platform-specific details in notes/json context, not exploding generic statuses.
-- - `active_verified` requires successful link/API/browser readback, or human verification where automation cannot verify.
-- - Continue through individual failures, but pause/review a platform/account after 7 consecutive failures.
-- - Dashboard needs active-verified coverage, per-platform status, stale verification, ready-but-not-live, and failed/blocked views.
-- - If not verified, marketplace reality is not `active_verified`; inventory/listing state should be corrected or flagged.

BEGIN;

ALTER TABLE public.listings
  DROP CONSTRAINT IF EXISTS listings_status_chk;

ALTER TABLE public.listings
  ADD CONSTRAINT listings_status_chk CHECK (status IN (
    -- legacy/current statuses retained for backward compatibility
    'draft','active','paused','pending','sold','delisted','cancelled','expired','relist_needed',
    -- AWF-142 lifecycle statuses
    'needs_photos','needs_measurements','profile_ready','ready_to_post','drafted',
    'posted_unverified','active_verified','active_needs_review',
    'failed_needs_correction','blocked_by_platform','cooldown_wait','flagged_or_restricted',
    'pending_sale'
  ));

ALTER TABLE public.listings
  ADD COLUMN IF NOT EXISTS status_verified_at timestamptz,
  ADD COLUMN IF NOT EXISTS status_verified_by text,
  ADD COLUMN IF NOT EXISTS status_verification_method text,
  ADD COLUMN IF NOT EXISTS status_verification_url text,
  ADD COLUMN IF NOT EXISTS platform_account_ref text,
  ADD COLUMN IF NOT EXISTS consecutive_failure_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS platform_pause_required boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS status_context jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.listings
  DROP CONSTRAINT IF EXISTS listings_verification_method_chk;
ALTER TABLE public.listings
  ADD CONSTRAINT listings_verification_method_chk CHECK (
    status_verification_method IS NULL OR status_verification_method IN (
      'programmatic_link_readback','browser_readback','api_readback','human_verified','not_required','unknown'
    )
  );

COMMENT ON COLUMN public.listings.status_verified_at IS
  'AWF-142: last time current listing status was verified by link/API/browser readback or human verification.';
COMMENT ON COLUMN public.listings.status_verified_by IS
  'AWF-142: actor who verified current listing status, e.g. Lex, Matt, Stephen, CI synthetic seed.';
COMMENT ON COLUMN public.listings.status_verification_method IS
  'AWF-142: how current listing status was verified. active_verified requires readback or human verification.';
COMMENT ON COLUMN public.listings.status_verification_url IS
  'AWF-142: URL or stable source checked during listing status verification when safe to store.';
COMMENT ON COLUMN public.listings.platform_account_ref IS
  'AWF-142: sanitized platform/account reference for platform-level pause/failure tracking; do not store credentials.';
COMMENT ON COLUMN public.listings.consecutive_failure_count IS
  'AWF-142: consecutive posting/verification failures for this listing/platform/account context. Initial platform/account pause threshold is 7.';
COMMENT ON COLUMN public.listings.platform_pause_required IS
  'AWF-142: true when repeated failures/flags should pause that platform/account for human review.';
COMMENT ON COLUMN public.listings.status_context IS
  'AWF-142: platform-specific status/verifier context as JSONB without expanding generic status taxonomy.';

CREATE TABLE IF NOT EXISTS public.listing_status_history (
  listing_status_history_id bigserial PRIMARY KEY,
  listing_id bigint NOT NULL REFERENCES public.listings(listing_id),
  inventory_uid text NOT NULL REFERENCES public.inventory(inventory_uid),
  platform text NOT NULL,
  old_status text,
  new_status text NOT NULL,
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by text NOT NULL DEFAULT 'agent',
  verification_method text,
  verification_url text,
  verified_at timestamptz,
  platform_account_ref text,
  consecutive_failure_count integer,
  platform_pause_required boolean NOT NULL DEFAULT false,
  reason text,
  notes text,
  context jsonb NOT NULL DEFAULT '{}'::jsonb,
  source_system text NOT NULL DEFAULT 'manual',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT listing_status_history_status_chk CHECK (new_status IN (
    'draft','active','paused','pending','sold','delisted','cancelled','expired','relist_needed',
    'needs_photos','needs_measurements','profile_ready','ready_to_post','drafted',
    'posted_unverified','active_verified','active_needs_review',
    'failed_needs_correction','blocked_by_platform','cooldown_wait','flagged_or_restricted',
    'pending_sale'
  ) AND (old_status IS NULL OR old_status IN (
    'draft','active','paused','pending','sold','delisted','cancelled','expired','relist_needed',
    'needs_photos','needs_measurements','profile_ready','ready_to_post','drafted',
    'posted_unverified','active_verified','active_needs_review',
    'failed_needs_correction','blocked_by_platform','cooldown_wait','flagged_or_restricted',
    'pending_sale'
  ))),
  CONSTRAINT listing_status_history_verification_method_chk CHECK (
    verification_method IS NULL OR verification_method IN (
      'programmatic_link_readback','browser_readback','api_readback','human_verified','not_required','unknown'
    )
  )
);

COMMENT ON TABLE public.listing_status_history IS
  'AWF-142: history of marketplace listing status/stage transitions. Use this to see where listing workflows stall, fail, require relist, or verify active state.';
CREATE INDEX IF NOT EXISTS idx_lsh_listing_at ON public.listing_status_history(listing_id, changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_lsh_inventory_at ON public.listing_status_history(inventory_uid, changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_lsh_platform_status_at ON public.listing_status_history(platform, new_status, changed_at DESC);
CREATE INDEX IF NOT EXISTS idx_lsh_platform_pause ON public.listing_status_history(platform, platform_account_ref, platform_pause_required);

CREATE OR REPLACE VIEW public.listing_status_dashboard AS
SELECT
  l.listing_id,
  l.inventory_uid,
  l.inventory_group_id,
  i.item_title,
  i.status AS inventory_status,
  l.platform,
  l.market_region,
  l.platform_account_ref,
  l.external_listing_id,
  l.listing_url,
  l.title,
  l.status AS listing_status,
  l.current_asking_price,
  l.listed_at,
  l.status_verified_at,
  l.status_verified_by,
  l.status_verification_method,
  l.status_reason,
  l.consecutive_failure_count,
  l.platform_pause_required,
  l.status_context,
  CASE WHEN l.status = 'active_verified' THEN true ELSE false END AS is_active_verified,
  CASE
    WHEN l.status = 'active_verified' AND l.status_verified_at IS NULL THEN true
    WHEN l.status = 'active_verified' AND l.status_verification_method IS NULL THEN true
    WHEN l.status IN ('active','posted_unverified') THEN true
    ELSE false
  END AS needs_verification,
  CASE
    WHEN l.status_verified_at IS NULL THEN NULL
    ELSE round((EXTRACT(epoch FROM (now() - l.status_verified_at)) / 3600.0)::numeric, 2)
  END AS hours_since_verification,
  CASE
    WHEN l.status = 'active_verified'
      AND (l.status_verified_at IS NULL OR l.status_verified_at <= now() - interval '7 days')
      THEN true
    ELSE false
  END AS stale_verification,
  CASE
    WHEN i.status = 'listed_active' AND l.status <> 'active_verified' THEN true
    ELSE false
  END AS inventory_listing_status_mismatch,
  CASE
    WHEN i.status IN ('ready_to_list','listed_active')
      AND l.status IN ('needs_photos','needs_measurements','profile_ready','ready_to_post','drafted','posted_unverified','failed_needs_correction','blocked_by_platform','cooldown_wait','flagged_or_restricted','relist_needed')
      THEN true
    ELSE false
  END AS ready_but_not_live,
  CASE WHEN l.status IN ('failed_needs_correction','blocked_by_platform','cooldown_wait','flagged_or_restricted') THEN true ELSE false END AS failed_or_blocked
FROM public.listings l
JOIN public.inventory i ON i.inventory_uid = l.inventory_uid
WHERE coalesce(l.is_current_version, true) IS TRUE;

COMMENT ON VIEW public.listing_status_dashboard IS
  'AWF-142: dashboard-ready listing status view for active verified coverage, per-platform status, stale verification, ready-but-not-live rows, failed/blocked rows, and inventory/listing mismatch flags.';

CREATE OR REPLACE VIEW public.listing_platform_status_summary AS
SELECT
  platform,
  count(*) AS listing_count,
  count(*) FILTER (WHERE listing_status = 'active_verified') AS active_verified_count,
  count(*) FILTER (WHERE needs_verification) AS needs_verification_count,
  count(*) FILTER (WHERE stale_verification) AS stale_verification_count,
  count(*) FILTER (WHERE ready_but_not_live) AS ready_but_not_live_count,
  count(*) FILTER (WHERE failed_or_blocked) AS failed_or_blocked_count,
  count(*) FILTER (WHERE platform_pause_required) AS platform_pause_required_count,
  count(*) FILTER (WHERE inventory_listing_status_mismatch) AS inventory_listing_status_mismatch_count
FROM public.listing_status_dashboard
GROUP BY platform;

COMMENT ON VIEW public.listing_platform_status_summary IS
  'AWF-142: platform-level status coverage summary for listing operations dashboards.';

COMMIT;
