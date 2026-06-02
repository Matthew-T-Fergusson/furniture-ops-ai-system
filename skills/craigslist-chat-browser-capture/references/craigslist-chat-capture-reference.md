# Craigslist Chat Capture Reference

## Related Jira

- internal-tracker: Create skill: Craigslist chat browser capture workflow.
- internal-tracker: the operator browser access via Tailscale VPN.
- internal-tracker: Future policy for Lex-approved routine marketplace replies.
- internal-tracker: Platform-specific privacy/capture policies.

## Key files

- `local_data/furniture_conversations/README.md`
- `docs/CONVERSATION_LAYER_CURRENT_STATE.md`
- `docs/CONVERSATION_LAYER_DESIGN.md`
- `scripts/run_conversation_monitor.py`
- `scripts/backfill_gmail_craigslist_conversations.py`
- `scripts/link_conversation_records.py`
- `scripts/apply_conversation_workflow_rules.py`

## Storage convention

Use paths under:

```text
local_data/furniture_conversations/raw/craigslist_chat/YYYY/MM/DD/
local_data/furniture_conversations/normalized/craigslist_chat/YYYY/MM/DD/
```

Raw capture should include:

- source chat URL
- capture timestamp
- visible page title/URL
- extracted message text
- visible timestamps/sender labels if available
- extraction notes/blockers
- optional screenshot path only if needed

Normalized message rows should map to `conversation_messages` using:

- platform: `craigslist_chat`
- source_account: usually `craigslist-account@example.invalid` or Craigslist account identifier
- source_thread_id: source chat/thread ID or stable hash/URL-derived ID
- source_message_id: source ID if exposed; otherwise hash fallback
- direction: inbound/outbound/system/internal_note
- body_text/body_preview
- raw_message_path

## Current live blocker example

Current queue has a Craigslist chat notification from Gmail:

```text
https://www.craigslist.org/d/APPOK/#chat=1~email~craigslist-account@example.invalid
```

The Gmail notification is already stored as a system message. Actual chat content is not captured until the browser session is logged in and the chat UI is read.

## Privacy/platform note

Craigslist is currently treated as furniture-business chat. Other platforms, especially Facebook, need platform-specific privacy filters because personal/social messages may be adjacent to marketplace messages.

## Reply policy

Current: no auto-send. Draft replies and ask human operators approval.

Future autonomous routine replies are deferred to internal-tracker.
