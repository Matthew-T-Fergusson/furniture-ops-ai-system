---
name: furniture-conversation-monitor-triage
description: Run or interpret the furniture-business conversation monitor and active_conversation_queue, including Gmail/Craigslist backfill, low-noise queue alerts, needs_reply/follow-up triage, and handoff to Craigslist email/chat reply workflows. Use when the operator asks to check furniture messages, review active conversation leads, run the monitor, explain monitor output, or handle scheduled/ad hoc platform-message pulls.
---

# Furniture Conversation Monitor Triage

Use this skill to check the shared furniture-business conversation queue and decide what needs action.

## Core rule

Run the deterministic monitor first when the user asks to check messages/leads:

```bash
python3 scripts/run_conversation_monitor.py --force-report
```

For scheduled/quiet checks, run without `--force-report`:

```bash
python3 scripts/run_conversation_monitor.py
```

If output is exactly `NO_ACTIONABLE_CHANGES`, reply `NO_REPLY` for scheduled/background checks. In direct chat, say briefly that nothing changed if the operator explicitly asked.

## What the monitor covers now

- Gmail/Craigslist email relay messages.
- Craigslist chat notification emails.
- Raw/normalized payload capture under `local_data/furniture_conversations/`.
- DB upsert into `conversation_threads` / `conversation_messages`.
- Matching/linking helper.
- Workflow rule helper.
- Active queue readback.

It does **not** yet capture actual on-site Craigslist chat contents unless a logged-in browser/session workflow is run separately.

## Triage output

For actionable rows, report compactly:

- urgency
- queue reason
- platform
- latest preview
- source/chat/listing link
- owner/assigned_to if present
- recommended next action

Avoid dumping raw message JSON unless the operator asks.

## Queue reason handling

- `craigslist_chat_capture_needed`: tell the operator the Gmail notification is captured, but actual Craigslist chat text needs logged-in browser/session capture.
- `needs_reply`: draft or recommend a response path; do not send externally without human operators approval.
- `follow_up_due_24h`: recommend a concise follow-up.
- `scheduled`: surface logistics redundancy; verify pickup/delivery details are linked if needed.
- `new_thread`: triage contact/listing/purpose and decide owner.

## Approval and privacy

- a human operator can approve/send replies for shared furniture-business conversations.
- Do not treat this as permission to share the operator-personal context.
- For external sends, show a pre-send preview unless human operators explicitly gave the exact send text and approval.

## Useful commands

Read active queue directly:

```bash
docker exec -i lex-postgres psql -U lex -d inspiring_works_llc -X -q -P pager=off -c \
"SELECT conversation_thread_id, queue_urgency, queue_reason, platform, stage, needs_reply, latest_body_preview, source_conversation_url FROM active_conversation_queue ORDER BY queue_sort_bucket, queue_sort_at NULLS LAST, conversation_thread_id;"
```

Run lower-level backfill only:

```bash
python3 scripts/backfill_gmail_craigslist_conversations.py --max 50
```

Apply helpers independently:

```bash
python3 scripts/link_conversation_records.py --apply --readback
python3 scripts/apply_conversation_workflow_rules.py --apply --readback
```

## References

For schema/workflow details, read only when needed:

- `references/conversation-monitor-reference.md`
