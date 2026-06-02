---
name: furniture-platform-message-ingestion-framework
description: Design, run, or extend the shared furniture-business platform message ingestion framework across Craigslist email, Craigslist chat, Facebook Marketplace, eBay, SMS, Gmail, and future marketplace channels. Use when adding a new platform source, deciding platform-specific capture/privacy rules, preserving raw payloads, normalizing messages into conversation_threads/conversation_messages, or wiring ingestion into the active furniture conversation queue.
---

# Furniture Platform Message Ingestion Framework

Use this skill to ingest furniture-business messages from any platform into the shared conversation layer.

## Non-negotiable architecture

Use shared canonical tables for all platforms:

- `conversation_threads`
- `conversation_messages`
- `contacts`
- `contact_roles`
- `listings`
- `inventory`
- `pickups_deliveries`

Do **not** create platform-specific lead/message tables.

Split platforms by `platform` value, not by table. Current/future platform values include:

- `craigslist_email`
- `craigslist_chat`
- `facebook_marketplace`
- `ebay`
- `telegram`
- `gmail`
- `sms`
- `manual`
- `other`

## Standard ingestion order

For each source/platform:

1. **Capture source payload**
   - API/email/browser/manual source.
   - Do not store credentials, auth tokens, or session secrets.
   - For browser platforms, stop for login/captcha/2FA; a human operator may complete those for shared furniture-business workflows.

2. **Store raw payload**
   - Save raw JSON/text/browser evidence under `local_data/furniture_conversations/raw/<platform>/YYYY/MM/DD/`.
   - Screenshots are optional/debug-only, not default storage.

3. **Normalize message(s)**
   - Save normalized JSON under `local_data/furniture_conversations/normalized/<platform>/YYYY/MM/DD/`.
   - Extract stable source IDs if available.
   - Extract sender/recipient, message text, timestamps, thread/listing URL, attachments, and direction.

4. **Upsert canonical DB rows**
   - Upsert/locate `conversation_threads` by `(platform, source_account, source_thread_id)`.
   - Upsert `conversation_messages` by `(platform, source_account, source_message_id)` when source IDs exist.
   - If source IDs do not exist, create deterministic hash IDs from platform + source thread + sender side + timestamp/body/order/capture time.

5. **Run matching/linking**
   - Run `link_conversation_records.py --apply --readback`.
   - Create provisional contacts only when platform identity exists.
   - Auto-link item/listing only on strong evidence, e.g. listing URL or external listing ID.
   - Fuzzy/title/name-only matching is review-only.

6. **Run workflow rules**
   - Run `apply_conversation_workflow_rules.py --apply --readback`.
   - Then inspect `active_conversation_queue`.

7. **Report or stay quiet**
   - Scheduled monitors should report only new/changed actionable items.
   - If the monitor output is exactly `NO_ACTIONABLE_CHANGES`, reply exactly `NO_REPLY`.

## Platform capture policy

Every platform needs an explicit capture policy before broad automation.

For each platform define:

- whether it is business-only or mixed personal/business;
- whether Lex may capture all visible messages, marketplace-only threads, or only threads opened from known business links/notifications;
- what to do if personal/non-business content appears;
- whether raw payloads need redaction;
- whether screenshots are permitted;
- whether replies are preview-only or may be automated under a future policy.

Current defaults:

- Craigslist email: capture via Gmail; business workflow OK.
- Craigslist chat: Gmail notification emails are the gate. Only run browser chat capture when a new Craigslist chat notification email appears; do not routinely scan chat if no new notification arrived. Browser capture after logged-in session is OK for business workflow.
- Facebook Marketplace: keep manual/conservative for now. Facebook is valuable for sales but strict enough that broad automation/capture is not worth account-freeze risk; only human-triggered, low-risk, marketplace-scoped capture should be considered later.
- Lead quality: `lead_quality_*` fields are human-reviewed only for now. human operators should label early examples/outcomes before any AI/content classifier is added.
- External replies: preview + human operators approval until internal-tracker routine-reply policy is approved.

## Scheduling guidance

Craigslist email and Craigslist chat are separate communication pathways, but chat capture is notification-gated:

- scheduled monitor checks Gmail first;
- Craigslist email-relay messages are parsed/mapped directly;
- generic Craigslist chat notification emails create `craigslist_chat_capture_needed` and should trigger browser capture;
- if no new chat notification email exists, skip browser chat scanning.

If browser capture becomes resource-heavy/flaky:

- reduce scheduled cadence,
- avoid repeated unchanged alerts,
- do not omit chat capture when email notifications indicate active chat messages.

## Useful commands

Run the current low-noise monitor:

```bash
python3 scripts/run_conversation_monitor.py
```

Force an ad hoc report:

```bash
python3 scripts/run_conversation_monitor.py --force-report
```

Run helpers after a platform-specific capture:

```bash
python3 scripts/link_conversation_records.py --apply --readback
python3 scripts/apply_conversation_workflow_rules.py --apply --readback
```

Read active queue:

```bash
docker exec -i lex-postgres psql -U lex -d inspiring_works_llc -X -q -P pager=off -c \
"SELECT conversation_thread_id, queue_urgency, queue_reason, platform, stage, needs_reply, latest_body_preview, source_conversation_url FROM active_conversation_queue ORDER BY queue_sort_bucket, queue_sort_at NULLS LAST;"
```

## References

Read `references/platform-ingestion-reference.md` for schema fields, storage paths, platform rules, and related Jira context.
