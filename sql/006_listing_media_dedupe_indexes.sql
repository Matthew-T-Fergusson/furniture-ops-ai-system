-- 006_listing_media_dedupe_indexes.sql
-- Add dedupe indexes for listing media assets after initial scrape scaffold.
--
-- Preflight/readback plan:
-- 1. Run: make ci-smoke
-- 2. Apply: apply ordered sql/*.sql in a database session
-- 3. Readback: SELECT indexname FROM pg_indexes WHERE schemaname='public' AND tablename='listing_media_assets' ORDER BY indexname;

BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS uq_listing_media_assets_local_path
  ON public.listing_media_assets(local_path);

CREATE UNIQUE INDEX IF NOT EXISTS uq_listing_media_assets_listing_sha
  ON public.listing_media_assets(listing_id, sha256)
  WHERE listing_id IS NOT NULL AND sha256 IS NOT NULL;

COMMENT ON INDEX public.uq_listing_media_assets_local_path IS
  'Prevent duplicate media rows for the same saved file path during repeated listing scrape runs.';
COMMENT ON INDEX public.uq_listing_media_assets_listing_sha IS
  'Prevent duplicate image hashes for the same listing during repeated Craigslist scrape runs.';

COMMIT;
