-- 008_listing_scrape_errors.sql
-- Durable per-listing scrape error log for later debugging and resumable runs.

BEGIN;

CREATE TABLE IF NOT EXISTS public.listing_scrape_errors (
  scrape_error_id bigserial PRIMARY KEY,
  scrape_run_id uuid REFERENCES public.listing_scrape_runs(scrape_run_id),
  listing_id bigint REFERENCES public.listings(listing_id),
  inventory_uid text,
  platform text,
  external_listing_id text,
  listing_url text,
  error_stage text NOT NULL,
  error_type text NOT NULL,
  http_status integer,
  error_message text,
  response_excerpt text,
  is_cooloff_signal boolean NOT NULL DEFAULT false,
  probe_listing_url text,
  probe_http_status integer,
  probe_error_type text,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.listing_scrape_errors IS
  'Durable per-listing Craigslist scrape error log. One failed listing should not kill a run unless it indicates captcha/rate-limit/cooloff.';
COMMENT ON COLUMN public.listing_scrape_errors.is_cooloff_signal IS
  'True when the error appears to indicate Craigslist captcha/rate-limit/cooloff rather than a listing-specific issue.';

CREATE INDEX IF NOT EXISTS idx_lse_run ON public.listing_scrape_errors(scrape_run_id);
CREATE INDEX IF NOT EXISTS idx_lse_listing ON public.listing_scrape_errors(listing_id);
CREATE INDEX IF NOT EXISTS idx_lse_cooloff ON public.listing_scrape_errors(is_cooloff_signal, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_lse_type ON public.listing_scrape_errors(error_type, created_at DESC);

COMMIT;
