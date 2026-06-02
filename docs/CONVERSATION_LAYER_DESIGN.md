# internal-tracker — Unified Conversation Layer Schema Design

Status: draft for the operator review
Last updated: 2026-06-01

## Goal

Add a lightweight conversation layer for furniture-business leads and logistics without duplicating existing `contacts`, `contact_roles`, `inventory`, `listings`, `pickups_deliveries`, or `cash_flows` concepts.

The conversation layer should answer:

- Who are we talking to?
- About which listing/item/logistics movement?
- What is the latest message / next action?
- Does the operator/Lex/the operator need to reply?
- Where is the raw source transcript stored?

## Existing canonical tables to reuse

- `contacts`: canonical people/entities.
- `contact_roles`: buyer/seller/source/contractor/vendor/marketplace role context.
- `inventory`: canonical item rows via `inventory_uid`.
- `inventory_groups`: bundle/set/lot grouping.
- `listings`: canonical marketplace listing rows.
- `pickups_deliveries`: scheduled movements/logistics.
- `cash_flows`: payments, deposits, sale payments, expenses.

## Proposed tables

### 1. `conversation_threads`

One row per logical conversation thread/lead, usually per platform thread + listing/item context.

Proposed columns:

- `conversation_thread_id bigserial primary key`
- `platform text not null`
  - examples: `craigslist_email`, `craigslist_chat`, `facebook_marketplace`, `telegram`, `gmail`, `sms`, `manual`
- `source_account text`
  - example: `craigslist-account@example.invalid`
- `source_thread_id text`
  - Gmail thread ID, Craigslist chat/thread ID, FB marketplace thread ID, etc.
- `source_conversation_url text`
  - link back to source thread when available.
- `contact_id bigint references contacts(contact_id)`
- `contact_role_id bigint references contact_roles(contact_role_id)`
- `inventory_uid text references inventory(inventory_uid)`
- `inventory_group_id text references inventory_groups(inventory_group_id)`
- `listing_id bigint references listings(listing_id)`
- `movement_id bigint references pickups_deliveries(movement_id)`
- `purpose text not null default 'unknown'`
- `stage text not null default 'new'`
- `priority text not null default 'normal'`
- `assigned_to text`
- `last_message_at timestamptz`
- `last_inbound_at timestamptz`
- `last_outbound_at timestamptz`
- `needs_reply boolean not null default false`
- `next_action_at timestamptz`
- `next_action_note text`
- `thread_summary text`
- `raw_thread_path text`
- `source_system text not null default 'manual'`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Constraints/enums:

- `purpose in ('sourcing_acquisition','sale_inquiry','pickup_coordination','delivery_coordination','vendor_coordination','partner_coordination','support_admin','unknown')`
- `stage in ('new','needs_reply','negotiating','scheduled','waiting_on_other_party','completed','dead','spam','archived')`
- `priority in ('low','normal','high','urgent')`
- Unique nullable constraint/index on `(platform, source_account, source_thread_id)` where `source_thread_id is not null`.

Indexes:

- `(stage, needs_reply, last_message_at desc)`
- `(contact_id, last_message_at desc)`
- `(inventory_uid, last_message_at desc)`
- `(listing_id, last_message_at desc)`
- `(movement_id, last_message_at desc)`
- `(platform, source_thread_id)`

### 2. `conversation_messages`

One row per source message/email/chat message. Store searchable metadata/body preview in DB; store full raw source payload externally.

Proposed columns:

- `conversation_message_id bigserial primary key`
- `conversation_thread_id bigint not null references conversation_threads(conversation_thread_id)`
- `platform text not null`
- `source_account text`
- `source_message_id text`
  - Gmail message ID, Craigslist message ID, FB message ID, Telegram message ID, etc.
- `source_thread_id text`
- `message_at timestamptz not null`
- `direction text not null`
  - `inbound`, `outbound`, `system`, `internal_note`
- `sender_contact_id bigint references contacts(contact_id)`
- `recipient_contact_id bigint references contacts(contact_id)`
- `sender_raw text`
- `recipient_raw text`
- `subject text`
- `body_text text`
- `body_preview text`
- `message_url text`
- `raw_message_path text`
- `has_attachments boolean not null default false`
- `attachments_json jsonb not null default '[]'::jsonb`
- `ingest_status text not null default 'ingested'`
- `source_system text not null default 'manual'`
- `created_at timestamptz not null default now()`

Constraints/enums:

- `direction in ('inbound','outbound','system','internal_note')`
- `ingest_status in ('ingested','parsed','needs_review','failed','ignored')`
- Unique nullable constraint/index on `(platform, source_account, source_message_id)` where `source_message_id is not null`.

Indexes:

- `(conversation_thread_id, message_at)`
- `(message_at desc)`
- `(direction, message_at desc)`
- `(source_message_id)`

### 3. Optional later: `conversation_events`

Not needed for first scaffolding unless workflow auditing becomes important.

Potential future columns:

