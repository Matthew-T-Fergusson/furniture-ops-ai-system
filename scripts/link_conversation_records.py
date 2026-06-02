#!/usr/bin/env python3
"""public-tracker: Link furniture conversation threads to contacts/listings/inventory.

V1 policy:
- Create provisional contacts up front when an inbound/platform identity exists.
- Link items only on strong evidence: exact listing URL or parsed external listing ID.
- Avoid fuzzy merges; ambiguous matches stay for review.
"""
from __future__ import annotations

import argparse
import os
import shlex
import subprocess
import sys

SQL = r"""
BEGIN;

CREATE TEMP TABLE tmp_awf161_updates (
  action text,
  conversation_thread_id bigint,
  entity text,
  entity_id text,
  detail text
) ON COMMIT DROP;

-- Latest and latest inbound-ish message per thread for identity/body matching.
CREATE TEMP TABLE tmp_thread_msg ON COMMIT DROP AS
WITH latest AS (
  SELECT DISTINCT ON (conversation_thread_id)
    conversation_thread_id,
    conversation_message_id,
    direction,
    sender_raw,
    recipient_raw,
    body_text,
    message_at
  FROM public.conversation_messages
  ORDER BY conversation_thread_id, message_at DESC, conversation_message_id DESC
), inbound AS (
  SELECT DISTINCT ON (conversation_thread_id)
    conversation_thread_id,
    conversation_message_id AS inbound_message_id,
    direction AS inbound_direction,
    sender_raw AS inbound_sender_raw,
    body_text AS inbound_body_text,
    message_at AS inbound_message_at
  FROM public.conversation_messages
  WHERE direction IN ('inbound','system')
  ORDER BY conversation_thread_id, message_at DESC, conversation_message_id DESC
)
SELECT
  t.conversation_thread_id,
  t.platform,
  t.purpose,
  t.contact_id,
  t.listing_id,
  t.inventory_uid,
  latest.conversation_message_id AS latest_message_id,
  latest.direction AS latest_direction,
  latest.sender_raw AS latest_sender_raw,
  latest.body_text AS latest_body_text,
  inbound.inbound_message_id,
  inbound.inbound_direction,
  inbound.inbound_sender_raw,
  inbound.inbound_body_text,
  coalesce(inbound.inbound_body_text, latest.body_text, '') AS match_text
FROM public.conversation_threads t
LEFT JOIN latest USING (conversation_thread_id)
LEFT JOIN inbound USING (conversation_thread_id);

-- Parse sender display/email for inbound non-system messages.
CREATE TEMP TABLE tmp_sender_identity ON COMMIT DROP AS
SELECT
  conversation_thread_id,
  platform,
  purpose,
  inbound_sender_raw,
  nullif(btrim(regexp_replace(coalesce(inbound_sender_raw,''), '\s*<[^>]+>\s*$', '')), '') AS sender_display_raw,
  nullif(substring(coalesce(inbound_sender_raw,'') from '<([^>]+)>'), '') AS sender_email_angle,
  CASE
    WHEN coalesce(inbound_sender_raw,'') ~ '<[^>]+>' THEN substring(coalesce(inbound_sender_raw,'') from '<([^>]+)>')
    WHEN coalesce(inbound_sender_raw,'') ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN inbound_sender_raw
    ELSE NULL
  END AS sender_email
FROM tmp_thread_msg
WHERE contact_id IS NULL
  AND inbound_direction = 'inbound'
  AND coalesce(inbound_sender_raw,'') <> '';

CREATE TEMP TABLE tmp_contact_candidates ON COMMIT DROP AS
SELECT
  conversation_thread_id,
  platform,
  purpose,
  inbound_sender_raw,
  CASE
    WHEN platform IN ('craigslist_email','craigslist_chat') THEN 'craigslist'
    WHEN platform = 'facebook_marketplace' THEN 'facebook_marketplace'
    WHEN platform = 'ebay' THEN 'ebay'
    WHEN platform = 'telegram' THEN 'telegram'
    WHEN platform = 'gmail' THEN 'gmail'
    WHEN platform = 'sms' THEN 'sms'
    ELSE 'other'
  END AS username_platform,
  nullif(btrim(replace(sender_display_raw, '"', '')), '') AS username,
  CASE
    WHEN sender_email ILIKE '%@reply.craigslist.org' THEN split_part(sender_email, '@', 1)
    WHEN sender_email ILIKE '%@sale.craigslist.org' THEN split_part(sender_email, '@', 1)
    ELSE NULL
  END AS platform_contact_id,
  CASE
    WHEN sender_email IS NOT NULL
      AND sender_email NOT ILIKE '%@reply.craigslist.org'
      AND sender_email NOT ILIKE '%@sale.craigslist.org'
      AND sender_email NOT ILIKE '%@craigslist.org'
      THEN sender_email
    ELSE NULL
  END AS real_email,
  coalesce(nullif(btrim(replace(sender_display_raw, '"', '')), ''), split_part(coalesce(sender_email,''), '@', 1), 'Unknown marketplace lead') AS display_name
FROM tmp_sender_identity;

-- Map to existing contacts by strong platform identity or real email.
CREATE TEMP TABLE tmp_contact_match ON COMMIT DROP AS
SELECT DISTINCT ON (cc.conversation_thread_id)
  cc.conversation_thread_id,
  c.contact_id,
  'existing_contact'::text AS match_type
FROM tmp_contact_candidates cc
JOIN public.contacts c ON (
  (cc.real_email IS NOT NULL AND lower(c.email) = lower(cc.real_email))
  OR (cc.platform_contact_id IS NOT NULL AND c.username_platform = cc.username_platform AND c.platform_contact_id = cc.platform_contact_id)
  OR (cc.platform_contact_id IS NULL AND cc.username IS NOT NULL AND c.username_platform = cc.username_platform AND lower(c.username) = lower(cc.username))
)
ORDER BY cc.conversation_thread_id, c.contact_id;

-- Create provisional contacts for unmatched inbound platform identities.
CREATE TEMP TABLE tmp_created_contacts ON COMMIT DROP AS
WITH inserted AS (
  INSERT INTO public.contacts (
    display_name,
    contact_type,
    email,
    username,
    username_platform,
    platform_contact_id,
    notes,
    source_system
  )
  SELECT
    cc.display_name,
    'lead',
    cc.real_email,
    cc.username,
    cc.username_platform,
    cc.platform_contact_id,
    'public-tracker provisional marketplace lead created from conversation thread ' || cc.conversation_thread_id || '. Clean up later if abandoned/non-converting.',
    'link_conversation_records.py'
  FROM tmp_contact_candidates cc
  LEFT JOIN tmp_contact_match m USING (conversation_thread_id)
  WHERE m.contact_id IS NULL
    AND (cc.real_email IS NOT NULL OR cc.username IS NOT NULL OR cc.platform_contact_id IS NOT NULL)
  RETURNING contact_id, username_platform, platform_contact_id, username, email
)
SELECT cc.conversation_thread_id, i.contact_id, 'created_contact'::text AS match_type
FROM tmp_contact_candidates cc
JOIN inserted i ON (
  (cc.real_email IS NOT NULL AND i.email = cc.real_email)
  OR (cc.platform_contact_id IS NOT NULL AND i.username_platform = cc.username_platform AND i.platform_contact_id = cc.platform_contact_id)
  OR (cc.platform_contact_id IS NULL AND cc.username IS NOT NULL AND i.username_platform = cc.username_platform AND lower(i.username) = lower(cc.username))
);

INSERT INTO tmp_awf161_updates(action, conversation_thread_id, entity, entity_id, detail)
SELECT match_type, conversation_thread_id, 'contact', contact_id::text, 'Linked/created provisional contact from inbound sender identity.'
FROM (
  SELECT * FROM tmp_contact_match
  UNION ALL
  SELECT * FROM tmp_created_contacts
) x;

-- Link contacts to threads.
WITH contact_links AS (
  SELECT * FROM tmp_contact_match
  UNION ALL
  SELECT * FROM tmp_created_contacts
)
UPDATE public.conversation_threads t
SET contact_id = cl.contact_id,
    updated_at = now()
FROM contact_links cl
WHERE t.conversation_thread_id = cl.conversation_thread_id
  AND t.contact_id IS NULL;

-- Create contact roles by purpose where absent.
WITH role_source AS (
  SELECT
    t.conversation_thread_id,
    t.contact_id,
    t.inventory_uid,
    t.inventory_group_id,
    CASE
      WHEN t.purpose = 'sale_inquiry' THEN 'buyer'
      WHEN t.purpose = 'sourcing_acquisition' THEN 'source'
      WHEN t.purpose = 'vendor_coordination' THEN 'vendor'
      WHEN t.purpose IN ('pickup_coordination','delivery_coordination','unknown') THEN 'marketplace_lead'
      ELSE NULL
    END AS role
  FROM public.conversation_threads t
  WHERE t.contact_id IS NOT NULL
), inserted_roles AS (
  INSERT INTO public.contact_roles (contact_id, role, inventory_uid, inventory_group_id, notes)
  SELECT
    rs.contact_id,
    rs.role,
    rs.inventory_uid,
    rs.inventory_group_id,
    'public-tracker role created from conversation thread ' || rs.conversation_thread_id
  FROM role_source rs
  WHERE rs.role IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.contact_roles cr
      WHERE cr.contact_id = rs.contact_id
        AND cr.role = rs.role
        AND cr.inventory_uid IS NOT DISTINCT FROM rs.inventory_uid
        AND cr.inventory_group_id IS NOT DISTINCT FROM rs.inventory_group_id
    )
  RETURNING contact_role_id, contact_id, role
)
INSERT INTO tmp_awf161_updates(action, conversation_thread_id, entity, entity_id, detail)
SELECT 'created_role', rs.conversation_thread_id, 'contact_role', ir.contact_role_id::text, 'Created role ' || ir.role
FROM inserted_roles ir
JOIN role_source rs ON rs.contact_id = ir.contact_id AND rs.role = ir.role;

-- Extract Craigslist/listing URLs and numeric external listing IDs from message text.
CREATE TEMP TABLE tmp_listing_clues ON COMMIT DROP AS
SELECT DISTINCT
  tm.conversation_thread_id,
  (regexp_match(match_text, '(https?://[^\s<>"'']*craigslist\.org/[^\s<>"'']+)'))[1] AS listing_url,
  (regexp_match(match_text, '/([0-9]{8,})\.html'))[1] AS external_listing_id
FROM tmp_thread_msg tm
WHERE coalesce(match_text,'') <> '';

CREATE TEMP TABLE tmp_listing_match ON COMMIT DROP AS
SELECT DISTINCT ON (lc.conversation_thread_id)
  lc.conversation_thread_id,
  l.listing_id,
  l.inventory_uid,
  l.inventory_group_id,
  CASE
    WHEN lc.listing_url IS NOT NULL AND l.listing_url = lc.listing_url THEN 'exact_listing_url'
    WHEN lc.external_listing_id IS NOT NULL AND l.external_listing_id = lc.external_listing_id THEN 'external_listing_id'
    WHEN lc.external_listing_id IS NOT NULL AND l.listing_url LIKE '%' || lc.external_listing_id || '%' THEN 'listing_url_contains_external_id'
    ELSE 'unknown'
  END AS match_type
FROM tmp_listing_clues lc
JOIN public.listings l ON (
  (lc.listing_url IS NOT NULL AND l.listing_url = lc.listing_url)
  OR (lc.external_listing_id IS NOT NULL AND l.external_listing_id = lc.external_listing_id)
  OR (lc.external_listing_id IS NOT NULL AND l.listing_url LIKE '%' || lc.external_listing_id || '%')
)
ORDER BY lc.conversation_thread_id,
  CASE
    WHEN lc.listing_url IS NOT NULL AND l.listing_url = lc.listing_url THEN 1
    WHEN lc.external_listing_id IS NOT NULL AND l.external_listing_id = lc.external_listing_id THEN 2
    ELSE 3
  END,
  l.listing_id;

WITH upd AS (
  UPDATE public.conversation_threads t
  SET listing_id = lm.listing_id,
      inventory_uid = coalesce(t.inventory_uid, lm.inventory_uid),
      inventory_group_id = coalesce(t.inventory_group_id, lm.inventory_group_id),
      updated_at = now()
  FROM tmp_listing_match lm
  WHERE t.conversation_thread_id = lm.conversation_thread_id
    AND (t.listing_id IS NULL OR t.inventory_uid IS NULL OR t.inventory_group_id IS NULL)
  RETURNING t.conversation_thread_id, t.listing_id, t.inventory_uid, t.inventory_group_id
)
INSERT INTO tmp_awf161_updates(action, conversation_thread_id, entity, entity_id, detail)
SELECT 'linked_listing', lm.conversation_thread_id, 'listing', lm.listing_id::text, 'Listing match: ' || lm.match_type
FROM tmp_listing_match lm;

SELECT coalesce(jsonb_pretty(jsonb_agg(to_jsonb(tmp_awf161_updates) ORDER BY conversation_thread_id, action, entity)), '[]'::jsonb::text)
FROM tmp_awf161_updates;

COMMIT;
"""

