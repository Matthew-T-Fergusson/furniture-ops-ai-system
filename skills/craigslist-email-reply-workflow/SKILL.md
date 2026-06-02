---
name: craigslist-email-reply-workflow
description: Draft, preview, approve, and send Craigslist email-relay replies for the furniture business using Gmail/gog and the shared conversation layer. Use when a craigslist_email conversation needs a response, human operators asks to reply to a Craigslist email lead, or Lex needs to preserve Gmail thread context while logging the outbound reply into conversation_messages.
---

# Craigslist Email Reply Workflow

Use this skill to handle Craigslist **email relay** replies. Do not use it for Craigslist on-site chat; route on-site chat to `craigslist-chat-browser-capture`.

## Current policy

- Do not auto-send external replies.
- Draft a reply and show a pre-send preview.
- a human operator may approve/send shared furniture-business replies.
- Send replies in-thread whenever possible.
- After sending, log/upsert the outbound message into the conversation layer.

## Standard workflow

1. **Read the conversation**
   - Use `active_conversation_queue` to identify the thread.
   - Pull recent `conversation_messages` for context.
   - If Gmail IDs/thread IDs are available, inspect the Gmail thread if needed.

2. **Draft the reply**
   - Keep it short, businesslike, and buyer/seller appropriate.
   - Answer only from known facts.
   - If price, availability, dimensions, pickup windows, or delivery terms are unknown, ask one clear question or flag for human operators.

3. **Show pre-send preview**
   - Include account, channel/platform, recipient, Gmail thread/message IDs if known, subject, body, and conversation/thread ID.
   - State clearly that this is a reply, not a new email.
   - Ask for approval before sending.

4. **Dry-run when possible**
   - Use `gog gmail send --dry-run` for command validation if a send command is assembled.

5. **Send only after explicit approval**
   - Use Gmail reply threading flags: `--reply-to-message-id` or `--thread-id`.
   - Prefer `--reply-all` only if the original recipients should remain included.

6. **Record outbound message**
   - Save raw/normalized outbound payload under `local_data/furniture_conversations/`.
   - Upsert `conversation_messages` with `platform='craigslist_email'`, `direction='outbound'`, and `source_system='gog_gmail_send'` or equivalent.
   - Update `conversation_threads.last_outbound_at`, `last_message_at`, `needs_reply=false`, `stage='waiting_on_other_party'` unless the reply completes the thread.
   - Run workflow helpers and verify queue readback.

## Gmail command shape

Use Lex Gmail account unless the thread proves another account owns the relay:

```bash
gog gmail send \
  --account craigslist-account@example.invalid \
  --thread-id '<gmail_thread_id>' \
  --reply-to-message-id '<gmail_message_id>' \
  --reply-all \
  --subject '<subject>' \
  --body-file /tmp/craigslist_reply.txt \
  --dry-run
```

After explicit approval, remove `--dry-run`.

If `--reply-all` would include unwanted recipients, use explicit `--to` instead.

## Pre-send preview format

```text
Craigslist email reply preview

Type: REPLY, not new email
From/account: craigslist-account@example.invalid
To: <recipient or reply-all>
Thread: <conversation_thread_id> / Gmail thread <id>
Subject: <subject>
Listing/item: <listing title/item if known>

Body:
<reply body>

Approval needed: Reply “send” to send as-is, or tell me edits.
```

## Safety/quality rules

- Never include the operator-personal context unless explicitly approved and relevant.
- Do not invent listing details.
- Do not negotiate final pricing without human operators approval unless a future policy allows it.
- Keep buyer replies direct: availability, price, pickup logistics, dimensions/photos, and next step.
- Preserve Craigslist relay privacy; do not expose private direct emails/phones unless human operators approved.
- If the lead is ambiguous or likely spam, recommend no reply or a clarification rather than sending.

## Useful DB commands

Read queue rows for Craigslist email:

```bash
docker exec -i lex-postgres psql -U lex -d inspiring_works_llc -X -q -P pager=off -c \
"SELECT conversation_thread_id, queue_urgency, queue_reason, platform, contact_name, latest_subject, latest_body_preview, source_conversation_url, next_action_note FROM active_conversation_queue WHERE platform='craigslist_email' ORDER BY queue_sort_bucket, queue_sort_at NULLS LAST;"
```

Read messages for a thread:

```bash
docker exec -i lex-postgres psql -U lex -d inspiring_works_llc -X -q -P pager=off -c \
"SELECT conversation_message_id, source_message_id, source_thread_id, message_at, direction, sender_raw, recipient_raw, subject, body_text, raw_message_path FROM conversation_messages WHERE conversation_thread_id=<id> ORDER BY message_at, conversation_message_id;"
```

Run post-send helpers:

```bash
python3 scripts/link_conversation_records.py --apply --readback
python3 scripts/apply_conversation_workflow_rules.py --apply --readback
```

## References

Read `references/craigslist-email-reply-reference.md` for storage paths, CLI notes, and related Jira context.