- `conversation_event_id bigserial primary key`
- `conversation_thread_id references conversation_threads`
- `event_type text`
- `old_stage text`
- `new_stage text`
- `event_at timestamptz default now()`
- `actor text default 'lex'`
- `notes text`

For now, stage changes can be updated directly and/or logged in `agent_action_log` if useful.

## Raw transcript storage convention

Implemented in internal-tracker foundation. Canonical storage doc:

```text
local_data/furniture_conversations/README.md
```

Root:

```text
local_data/furniture_conversations/
```

Path format:

```text
raw/{platform}/{yyyy}/{mm}/{dd}/{source-kind}-{source-id}.json
normalized/{platform}/{yyyy}/{mm}/{dd}/{source-kind}-{source-id}.normalized.json
```

Examples:

```text
local_data/furniture_conversations/raw/craigslist_email/2026/06/01/gmail-thread-19e80d1e7777f182.json
local_data/furniture_conversations/raw/craigslist_email/2026/06/01/gmail-message-19e80d1e7777f182.json
local_data/furniture_conversations/normalized/craigslist_email/2026/06/01/gmail-message-19e80d1e7777f182.normalized.json
```

DB rows should store relative raw paths when possible, e.g.:

```text
local_data/furniture_conversations/raw/craigslist_email/2026/06/01/gmail-message-19e80d1e7777f182.json
```

## Dedupe strategy

1. Message-level dedupe first:
   - `(platform, source_account, source_message_id)`.
2. Thread-level dedupe second:
   - `(platform, source_account, source_thread_id)`.
3. If no source IDs exist:
   - hash normalized `sender/contact + timestamp bucket + body_text + listing_id` in ingest code, not as first schema requirement.

## Contact/linking policy

- Do not create separate buyer/seller lead tables.
- Use `contacts` for people/entities.
- Use `contact_roles` for buyer/seller/source/vendor/etc. context.
- Conversations may start unmatched (`contact_id null`) and be linked later.
- Ambiguous contact matches should be flagged via `stage = 'needs_reply'` or `ingest_status = 'needs_review'`, plus notes, instead of silently creating duplicates.

### Contact identity additions needed

Marketplace conversations often begin with a weak identity such as a Craigslist relay display name, Craigslist/eBay username, handle, or opaque platform ID before we have phone/email/real name.

Add platform-scoped identity fields to `contacts` so we can differentiate leads without inventing fake full contact records:

- `username text`
  - Human-visible username, handle, nickname, or marketplace display name.
  - Examples: Craigslist display name, eBay username, Facebook profile display name.
- `username_platform text`
  - Platform/source for that username.
  - Examples: `craigslist`, `ebay`, `facebook_marketplace`, `telegram`, `gmail`, `sms`, `manual`.
- `platform_contact_id text`
  - Opaque provider/platform ID when available.
  - Examples: Craigslist relay/contact token, eBay member ID, FB marketplace profile/thread participant ID.

Recommended matching order:

1. Exact phone.
2. Exact email.
3. Exact `(username_platform, platform_contact_id)` when platform ID is available.
4. Exact `(username_platform, username)` as a provisional match.
5. Fuzzy/name-only matches should be review-only, not automatic merge.

Open design note:
- If one real person later appears on multiple platforms, keep the best canonical `contacts` row and merge/link platform identities carefully. If multi-platform aliases become common, create a separate `contact_platform_identities` table later. For v1, the three additive `contacts` columns are enough.

## Stage/purpose defaults

Inbound buyer message about an active listing:

- `purpose = 'sale_inquiry'`
- `stage = 'needs_reply'`
- `needs_reply = true`

Outbound reply sent:

- `last_outbound_at` updated
- `needs_reply = false`
- `stage = 'waiting_on_other_party'` unless a pickup/delivery is scheduled.

Pickup/delivery agreed:

- link/create `pickups_deliveries`
- `purpose = 'pickup_coordination'` or `delivery_coordination`
- `stage = 'scheduled'`

Dead/spam:

- `stage = 'dead'` or `spam`
- `needs_reply = false`

## Message storage/search design

Search needs two layers:

1. **Operational DB text** for fast triage and lead queue search.
2. **Raw source payload files** for audit/replay/debugging without bloating core DB rows.

`conversation_messages.body_text` should store normalized searchable text:

- Plain-text body only, not raw MIME/HTML.
- Strip Craigslist footer boilerplate where practical, but keep enough body context to understand the lead.
- Preserve user-written text, listing URL, offer amount, pickup timing, phone/email if present.
- Normalize whitespace and line endings.
- Store outbound reply text the same way as inbound text.

`conversation_messages.body_preview` should store a short preview for lead queues, roughly 240-500 chars.

`conversation_messages.search_vector` should be added in internal-tracker as a generated/stored or maintained `tsvector`, likely from:

```sql
coalesce(subject,'') || ' ' || coalesce(body_text,'') || ' ' || coalesce(sender_raw,'') || ' ' || coalesce(recipient_raw,'')
```

