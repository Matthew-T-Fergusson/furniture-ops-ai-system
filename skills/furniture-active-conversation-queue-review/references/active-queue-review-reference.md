# Active Conversation Queue Review Reference

## Related Jira

- internal-tracker: active conversation queue/report view.
- internal-tracker: scheduled business-hours monitor.
- internal-tracker: furniture conversation monitor triage skill.
- internal-tracker: Craigslist email reply workflow skill.
- internal-tracker: Craigslist chat browser capture skill.
- internal-tracker: platform message ingestion framework skill.
- internal-tracker: this active queue review skill.
- internal-tracker: refine Craigslist chat timestamp/follow-up logic.

## Main DB object

Use `public.active_conversation_queue`.

Important fields:

- `conversation_thread_id`
- `queue_urgency`
- `queue_reason`
- `queue_sort_bucket`
- `queue_sort_at`
- `platform`
- `purpose`
- `stage`
- `needs_reply`
- `assigned_to`
- `contact_name`
- `contact_username`
- `listing_title`
- `listing_url`
- `source_conversation_url`
- `latest_subject`
- `latest_body_preview`
- `next_action_at`
- `next_action_note`

## Useful SQL

Full queue:

```sql
SELECT conversation_thread_id, queue_urgency, queue_reason, platform, purpose, stage,
       needs_reply, assigned_to, contact_name, contact_username,
       listing_title, listing_url, latest_subject, latest_body_preview,
       source_conversation_url, next_action_at, next_action_note
FROM active_conversation_queue
ORDER BY queue_sort_bucket, queue_sort_at NULLS LAST, conversation_thread_id;
```

Conversation messages for one thread:

```sql
SELECT conversation_message_id, message_at, direction, sender_raw, recipient_raw,
       subject, body_text, raw_message_path
FROM conversation_messages
WHERE conversation_thread_id = <id>
ORDER BY message_at, conversation_message_id;
```

## Current known caveat

internal-tracker captured Craigslist chat messages from browser DOM, but Craigslist exposed visible timestamps only as `yesterday`. Current DB timestamps for that capture are provisional sequence timestamps. internal-tracker tracks improving exact timestamp extraction and follow-up behavior.

When queue urgency is driven by the 24h follow-up rule and timestamps are provisional, mention the caveat and avoid over-escalating.

## Current live example after internal-tracker

Thread 2:

- platform: `craigslist_chat`
- contact: `Du`
- latest preview: `Yes — Lex can see and reply here. Testing Craigslist chat workflow.`
- queue state after internal-tracker: `follow_up_due_24h` / `high`
- interpretation: likely test/noise from workflow validation, not a real buyer action.
- recommended cleanup: mark handled/completed or suppress test follow-up if the operator agrees.

## Related skills to route into

- `furniture-conversation-monitor-triage`: monitor-level check/report.
- `craigslist-chat-browser-capture`: actual Craigslist on-site chat capture.
- `furniture-platform-message-ingestion-framework`: adding/extending platform sources.
- `furniture-movement-scheduling`: pickup/delivery details.
- Future `craigslist-email-reply-workflow`: Craigslist email reply drafting/sending approval.

## Reply approval rule

Current rule: do not send external replies automatically. Draft and get human operators approval.

internal-tracker tracks future policy for routine approved replies.
