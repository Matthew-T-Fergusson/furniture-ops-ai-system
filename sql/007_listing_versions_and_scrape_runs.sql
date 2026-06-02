-- 007_listing_versions_and_scrape_runs.sql
-- Add listing version lineage and resumable scrape-run tracking.
--
-- Design decision: if an existing external listing materially changes,
-- create a new listings row/version for easier historical querying. Only enrich
-- missing fields in-place when the scraped listing appears to be the same.

BEGIN;

ALTER TABLE public.listings
  ADD COLUMN IF NOT EXISTS listing_series_id uuid,
  ADD COLUMN IF NOT EXISTS listing_version_no integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS supersedes_listing_id bigint REFERENCES public.listings(listing_id),
  ADD COLUMN IF NOT EXISTS valid_from timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS valid_to timestamptz,
  ADD COLUMN IF NOT EXISTS is_current_version boolean NOT NULL DEFAULT true;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

UPDATE public.listings
SET listing_series_id = gen_random_uuid()
WHERE listing_series_id IS NULL;

ALTER TABLE public.listings
  ALTER COLUMN listing_series_id SET DEFAULT gen_random_uuid(),
  ALTER COLUMN listing_series_id SET NOT NULL;

COMMENT ON COLUMN public.listings.listing_series_id IS
  'Continuity identifier for one external listing across captured versions/revisions. New rows for material changes share the same series.';
COMMENT ON COLUMN public.listings.listing_version_no IS
  'Incrementing version number within listing_series_id. New row/version is created when scraped listing content/price materially changes.';
COMMENT ON COLUMN public.listings.supersedes_listing_id IS
  'Previous listings row version superseded by this row when a material listing change is captured.';
COMMENT ON COLUMN public.listings.valid_from IS
  'Timestamp this listing row/version became the current observed representation.';
COMMENT ON COLUMN public.listings.valid_to IS
  'Timestamp this listing row/version stopped being current due to a later observed version.';
COMMENT ON COLUMN public.listings.is_current_version IS
  'True for current row/version within listing_series_id; historical versions remain queryable in listings.';

CREATE INDEX IF NOT EXISTS idx_listings_series_version
  ON public.listings(listing_series_id, listing_version_no);
CREATE INDEX IF NOT EXISTS idx_listings_current_version
  ON public.listings(is_current_version, platform, status);

CREATE TABLE IF NOT EXISTS public.listing_scrape_runs (
  scrape_run_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_started_at timestamptz NOT NULL DEFAULT now(),
  run_finished_at timestamptz,
  status text NOT NULL DEFAULT 'running',
  requested_limit integer,
  delay_min_seconds numeric(8,2),
  delay_max_seconds numeric(8,2),
  download_images boolean NOT NULL DEFAULT false,
  apply_changes boolean NOT NULL DEFAULT false,
  processed_count integer NOT NULL DEFAULT 0,
  success_count integer NOT NULL DEFAULT 0,
  error_count integer NOT NULL DEFAULT 0,
  captcha_count integer NOT NULL DEFAULT 0,
  last_listing_id bigint,
  report_path text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT listing_scrape_runs_status_chk CHECK (status IN ('running','completed','stopped_captcha','failed','cancelled'))
);
COMMENT ON TABLE public.listing_scrape_runs IS
  'Durable Craigslist scrape run tracking so long runs can stop on captcha/errors and resume from DB state instead of relying on agent context.';

ALTER TABLE public.listing_events
  ADD COLUMN IF NOT EXISTS scrape_run_id uuid REFERENCES public.listing_scrape_runs(scrape_run_id);

ALTER TABLE public.listing_content_snapshots
  ADD COLUMN IF NOT EXISTS scrape_run_id uuid REFERENCES public.listing_scrape_runs(scrape_run_id);

ALTER TABLE public.listing_media_assets
  ADD COLUMN IF NOT EXISTS scrape_run_id uuid REFERENCES public.listing_scrape_runs(scrape_run_id);

CREATE INDEX IF NOT EXISTS idx_listing_events_scrape_run ON public.listing_events(scrape_run_id);
CREATE INDEX IF NOT EXISTS idx_lcs_scrape_run ON public.listing_content_snapshots(scrape_run_id);
CREATE INDEX IF NOT EXISTS idx_lma_scrape_run ON public.listing_media_assets(scrape_run_id);

COMMIT;