Recommended indexes:

```sql
CREATE INDEX idx_conversation_messages_search_vector
ON conversation_messages USING gin(search_vector);

CREATE INDEX idx_conversation_messages_body_trgm
ON conversation_messages USING gin(body_text gin_trgm_ops);
```

Use Postgres full-text search for normal triage and trigram search for fuzzy names/phrases/listing snippets if `pg_trgm` is available.

Raw payloads go to `raw_message_path` / `raw_thread_path` as JSON files containing provider-specific fields, headers, MIME, source labels, and unmodified body variants.

## Open decisions for the operator

1. Should Craigslist email relay and Craigslist on-site chat be separate platform values?
   - Context: Craigslist can produce at least two different conversation sources:
     - Gmail/email relay messages from `*@reply.craigslist.org`, where we can reply through Gmail.
     - Craigslist on-site chat notifications from `robot@craigslist.org`, where Gmail may only notify us and the actual reply may need to happen on Craigslist.
   - Recommendation: yes: use separate values `craigslist_email` and `craigslist_chat` so ingest/reply logic does not confuse email replies with on-site chat handling.

   Storage location and table implication:
   - Both sources live in the **same DB tables**: `conversation_threads` and `conversation_messages`.
   - The split is a `platform` value, not separate Craigslist-specific tables.
   - Example thread rows:
     - `platform = 'craigslist_email'`, `source_account = 'craigslist-account@example.invalid'`, `source_thread_id = Gmail thread ID`
     - `platform = 'craigslist_chat'`, `source_account = Craigslist account or Gmail notification account`, `source_thread_id = Craigslist chat/thread ID when available`
   - Raw payloads are stored under different raw directories:
     - `local_data/furniture_conversations/raw/craigslist_email/...`
     - `local_data/furniture_conversations/raw/craigslist_chat/...`

   Workflow implication:
   - `craigslist_email` can usually support Gmail in-thread reply.
   - `craigslist_chat` may require opening Craigslist or using a future Craigslist-chat automation path; Gmail may only be a notification source.
   - Lead queue/reporting can still combine both because both normalize into the same `conversation_threads` fields: `purpose`, `stage`, `needs_reply`, `contact_id`, `listing_id`, `inventory_uid`, `last_message_at`.
   - Reply tooling must branch by `platform`:
     - email relay → reply via Gmail, after human operators approval.
     - on-site chat → route to Craigslist chat workflow, after human operators approval.
   - Dedupe constraints stay source-specific via `(platform, source_account, source_thread_id)` and `(platform, source_account, source_message_id)`, preventing a Gmail relay ID and Craigslist chat ID from colliding.

2. Should full email/chat body text live in DB, or only preview + raw path?
   - Decision direction: store normalized searchable message text in DB plus raw JSON payload externally.
   - DB should include `body_text`, `body_preview`, and `search_vector` for search/triage.
   - Raw files should preserve full provider payloads for audit/debug/reprocessing.

3. Who can approve external replies?
   - Decision direction: a human operator may approve/send replies for furniture-business conversations.
   - Implementation note: record approval/sender context where possible, e.g. `approved_by`, `sent_by`, or an `agent_action_log` entry.
   - Guardrail: this applies to furniture-business workflow messages, not the operator-personal/private contexts.

4. Should the operator-visible conversations be included in the same layer?
   - Decision: yes, both the operator and the operator need to be able to use this workflow for furniture-business operations.
   - Implementation note: reporting/output should still respect privacy/source boundaries, but the operational layer should cover shared furniture-business leads and logistics.

5. Should `conversation_events` ship in v1?
   - Context: `conversation_events` would be an audit/history table for changes to a conversation thread, separate from the actual messages. Examples: stage changed from `needs_reply` to `waiting_on_other_party`, linked to inventory item, assigned to the operator, marked dead/spam, pickup scheduled.
   - Why it is useful: it gives a timeline of operational decisions even when no message was sent. This is what we would eventually use for conversion-time KPIs, e.g. first response time, time from first inbound to scheduled pickup, time from inquiry to sale/dead, and stage-by-stage dropoff.
   - Why it should not ship in v1: the fields and process flows are still being formed. If we add event logging too early, we will constantly rewrite event types and reporting logic as the operating workflow changes.
   - Decision: skip as required v1 table. Create a follow-up Jira ticket to design/add `conversation_events` after the operating infrastructure and process flows are in place.
   - V1 substitute: use `conversation_threads.updated_at`, current fields, actual `conversation_messages`, and `agent_action_log` for important automation actions.

## Migration plan for internal-tracker

1. Create migration `032_awf158_conversation_layer_foundation.sql`.
2. Add `conversation_threads`.
3. Add `conversation_messages`.
4. Add constraints and indexes.
5. Add comments explaining table purpose and source-of-truth boundaries.
6. Validate with existing migration tooling.
7. Create readback SQL checking tables, constraints, and indexes.