READBACK = r"""
SELECT
  t.conversation_thread_id || E'\t' ||
  t.platform || E'\t' ||
  coalesce(t.purpose,'') || E'\t' ||
  coalesce(t.stage,'') || E'\t' ||
  coalesce(t.contact_id::text,'') || E'\t' ||
  coalesce(c.display_name,'') || E'\t' ||
  coalesce(c.username_platform,'') || E'\t' ||
  coalesce(c.username,'') || E'\t' ||
  coalesce(c.platform_contact_id,'') || E'\t' ||
  coalesce(t.listing_id::text,'') || E'\t' ||
  coalesce(t.inventory_uid,'') || E'\t' ||
  coalesce(t.next_action_note,'')
FROM public.conversation_threads t
LEFT JOIN public.contacts c ON c.contact_id = t.contact_id
ORDER BY t.conversation_thread_id;
"""


def psql_command() -> list[str]:
    explicit = os.environ.get("FURNITURE_DB_PSQL")
    if explicit:
        return shlex.split(explicit)
    return ["docker", "exec", "-i", os.environ.get("FURNITURE_DB_DOCKER_CONTAINER", "lex-postgres"), "psql", "-U", os.environ.get("FURNITURE_DB_USER", "lex"), "-d", os.environ.get("FURNITURE_DB_NAME", "inspiring_works_llc")]


def run_sql(sql: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(psql_command() + ["-v", "ON_ERROR_STOP=1", "-X", "-q", "-At"], input=sql, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)


def require_ok(proc: subprocess.CompletedProcess[str], label: str) -> str:
    if proc.returncode != 0:
        sys.stderr.write(f"{label} failed with exit {proc.returncode}\n")
        if proc.stdout:
            sys.stderr.write(proc.stdout)
        if proc.stderr:
            sys.stderr.write(proc.stderr)
        raise SystemExit(proc.returncode)
    return proc.stdout or ""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--apply", action="store_true", help="Apply changes. Without this, preview and roll back.")
    ap.add_argument("--readback", action="store_true", help="Print thread linkage readback.")
    args = ap.parse_args()
    sql = SQL if args.apply else SQL.replace("COMMIT;", "ROLLBACK;")
    print((require_ok(run_sql(sql), "link conversation records") or "[]").strip())
    if args.readback:
        print("\nconversation_thread_id\tplatform\tpurpose\tstage\tcontact_id\tcontact_name\tusername_platform\tusername\tplatform_contact_id\tlisting_id\tinventory_uid\tnext_action_note")
        print(require_ok(run_sql(READBACK), "readback conversation links").strip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
