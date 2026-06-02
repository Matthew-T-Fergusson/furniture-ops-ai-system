---
name: craigslist-chat-browser-capture
description: Capture and triage Craigslist on-site chat messages for the furniture business using the managed OpenClaw browser, especially when active_conversation_queue shows craigslist_chat_capture_needed. Use for Craigslist chat login/session checks, browser chat extraction, raw/normalized storage, DB upsert, and handoff to reply drafting after human operators approval.
---

# Craigslist Chat Browser Capture

Use this skill when a furniture conversation queue item has `queue_reason = craigslist_chat_capture_needed`, or when human operators asks to open/capture Craigslist chat messages. Scheduled runs should reach this skill only after Gmail captured a new Craigslist chat notification email; if no new notification exists, skip browser chat scanning.

## Scope

This workflow captures actual Craigslist on-site chat contents. Gmail notifications alone are not enough.

Current policy:

- Use the managed OpenClaw browser session by default.
- a human operator may complete Craigslist login, captcha, or 2FA for shared furniture-business workflows.
- Do not bypass captcha/2FA.
- Capture Craigslist chat together with the scheduled message-monitoring workflow when feasible, but keep it notification-gated: Gmail chat notification first, browser capture second.
- If browser capture becomes too costly/flaky, reduce cadence rather than skipping chat when notifications indicate active messages.
- Do not send replies automatically. Draft + preview + human operators approval first.

## Browser workflow

1. Read the active queue or use the provided Craigslist chat URL.
2. Open the chat URL in the managed browser.
3. Snapshot the page.
4. If login/captcha/2FA is required:
   - stop and ask human operators to complete it;
   - keep the DB queue item active;
   - do not mark capture resolved.
5. If the chat page is visible:
   - capture visible message text, sender side, timestamps if present, and thread/listing context;
   - save raw browser evidence as JSON/text under `local_data/furniture_conversations/raw/craigslist_chat/`;
   - upsert normalized messages into `conversation_messages`;
   - run matching and workflow helpers;
   - verify `active_conversation_queue` changed from `craigslist_chat_capture_needed` to the correct business state.

## Screenshot policy

Do not use screenshots as default storage.

Use screenshots only when:

- extraction is ambiguous,
- the page is blocked/login/captcha/error,
- sender/timestamp grouping is visually unclear,
- or proof of page state is useful.

Default evidence should be text/HTML/JSON-like raw capture + normalized DB rows.

## Queue resolution rule

Resolve `craigslist_chat_capture_needed` only after actual chat state is captured. A generic Gmail notification alone is not enough to resolve it, because it does not carry listing/contact/message details.

After capture:

- If buyer/seller message needs response: set/keep `needs_reply = true`; queue reason should become `needs_reply` or another business reason.
- If no action remains: set `needs_reply = false` and appropriate stage (`waiting_on_other_party`, `completed`, etc.).
- If blocked by login/captcha/session: keep `craigslist_chat_capture_needed` active and add/keep a note such as `login/session required`.

## Dedupe rule

Prefer source message IDs if Craigslist exposes them. If not, dedupe by normalized hash of:

- platform
- chat/thread URL
- sender side
- timestamp if visible
- body text
- message order / capture time as fallback

## Commands / DB helpers

Read current Craigslist chat capture-needed queue rows:

```bash
docker exec -i lex-postgres psql -U lex -d inspiring_works_llc -X -q -P pager=off -c \
"SELECT conversation_thread_id, source_conversation_url, latest_body_preview, next_action_note FROM active_conversation_queue WHERE queue_reason='craigslist_chat_capture_needed' ORDER BY queue_sort_bucket, queue_sort_at NULLS LAST;"
```

Run helpers after capture/upsert:

```bash
python3 scripts/link_conversation_records.py --apply --readback
python3 scripts/apply_conversation_workflow_rules.py --apply --readback
```

## References

Read `references/craigslist-chat-capture-reference.md` for storage paths, Jira context, and implementation details when needed.
