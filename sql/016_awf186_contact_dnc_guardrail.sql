-- 016_awf186_contact_dnc_guardrail.sql
-- AWF-186: Add contact-level do-not-contact fields and outbound DNC guardrail.
--
-- Decision from Matt (2026-06-03): DNC should block automatic/external
-- sending only. It should not block draft/pre-send preview generation; Lex may
-- still draft internally, but send workflows must surface/stop on DNC before an
-- external message is sent.

BEGIN;

ALTER TABLE contacts
  ADD COLUMN IF NOT EXISTS do_not_contact boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS dnc_reason text,
  ADD COLUMN IF NOT EXISTS dnc_set_at timestamptz,
  ADD COLUMN IF NOT EXISTS dnc_set_by text,
  ADD COLUMN IF NOT EXISTS dnc_channels text[];

ALTER TABLE contacts
  DROP CONSTRAINT IF EXISTS contacts_dnc_channels_chk;

ALTER TABLE contacts
  ADD CONSTRAINT contacts_dnc_channels_chk
  CHECK (
    dnc_channels IS NULL OR dnc_channels <@ ARRAY[
      'craigslist_email'::text,
      'craigslist_chat'::text,
      'facebook_marketplace'::text,
      'ebay'::text,
      'telegram'::text,
      'gmail'::text,
      'sms'::text,
      'manual'::text,
      'other'::text
    ]
  );

COMMENT ON COLUMN contacts.do_not_contact IS
  'AWF-186: Contact-level DNC flag. Blocks automatic/external outbound sending; does not block internal draft/pre-send preview generation.';
COMMENT ON COLUMN contacts.dnc_reason IS
  'AWF-186: Free-text or conventional reason for DNC, e.g. explicit_opt_out, hostile_or_harassing, wrong_person, spam_or_scam, manual_business_decision.';
COMMENT ON COLUMN contacts.dnc_set_at IS
  'AWF-186: Timestamp when DNC was set or last materially updated.';
COMMENT ON COLUMN contacts.dnc_set_by IS
  'AWF-186: Actor that set DNC, e.g. Matt, Stephen, Lex, or system.';
COMMENT ON COLUMN contacts.dnc_channels IS
  'AWF-186: Optional channel-specific DNC scope. NULL or empty array means all channels; otherwise only listed platform values are blocked.';

CREATE INDEX IF NOT EXISTS idx_contacts_dnc_active
  ON contacts(do_not_contact, updated_at DESC)
  WHERE do_not_contact IS TRUE;

DROP VIEW IF EXISTS furniture_db_guardrail_summary;
ALTER VIEW furniture_db_guardrail_anomalies RENAME TO furniture_db_guardrail_anomalies_pre_awf186;

CREATE VIEW furniture_db_guardrail_anomalies AS
SELECT * FROM furniture_db_guardrail_anomalies_pre_awf186
UNION ALL
SELECT
  'conversation_message'::text AS entity_type,
  m.conversation_message_id::text AS entity_id,
  t.inventory_group_id,
  'outbound_message_to_dnc_contact'::text AS anomaly_type,
  'error'::text AS severity,
  'Outbound message targets a contact marked do_not_contact. DNC blocks automatic/external sending; drafts/previews may still be prepared for human review.'::text AS message
FROM conversation_messages m
JOIN conversation_threads t ON t.conversation_thread_id = m.conversation_thread_id
JOIN contacts c ON c.contact_id = COALESCE(m.recipient_contact_id, t.contact_id)
WHERE m.direction = 'outbound'
  AND c.do_not_contact IS TRUE
  AND (
    c.dnc_channels IS NULL
    OR cardinality(c.dnc_channels) = 0
    OR m.platform = ANY(c.dnc_channels)
  );

COMMENT ON VIEW furniture_db_guardrail_anomalies IS
  'Furniture DB guardrail anomalies, including AWF-186 outbound-message-to-DNC-contact errors. DNC is a send guardrail, not a drafting/pre-send-preview blocker.';

CREATE OR REPLACE VIEW furniture_db_guardrail_summary AS
SELECT anomaly_type, severity, count(*) AS anomaly_count
FROM furniture_db_guardrail_anomalies
GROUP BY anomaly_type, severity
ORDER BY CASE severity WHEN 'error' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END, anomaly_count DESC, anomaly_type;

COMMIT;
