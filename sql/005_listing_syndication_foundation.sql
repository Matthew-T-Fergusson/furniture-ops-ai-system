-- 005_listing_syndication_foundation.sql
-- //Add listing scrape, media, marketplace, pricing, and publication-queue foundation.
--
-- Preflight/readback plan:
-- 1. Run: make ci-smoke
-- 2. Apply: apply ordered sql/*.sql in a database session
-- 3. Readback SQL:
--    SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_name IN
--      ('listing_events','listing_content_snapshots','listing_media_assets','image_match_candidates','marketplace_platforms','marketplace_pricing_rules','listing_price_quotes','listing_publication_queue')
--      ORDER BY table_name;
--
-- Policy:
-- - Additive only.
-- - Existing listing rows remain canonical current-state rows.
-- - Historical/event tables make price/status/content history queryable without replacing listing_price_history.

BEGIN;

ALTER TABLE public.listings
  ADD COLUMN IF NOT EXISTS market_region text,
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz,
  ADD COLUMN IF NOT EXISTS not_found_at timestamptz,
  ADD COLUMN IF NOT EXISTS expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS ended_at timestamptz,
  ADD COLUMN IF NOT EXISTS status_reason text,
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS location_text text,
  ADD COLUMN IF NOT EXISTS dimensions_raw text,
  ADD COLUMN IF NOT EXISTS parsed_length_in numeric(10,2),
  ADD COLUMN IF NOT EXISTS parsed_width_in numeric(10,2),
  ADD COLUMN IF NOT EXISTS parsed_height_in numeric(10,2),
  ADD COLUMN IF NOT EXISTS listing_content_hash text,
  ADD COLUMN IF NOT EXISTS reuse_approved boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.listings.market_region IS
  'Marketplace/city/region for platform listing, e.g. washingtondc, baltimore, richmond. Multi-city Craigslist posts should be separate listings rows.';
COMMENT ON COLUMN public.listings.last_seen_at IS
  'Last time a scraper or human confirmed the external listing was visible.';
COMMENT ON COLUMN public.listings.not_found_at IS
  'First/most recent time a scraper found the external listing unavailable/not found.';
COMMENT ON COLUMN public.listings.expires_at IS
  'Known or inferred external listing expiry timestamp, if available.';
COMMENT ON COLUMN public.listings.ended_at IS
  'Timestamp the listing lifecycle ended for analysis, separate from status text.';
COMMENT ON COLUMN public.listings.status_reason IS
  'Human or automation-readable reason for current listing status.';
COMMENT ON COLUMN public.listings.description IS
  'Current normalized listing body/copy suitable for reuse after human review.';
COMMENT ON COLUMN public.listings.location_text IS
  'Current marketplace-visible location text scraped or manually entered.';
COMMENT ON COLUMN public.listings.dimensions_raw IS
  'Raw dimension text captured from listing copy before normalization.';
COMMENT ON COLUMN public.listings.parsed_length_in IS
  'Parsed item length in inches when confidently extracted from listing copy.';
COMMENT ON COLUMN public.listings.parsed_width_in IS
  'Parsed item width/depth in inches when confidently extracted from listing copy.';
COMMENT ON COLUMN public.listings.parsed_height_in IS
  'Parsed item height in inches when confidently extracted from listing copy.';
COMMENT ON COLUMN public.listings.listing_content_hash IS
  'Hash of current normalized listing content used to detect meaningful changes.';
COMMENT ON COLUMN public.listings.reuse_approved IS
  'Whether listing copy/media has been reviewed and approved for reuse on other platforms.';

CREATE INDEX IF NOT EXISTS idx_listings_platform_region ON public.listings(platform, market_region);
CREATE INDEX IF NOT EXISTS idx_listings_last_seen ON public.listings(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_listings_content_hash ON public.listings(listing_content_hash);

CREATE TABLE IF NOT EXISTS public.listing_events (
  listing_event_id bigserial PRIMARY KEY,
  listing_id bigint NOT NULL REFERENCES public.listings(listing_id),
  inventory_uid text NOT NULL REFERENCES public.inventory(inventory_uid),
  event_type text NOT NULL,
  event_at timestamptz NOT NULL DEFAULT now(),
  old_status text,
  new_status text,
  old_price numeric(12,2),
  new_price numeric(12,2),
  old_content_hash text,
  new_content_hash text,
  source_system text NOT NULL DEFAULT 'manual',
  actor text NOT NULL DEFAULT 'lex',
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT listing_events_type_chk CHECK (event_type IN ('created','scraped','content_changed','price_changed','status_changed','relisted','manual_note','queued','published','not_found','expired'))
);
COMMENT ON TABLE public.listing_events IS
  'Query-friendly long table for listing lifecycle/content/price/status events. Use alongside listing_price_history for pricing analysis.';
CREATE INDEX IF NOT EXISTS idx_listing_events_listing_at ON public.listing_events(listing_id, event_at);
CREATE INDEX IF NOT EXISTS idx_listing_events_inventory_at ON public.listing_events(inventory_uid, event_at);
CREATE INDEX IF NOT EXISTS idx_listing_events_type ON public.listing_events(event_type);

CREATE TABLE IF NOT EXISTS public.listing_content_snapshots (
  snapshot_id bigserial PRIMARY KEY,
  listing_id bigint NOT NULL REFERENCES public.listings(listing_id),
  inventory_uid text NOT NULL REFERENCES public.inventory(inventory_uid),
  platform text NOT NULL DEFAULT 'craigslist',
  external_listing_id text,
  listing_url text,
  scraped_at timestamptz NOT NULL DEFAULT now(),
  title text,
  description text,
  price numeric(12,2),
  location_text text,
  dimensions_raw text,
  parsed_length_in numeric(10,2),
  parsed_width_in numeric(10,2),
  parsed_height_in numeric(10,2),
  content_hash text,
  raw_html_path text,
  source_status text,
  source_system text NOT NULL DEFAULT 'scrape_craigslist_listing_profiles.py',
  created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.listing_content_snapshots IS
  'Versioned raw/normalized scrape evidence. Supporting capture for sourcing/listing reuse; not the primary analytical price-history table.';
CREATE INDEX IF NOT EXISTS idx_lcs_listing_scraped ON public.listing_content_snapshots(listing_id, scraped_at DESC);
CREATE INDEX IF NOT EXISTS idx_lcs_content_hash ON public.listing_content_snapshots(content_hash);

CREATE TABLE IF NOT EXISTS public.listing_media_assets (
  media_id bigserial PRIMARY KEY,
  inventory_uid text NOT NULL REFERENCES public.inventory(inventory_uid),
  listing_id bigint REFERENCES public.listings(listing_id),
  platform text,
  external_media_id text,
  source_url text,
  local_path text NOT NULL,
  source_quality text NOT NULL DEFAULT 'unknown',
  media_type text NOT NULL DEFAULT 'image',
  sort_order integer,
  sha256 text,
  perceptual_hash text,
  width_px integer,
  height_px integer,
  file_size_bytes bigint,
  captured_at timestamptz NOT NULL DEFAULT now(),
  active boolean NOT NULL DEFAULT true,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT listing_media_quality_chk CHECK (source_quality IN ('craigslist_low_res','stephen_original_high_res','other_platform','manual_upload','unknown'))
);
COMMENT ON TABLE public.listing_media_assets IS
  'File/database mapping for listing photos and other media, including Craigslist low-res and later the operator high-res originals.';
CREATE INDEX IF NOT EXISTS idx_lma_inventory ON public.listing_media_assets(inventory_uid);
CREATE INDEX IF NOT EXISTS idx_lma_listing ON public.listing_media_assets(listing_id);
CREATE INDEX IF NOT EXISTS idx_lma_sha256 ON public.listing_media_assets(sha256);
CREATE INDEX IF NOT EXISTS idx_lma_phash ON public.listing_media_assets(perceptual_hash);

CREATE TABLE IF NOT EXISTS public.image_match_candidates (
  candidate_id bigserial PRIMARY KEY,
  source_media_id bigint NOT NULL REFERENCES public.listing_media_assets(media_id),
  candidate_media_id bigint NOT NULL REFERENCES public.listing_media_assets(media_id),
  match_method text NOT NULL,
  score numeric(10,6),
  review_status text NOT NULL DEFAULT 'pending',
  reviewed_by text,
  reviewed_at timestamptz,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT image_match_review_status_chk CHECK (review_status IN ('pending','accepted','rejected','needs_review'))
);
COMMENT ON TABLE public.image_match_candidates IS
  'Local near-duplicate image matching candidates before human/vision review. Prefer local hashing/embeddings before token-based vision.';
CREATE INDEX IF NOT EXISTS idx_imc_source ON public.image_match_candidates(source_media_id);
CREATE INDEX IF NOT EXISTS idx_imc_candidate ON public.image_match_candidates(candidate_media_id);
CREATE INDEX IF NOT EXISTS idx_imc_review_status ON public.image_match_candidates(review_status);

CREATE TABLE IF NOT EXISTS public.marketplace_platforms (
  platform text PRIMARY KEY,
  display_name text NOT NULL,
  status text NOT NULL DEFAULT 'prospective',
  posting_priority integer,
  automation_risk text NOT NULL DEFAULT 'unknown',
  rate_limit_notes text,
  posting_requirements_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  credential_secret_ref text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT marketplace_platform_status_chk CHECK (status IN ('active','prospective','paused','retired')),
  CONSTRAINT marketplace_platform_risk_chk CHECK (automation_risk IN ('low','medium','high','manual_only','unknown'))
);
COMMENT ON TABLE public.marketplace_platforms IS
  'Marketplace/platform catalog with automation risk, posting requirements, and credential references only. Do not store raw passwords here.';

INSERT INTO public.marketplace_platforms (platform, display_name, status, posting_priority, automation_risk, notes)
VALUES
  ('craigslist','Craigslist','active',1,'medium','Active channel. Use slow randomized pacing and respect region/posting rules.'),
  ('facebook_marketplace','Facebook Marketplace','active',2,'high','Active/proven channel but account-risk/manual-review heavy; automation likely constrained.'),
  ('ebay','eBay / eBay Local','prospective',3,'medium','Prospective channel; evaluate fees, local pickup/delivery support, and listing automation rules.'),
  ('chairish','Chairish','prospective',4,'medium','Prospective higher-end furniture channel; evaluate fee schedule and intake requirements.'),
  ('aptdeco','AptDeco','prospective',5,'medium','Prospective furniture marketplace; evaluate geography, fees, and logistics model.'),
  ('offerup','OfferUp','prospective',6,'high','Prospective local marketplace; evaluate automation/account-risk constraints.'),
  ('nextdoor','Nextdoor','prospective',7,'high','Prospective local channel; likely manual/account-risk constrained.')
ON CONFLICT (platform) DO UPDATE
SET display_name = EXCLUDED.display_name,
    status = EXCLUDED.status,
    posting_priority = EXCLUDED.posting_priority,
    automation_risk = EXCLUDED.automation_risk,
    notes = EXCLUDED.notes,
    updated_at = now();

CREATE TABLE IF NOT EXISTS public.marketplace_pricing_rules (
  rule_id bigserial PRIMARY KEY,
  platform text NOT NULL REFERENCES public.marketplace_platforms(platform),
  market_region text,
  status text NOT NULL DEFAULT 'active',
  base_price_source text NOT NULL DEFAULT 'inventory.list_price_target',
  platform_fee_pct numeric(8,4) NOT NULL DEFAULT 0,
  platform_fixed_fee numeric(12,2) NOT NULL DEFAULT 0,
  delivery_fee_basis text NOT NULL DEFAULT 'manual',
  delivery_cost_estimate numeric(12,2) NOT NULL DEFAULT 0,
  markup_pct numeric(8,4) NOT NULL DEFAULT 0,
  minimum_margin_pct numeric(8,4),
  rounding_rule text DEFAULT 'nearest_25',
  floor_price numeric(12,2),
  ceiling_price numeric(12,2),
  effective_start date NOT NULL DEFAULT current_date,
  effective_end date,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT marketplace_pricing_rule_status_chk CHECK (status IN ('active','draft','paused','retired')),
  CONSTRAINT marketplace_pricing_delivery_basis_chk CHECK (delivery_fee_basis IN ('manual','mileage','zone','flat','none'))
);
COMMENT ON TABLE public.marketplace_pricing_rules IS
  'Platform/geography pricing rules for delivery cost, platform fees, markups, rounding, floors/ceilings, and target margin preservation.';
CREATE INDEX IF NOT EXISTS idx_mpr_platform_region ON public.marketplace_pricing_rules(platform, market_region, status);

CREATE TABLE IF NOT EXISTS public.listing_price_quotes (
  quote_id bigserial PRIMARY KEY,
  inventory_uid text NOT NULL REFERENCES public.inventory(inventory_uid),
  platform text NOT NULL REFERENCES public.marketplace_platforms(platform),
  market_region text,
  rule_id bigint REFERENCES public.marketplace_pricing_rules(rule_id),
  base_price numeric(12,2) NOT NULL,
  delivery_adjustment numeric(12,2) NOT NULL DEFAULT 0,
  platform_fee_adjustment numeric(12,2) NOT NULL DEFAULT 0,
  markup_adjustment numeric(12,2) NOT NULL DEFAULT 0,
  recommended_price numeric(12,2) NOT NULL,
  target_margin_pct numeric(8,4),
  generated_at timestamptz NOT NULL DEFAULT now(),
  approved_by text,
  approved_at timestamptz,
  used_for_listing_id bigint REFERENCES public.listings(listing_id),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.listing_price_quotes IS
  'Generated/reviewed price recommendations explaining how platform fees, geography/delivery, markup, and margin targets produced a listing price.';
CREATE INDEX IF NOT EXISTS idx_lpq_inventory_generated ON public.listing_price_quotes(inventory_uid, generated_at DESC);
CREATE INDEX IF NOT EXISTS idx_lpq_platform_region ON public.listing_price_quotes(platform, market_region);

CREATE TABLE IF NOT EXISTS public.listing_publication_queue (
  queue_id bigserial PRIMARY KEY,
  inventory_uid text NOT NULL REFERENCES public.inventory(inventory_uid),
  platform text NOT NULL REFERENCES public.marketplace_platforms(platform),
  market_region text,
  desired_action text NOT NULL DEFAULT 'create_listing',
  status text NOT NULL DEFAULT 'queued',
  priority integer,
  source_listing_id bigint REFERENCES public.listings(listing_id),
  price_quote_id bigint REFERENCES public.listing_price_quotes(quote_id),
  assigned_to text,
  due_at timestamptz,
  completed_at timestamptz,
  result_listing_id bigint REFERENCES public.listings(listing_id),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT listing_publication_action_chk CHECK (desired_action IN ('create_listing','update_listing','refresh_photos','price_change','delist','relist')),
  CONSTRAINT listing_publication_status_chk CHECK (status IN ('queued','in_progress','blocked','manual_required','automated_possible','done','cancelled'))
);
COMMENT ON TABLE public.listing_publication_queue IS
  'Work queue for items still needing manual or automated listing actions across platforms/regions.';
CREATE INDEX IF NOT EXISTS idx_lpq_queue_status ON public.listing_publication_queue(status, priority, due_at);
CREATE INDEX IF NOT EXISTS idx_lpq_queue_inventory ON public.listing_publication_queue(inventory_uid);
CREATE INDEX IF NOT EXISTS idx_lpq_queue_platform_region ON public.listing_publication_queue(platform, market_region);

COMMIT;

-- Suggested manual readback after apply:
-- SELECT table_name
-- FROM information_schema.tables
-- WHERE table_schema = 'public'
--   AND table_name IN ('listing_events','listing_content_snapshots','listing_media_assets','image_match_candidates','marketplace_platforms','marketplace_pricing_rules','listing_price_quotes','listing_publication_queue')
-- ORDER BY table_name;
