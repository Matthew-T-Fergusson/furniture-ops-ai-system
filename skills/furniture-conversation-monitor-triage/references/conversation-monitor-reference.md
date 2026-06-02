# Conversation Monitor Reference

## Primary scripts

From the repository root:

- `scripts/run_conversation_monitor.py`
  - top-level low-noise monitor wrapper.
  - uses `monitor_state.json` to suppress unchanged queue items.
- `scripts/backfill_gmail_craigslist_conversations.py`
  - Gmail/Craigslist backfill.
- `scripts/normalize_gmail_conversation_message.py`
  - raw + normalized payload capture for Gmail messages.
- `scripts/link_conversation_records.py`
  - provisional contact/linking helper.
- `scripts/apply_conversation_workflow_rules.py`
  - needs_reply/follow-up helper.

## Key docs

- `docs/CONVERSATION_LAYER_CURRENT_STATE.md`
- `docs/CONVERSATION_LAYER_DESIGN.md`
- `local_data/furniture_conversations/README.md`
- `docs/awf-158-conversation-layer-schema-design.md`

## DB objects

- `conversation_threads`
- `conversation_messages`
- `active_conversation_queue`
- existing canonical links: `contacts`, `contact_roles`, `inventory`, `listings`, `pickups_deliveries`

## Current scheduled monitor

Cron job:

- `furniture-conversation-monitor-business-hours`
- schedule: `0 8,11,14,17,19 * * *` America/New_York
- isolated session
- low-noise; announces only changed/actionable queue items

## Current known limitation

Craigslist chat notification emails are captured, but actual on-site chat contents require Craigslist login/browser capture. Route those to the Craigslist chat browser capture workflow once that skill exists.

## Queue fields worth surfacing

- `conversation_thread_id`
- `queue_urgency`
- `queue_reason`
- `platform`
- `purpose`
- `stage`
- `needs_reply`
- `assigned_to`
- `contact_name` / `contact_username`
- `listing_title` / `listing_url`
- `source_conversation_url`
- `latest_subject`
- `latest_body_preview`
- `next_action_at`
- `next_action_note`

## Status/Jira context

- internal-tracker through internal-tracker: conversation foundation/backfill complete.
- internal-tracker: business-hours monitor scheduled complete.
- internal-tracker: this skill.
- Follow-ups: internal-tracker urgency definitions, internal-tracker real-lead validation, internal-tracker email reply skill, internal-tracker Craigslist chat browser capture skill, internal-tracker platform ingestion framework.
