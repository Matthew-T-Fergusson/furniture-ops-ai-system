-- 009_conversation_layer_foundation.sql
-- Add furniture conversation layer foundation tables and contact marketplace identity fields.
--
-- Preflight/readback plan:
-- 1. Run: make ci-smoke
-- 2. Apply after human confirmation: apply ordered sql/*.sql in a database session
-- 3. Readback SQL:
--    SELECT table_name FROM information_schema.tables
--    WHERE table_schema='public' AND table_name IN ('conversation_threads','conversation_messages')
--    ORDER BY table_name;
--    SELECT column_name FROM information_schema.columns
--    WHERE table_schema='public' AND table_name='contacts'
--      AND column_name IN ('username','username_platform','platform_contact_id')
--    ORDER BY column_name;
--
-- Policy:
-- - Additive only.
-- - Existing contacts/contact_roles remain canonical person/entity and role sources.
-- - Existing inventory/listings/pickups_deliveries/cash_flows remain canonical operational sources.
-- - Conversation tables normalize lead/logistics messaging metadata and searchable text; raw provider payloads live in files referenced by *_raw_path columns.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_trgm;

ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS username text,
  ADD COLUMN IF NOT EXISTS username_platform text,
  ADD COLUMN IF NOT EXISTS platform_contact_id text;

COMMENT ON COLUMN public.contacts.username IS
  'Marketplace/platform username, nickname, handle, or display name used as weak/provisional identity before phone/email/real name are known.';
COMMENT ON COLUMN public.contacts.username_platform IS
  'Platform/source for contacts.username or contacts.platform_contact_id, e.g. craigslist, ebay, facebook_marketplace, telegram, gmail, sms, manual, other.';
COMMENT ON COLUMN public.contacts.platform_contact_id IS
  'Opaque provider/platform contact identifier when available; use with username_platform for provisional dedupe before phone/email are known.';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'contacts_username_platform_chk') THEN
    ALTER TABLE public.contacts
      ADD CONSTRAINT contacts_username_platform_chk CHECK (
        username_platform IS NULL OR username_platform IN (
          'craigslist',
          'ebay',
          'facebook_marketplace',
          'telegram',
          'gmail',
          'sms',
          'manual',
          'other'
        )
      );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_contacts_username_platform_id
  ON public.contacts(username_platform, platform_contact_id)
  WHERE platform_contact_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_contacts_username_platform_username
  ON public.contacts(username_platform, lower(username))
  WHERE username IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.conversation_threads (
  conversation_thread_id bigserial PRIMARY KEY,
  platform text NOT NULL,
  source_account text,
  source_thread_id text,
  source_conversation_url text,
  contact_id bigint REFERENCES public.contacts(contact_id),
  contact_role_id bigint REFERENCES public.contact_roles(contact_role_id),
  inventory_uid text REFERENCES public.inventory(inventory_uid),
  inventory_group_id text REFERENCES public.inventory_groups(inventory_group_id),
  listing_id bigint REFERENCES public.listings(listing_id),
  movement_id bigint REFERENCES public.pickups_deliveries(movement_id),
  purpose text NOT NULL DEFAULT 'unknown',
  stage text NOT NULL DEFAULT 'new',
  priority text NOT NULL DEFAULT 'normal',
  assigned_to text,
  last_message_at timestamptz,
  last_inbound_at timestamptz,
  last_outbound_at timestamptz,
  needs_reply boolean NOT NULL DEFAULT false,
  next_action_at timestamptz,
  next_action_note text,
  thread_summary text,
  raw_thread_path text,
  source_system text NOT NULL DEFAULT 'manual',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT conversation_threads_platform_chk CHECK (platform IN (
    'craigslist_email',
    'craigslist_chat',
    'facebook_marketplace',
    'ebay',
    'telegram',
    'gmail',
    'sms',
    'manual',
    'other'
  )),
  CONSTRAINT conversation_threads_purpose_chk CHECK (purpose IN (
    'sourcing_acquisition',
    'sale_inquiry',
    'pickup_coordination',
    'delivery_coordination',
    'vendor_coordination',
    'partner_coordination',
    'support_admin',
    'unknown'
  )),
  CONSTRAINT conversation_threads_stage_chk CHECK (stage IN (
    'new',
    'needs_reply',
    'negotiating',
    'scheduled',
    'waiting_on_other_party',
    'completed',
    'dead',
    'spam',
    'archived'
  )),
  CONSTRAINT conversation_threads_priority_chk CHECK (priority IN ('low','normal','high','urgent'))
);

COMMENT ON TABLE public.conversation_threads IS
  'One row per logical furniture-business conversation/lead/logistics thread. Reuses contacts, listings, inventory, and pickups_deliveries as canonical sources rather than duplicating them.';
COMMENT ON COLUMN public.conversation_threads.platform IS
  'Source channel. craigslist_email and craigslist_chat are deliberately separate platform values but share this same table/workflow.';
COMMENT ON COLUMN public.conversation_threads.source_thread_id IS
  'Provider thread ID, e.g. Gmail thread ID, Craigslist chat/thread ID, Facebook Marketplace thread ID.';
COMMENT ON COLUMN public.conversation_threads.purpose IS
  'Operational reason for thread: sale inquiry, sourcing/acquisition, pickup/delivery coordination, vendor/partner/admin, or unknown.';
COMMENT ON COLUMN public.conversation_threads.stage IS
  'Current operating state for lead/workflow triage; history/event KPI logging is deferred to .';
COMMENT ON COLUMN public.conversation_threads.raw_thread_path IS
  'Relative path to raw source thread payload JSON when available; large/raw provider payloads should live outside core DB rows.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_conversation_threads_source_thread
  ON public.conversation_threads(platform, source_account, source_thread_id)
  WHERE source_thread_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_conversation_threads_stage_reply_last
  ON public.conversation_threads(stage, needs_reply, last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversation_threads_contact_last
  ON public.conversation_threads(contact_id, last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversation_threads_inventory_last
  ON public.conversation_threads(inventory_uid, last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversation_threads_listing_last
  ON public.conversation_threads(listing_id, last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversation_threads_movement_last
  ON public.conversation_threads(movement_id, last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversation_threads_platform_source
  ON public.conversation_threads(platform, source_thread_id);

CREATE TABLE IF NOT EXISTS public.conversation_messages (
  conversation_message_id bigserial PRIMARY KEY,
  conversation_thread_id bigint NOT NULL REFERENCES public.conversation_threads(conversation_thread_id),
  platform text NOT NULL,
  source_account text,
  source_message_id text,
  source_thread_id text,
  message_at timestamptz NOT NULL,
  direction text NOT NULL,
  sender_contact_id bigint REFERENCES public.contacts(contact_id),
  recipient_contact_id bigint REFERENCES public.contacts(contact_id),
  sender_raw text,
  recipient_raw text,
  subject text,
  body_text text,
  body_preview text,
  search_vector tsvector GENERATED ALWAYS AS (
    to_tsvector(
      'simple'::regconfig,
      coalesce(subject,'') || ' ' ||
      coalesce(body_text,'') || ' ' ||
      coalesce(sender_raw,'') || ' ' ||
      coalesce(recipient_raw,'')
    )
  ) STORED,
  message_url text,
  raw_message_path text,
  has_attachments boolean NOT NULL DEFAULT false,
  attachments_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  ingest_status text NOT NULL DEFAULT 'ingested',
  source_system text NOT NULL DEFAULT 'manual',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT conversation_messages_platform_chk CHECK (platform IN (
    'craigslist_email',
    'craigslist_chat',
    'facebook_marketplace',
    'ebay',
    'telegram',
    'gmail',
    'sms',
    'manual',
    'other'
  )),
  CONSTRAINT conversation_messages_direction_chk CHECK (direction IN ('inbound','outbound','system','internal_note')),
  CONSTRAINT conversation_messages_ingest_status_chk CHECK (ingest_status IN ('ingested','parsed','needs_review','failed','ignored'))
);

COMMENT ON TABLE public.conversation_messages IS
  'Searchable normalized metadata/text for individual messages in furniture-business conversations. Raw MIME/provider payloads live in raw_message_path files.';
COMMENT ON COLUMN public.conversation_messages.body_text IS
  'Normalized searchable plain text, preserving user-written content and useful lead details while avoiding raw MIME/HTML bloat.';
COMMENT ON COLUMN public.conversation_messages.body_preview IS
  'Short lead-queue preview derived from body_text.';
COMMENT ON COLUMN public.conversation_messages.search_vector IS
  'Postgres full-text search vector over subject/body/sender/recipient for conversation triage.';
COMMENT ON COLUMN public.conversation_messages.raw_message_path IS
  'Relative path to raw source message JSON/MIME payload when available.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_conversation_messages_source_message
  ON public.conversation_messages(platform, source_account, source_message_id)
  WHERE source_message_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_conversation_messages_thread_at
  ON public.conversation_messages(conversation_thread_id, message_at);
CREATE INDEX IF NOT EXISTS idx_conversation_messages_message_at
  ON public.conversation_messages(message_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversation_messages_direction_at
  ON public.conversation_messages(direction, message_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversation_messages_source_message
  ON public.conversation_messages(source_message_id);
CREATE INDEX IF NOT EXISTS idx_conversation_messages_search_vector
  ON public.conversation_messages USING gin(search_vector);
CREATE INDEX IF NOT EXISTS idx_conversation_messages_body_trgm
  ON public.conversation_messages USING gin(body_text gin_trgm_ops)
  WHERE body_text IS NOT NULL;

COMMIT;

-- Suggested manual readback after apply:
-- SELECT table_name FROM information_schema.tables
-- WHERE table_schema='public' AND table_name IN ('conversation_threads','conversation_messages')
-- ORDER BY table_name;
--
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema='public' AND table_name='contacts'
--   AND column_name IN ('username','username_platform','platform_contact_id')
-- ORDER BY column_name;
--
-- SELECT indexname FROM pg_indexes
-- WHERE schemaname='public'
--   AND tablename IN ('conversation_threads','conversation_messages','contacts')
--   AND indexname LIKE ANY (ARRAY['idx_conversation%','uq_conversation%','idx_contacts_username%'])
-- ORDER BY indexname;
