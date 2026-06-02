# Platform Message Ingestion Reference

## Related Jira

- internal-tracker: conversation layer schema design.
- internal-tracker: conversation layer DB foundation.
- internal-tracker: raw/normalized transcript storage.
- internal-tracker: conversation matching/linking logic.
- internal-tracker: active conversation queue/report view.
- internal-tracker: conversation purpose/stage workflow.
- internal-tracker: backfill active furniture conversations.
- internal-tracker: scheduled business-hours monitor.
- internal-tracker: furniture conversation monitor triage skill.
- internal-tracker: Craigslist email reply workflow skill.
- internal-tracker: Craigslist chat browser capture skill.
- internal-tracker: this platform ingestion framework skill.
- internal-tracker: future Lex-approved routine marketplace reply policy.
- internal-tracker: platform-specific privacy/capture policies.
- internal-tracker: Craigslist timestamp/follow-up refinement.

## Canonical DB tables

Use these shared objects:

- `conversation_threads`
- `conversation_messages`
- `active_conversation_queue`
- `contacts`
- `contact_roles`
- `listings`
- `inventory`
- `inventory_groups`
- `pickups_deliveries`

Never create buyer/seller lead tables or platform-specific conversation tables for normal platform ingestion.

## Platform values

Current allowed `conversation_threads.platform` / `conversation_messages.platform` values:

- `craigslist_email`
- `craigslist_chat`
- `facebook_marketplace`
- `ebay`
- `telegram`
- `gmail`
- `sms`
- `manual`
- `other`

## Storage paths

Raw:

```text
local_data/furniture_conversations/raw/<platform>/YYYY/MM/DD/
```

Normalized:

```text
local_data/furniture_conversations/normalized/<platform>/YYYY/MM/DD/
```

Raw payloads should include source metadata and extraction notes, but never credentials, auth tokens, session cookies, or one-time login links.

## Required normalized fields where available

Thread-level:

- `platform`
- `source_account`
- `source_thread_id`
- `source_conversation_url`
- `purpose`
- `stage`
- related contact/listing/inventory/movement IDs if known

Message-level:

- `platform`
- `source_account`
- `source_message_id`
- `source_thread_id`
- `message_at`
- `direction`: `inbound`, `outbound`, `system`, or `internal_note`
- `sender_raw`
- `recipient_raw`
- `subject`
- `body_text`
- `body_preview`
- `message_url`
- `raw_message_path`
- attachments metadata if present

## Matching priority

1. phone
2. email
3. `(username_platform, platform_contact_id)`
4. `(username_platform, username)` provisional
5. fuzzy/name/title-only = review only

Do not silently create duplicate contacts from weak name-only data.

## Strong item/listing evidence

Auto-link listing/inventory only when evidence is strong, e.g.:

- listing URL
- external listing ID
- known source conversation URL tied to an existing listing
- exact internal listing ID / item ID

Weak title-only matches should be surfaced for review.

## Current implemented platform sources

### Craigslist email

Source:

- Gmail messages from Craigslist email relay.

Current helper:

- `scripts/backfill_gmail_craigslist_conversations.py`
- `scripts/normalize_gmail_conversation_message.py`

### Craigslist chat

Sources:

- Gmail notification emails.
- Managed browser on-site chat capture.

Current skill:

- `skills/craigslist-chat-browser-capture/`

Notes:

- Actual chat text requires logged-in browser session.
- a human operator may complete login/captcha/2FA.
- Use browser capture to resolve `craigslist_chat_capture_needed`.
- internal-tracker tracks exact timestamp/follow-up refinement.

### Facebook Marketplace

Policy:

- Do not broadly capture all visible chats until platform-specific policy is defined.
- Capture only marketplace/business-scoped threads or known business URLs/notifications once approved.
- If personal/social content appears, stop broad capture and record a policy/blocker note.

Tracked by:

- internal-tracker.

## Current scheduled monitor

Cron:

- `furniture-conversation-monitor-business-hours`
- `0 8,11,14,17,19 * * *` America/New_York
- Isolated session.
- Low-noise: unchanged actionable queue items should not repeatedly alert.

## Existing scripts

- `scripts/run_conversation_monitor.py`
- `scripts/backfill_gmail_craigslist_conversations.py`
- `scripts/normalize_gmail_conversation_message.py`
- `scripts/link_conversation_records.py`
- `scripts/apply_conversation_workflow_rules.py`

## Documentation

- `docs/CONVERSATION_LAYER_CURRENT_STATE.md`
- `docs/CONVERSATION_LAYER_DESIGN.md`
- `local_data/furniture_conversations/README.md`
- `docs/awf-158-conversation-layer-schema-design.md`
