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
- `contact_activity_timeline` provides the CRM-style "show everything that happened with this person" view. It preserves every message row, includes conversation-thread/listing context, movement events, and explicitly contact-linked cash flows, with relationship strength and related IDs in JSON context.
- `response_sla_thread_metrics` and `response_sla_metrics` expose marketplace response performance separately from item-demand analytics. The SLA target is 24h primary / 48h secondary, scoped to marketplace platforms, with every inbound-to-next-outbound response pair preserved at thread level and platform rollups available for dashboards.

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

Raw CRM/audit views such as `contact_activity_timeline` should not hide archived/test activity by default. Dashboards and agent summaries can filter those rows, but the raw timeline remains useful when reviewing test behavior or debugging workflow regressions.

### Response SLA measures responsiveness, not item demand

`response_sla_thread_metrics` is the raw/auditable layer. It includes marketplace conversations from Craigslist email/chat, Facebook Marketplace, eBay, and future marketplace platforms; it also carries `is_test_or_archived` so dashboards can filter test/archive/spam-like rows without hiding them from audit queries.

`response_sla_metrics` rolls those rows up by platform:

- `threads_with_inbound`: marketplace conversations where someone contacted us.
- `threads_responded`: conversations with an outbound response after the first inbound.
- `response_rate_pct`: percent of inbound threads that received a response.
- `median_first_response_hours`: typical first response speed.
- `p90_first_response_hours`: slow-end response speed; 90% of responded threads were faster than this.
- `open_breaches_24h`: currently unanswered marketplace threads older than the primary SLA target.
- `open_breaches_48h`: currently unanswered marketplace threads past the secondary severity marker.
- `dashboard_default_*`: variants excluding test/archive rows for normal KPI reporting.

This intentionally does not answer “which items are getting the most interest?” That belongs in a separate listing-demand / item-interest metric so sales demand is not mixed with our reply-speed performance.

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
- `sql/013_contact_activity_timeline.sql`
- `sql/014_response_sla_metrics.sql`
- `scripts/backfill_gmail_craigslist_conversations.py`
- `scripts/run_conversation_monitor.py`
- `scripts/link_conversation_records.py`
- `scripts/apply_conversation_workflow_rules.py`
- `skills/furniture-conversation-monitor-triage/SKILL.md`
- `skills/craigslist-chat-browser-capture/SKILL.md`
- `skills/craigslist-email-reply-workflow/SKILL.md`
- `skills/furniture-platform-message-ingestion-framework/SKILL.md`
