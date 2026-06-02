# Furniture Conversation Layer — Current State

Updated: 2026-06-02

## What works now

- Craigslist email relay messages are captured from Gmail, normalized, inserted into the shared conversation tables, matched to listings/inventory when the listing URL or external listing ID is present, and surfaced in `active_conversation_queue`.
- Craigslist on-site chat notification emails from `robot@craigslist.org` are captured as `craigslist_chat` system messages.
- Actual Craigslist chat contents can be captured through the managed OpenClaw browser session, normalized into `conversation_messages`, linked to contacts/listings, and moved into the active queue.
- Lead-quality review fields exist on `conversation_threads` and are exposed in `active_conversation_queue`:
  - `lead_quality_tag`
  - `lead_quality_reviewed_by`
  - `lead_quality_reviewed_at`
  - `lead_quality_notes`

## Operating decisions from 2026-06-02

### Craigslist chat is notification-gated

The scheduled monitor should check Gmail first. If Gmail has a new generic Craigslist chat notification email, that is the trigger for browser chat capture.

If there is no new Craigslist chat notification email, routine browser chat scanning is not needed.

Reason: Craigslist notification emails do not include the actual listing/contact/message detail, but they are a reliable low-cost signal that the heavier browser capture workflow should run.

### Generic chat notifications stay capture-needed

A generic `new craigslist chat message` notification should remain in `active_conversation_queue` with `craigslist_chat_capture_needed` until actual chat state is captured from the logged-in Craigslist UI.

### Lead quality is human-reviewed for now

Do not spend tokens reading/classifying every message for lead quality yet. human operators should initially label examples and outcomes manually so future automation has real judgment data.

Examples of human-reviewed tags:

- `actionable`
- `low_intent`
- `hostile_noise`
- `price_complaint_no_buy_signal`
- `spam`
- `harassment`
- `block_candidate`
- `blocked`
- `not_a_lead`
- `needs_human_review`

The internal-tracker hostile/no-buy-signal test message was labeled `hostile_noise`, but no automatic queue suppression/classification was added.

### Test traffic should not pollute the active queue

internal-tracker test conversations were archived with `needs_reply = false` and `priority = low` after validation. Test/archive handling should be standardized in the CRM-style disposition workflow.

### Facebook Marketplace remains conservative/manual

Facebook Marketplace is valuable for sales but strict enough that broad automation or capture is not worth risking account restrictions. Keep Facebook manual or human-triggered/minimal until platform-specific privacy/capture policy is approved.

## Relevant Jira follow-ups

- internal-tracker: marketplace posting and listing status workflow.
- internal-tracker: routine Lex-approved replies; due 2026-06-16, full human review until then.
- internal-tracker: platform-specific privacy/capture policy, especially Facebook.
- internal-tracker: trigger Craigslist browser chat capture from new chat notification emails.
- internal-tracker: CRM-style lead disposition and queue hygiene workflow.
- internal-tracker: end-to-end Craigslist reply workflow test with internal-tracker messages.

## Key implementation files

- `sql/009_conversation_layer_foundation.sql`
- `sql/010_active_conversation_queue.sql`
- `sql/011_queue_urgency_rules.sql`
- `sql/012_lead_quality_review_fields.sql`
- `scripts/backfill_gmail_craigslist_conversations.py`
- `scripts/run_conversation_monitor.py`
- `scripts/link_conversation_records.py`
- `scripts/apply_conversation_workflow_rules.py`
- `skills/furniture-conversation-monitor-triage/SKILL.md`
- `skills/craigslist-chat-browser-capture/SKILL.md`
- `skills/craigslist-email-reply-workflow/SKILL.md`
- `skills/furniture-platform-message-ingestion-framework/SKILL.md`
