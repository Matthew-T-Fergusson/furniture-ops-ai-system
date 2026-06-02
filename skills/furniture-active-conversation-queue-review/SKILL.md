---
name: furniture-active-conversation-queue-review
description: Review and triage the furniture-business active conversation queue for human operators, including actionable marketplace leads, needs_reply/follow-up items, craigslist_chat_capture_needed rows, owner/next-action recommendations, and low-noise summaries from active_conversation_queue. Use when asked what furniture conversations need action, who should respond, what to do next, or to prepare a concise daily/adhoc queue review.
---

# Furniture Active Conversation Queue Review

Use this skill to turn `active_conversation_queue` into a human-operable action list for the operator and the operator.

## Goal

Answer: **What conversations need action, why, who should handle them, and what is the next safe step?**

Do not send external replies from this skill. Route reply drafting to the platform-specific reply workflow and require human operators approval unless a future policy explicitly allows automation.

## Standard review order

1. Refresh or read the current queue.
2. Group items by urgency and queue reason.
3. For each actionable row, identify:
   - platform
   - queue reason
   - buyer/seller/contact label
   - listing/item if linked or obvious
   - latest preview
   - source link
   - owner/assignee if present
   - recommended next action
4. Separate real customer/business action from system/test/noise.
5. Keep the report compact.
6. If no actionable changes exist in a scheduled/background run, reply exactly `NO_REPLY`.

## First command to run

For an ad hoc human operators review, force a current report:

```bash
python3 scripts/run_conversation_monitor.py --force-report
```

For a scheduled/background queue check, use low-noise mode:

```bash
python3 scripts/run_conversation_monitor.py
```

If the monitor output is exactly `NO_ACTIONABLE_CHANGES`, reply exactly `NO_REPLY` for scheduled/background runs.

## Direct queue readback

Use this when the monitor output is insufficient or when you need details:

```bash
docker exec -i lex-postgres psql -U lex -d inspiring_works_llc -X -q -P pager=off -c \
"SELECT conversation_thread_id, queue_urgency, queue_reason, platform, purpose, stage, needs_reply, assigned_to, contact_name, contact_username, listing_title, listing_url, latest_subject, latest_body_preview, source_conversation_url, next_action_at, next_action_note FROM active_conversation_queue ORDER BY queue_sort_bucket, queue_sort_at NULLS LAST, conversation_thread_id;"
```

## Queue reason playbook

### `craigslist_chat_capture_needed`

Recommended next action:

- Run/use `craigslist-chat-browser-capture`.
- If login/captcha/2FA blocks capture, ask a human operator to complete it.
- Do not mark resolved until actual on-site chat state is captured.

### `needs_reply`

Recommended next action:

- Summarize the message and propose the safest response path.
- Route to platform-specific reply workflow, e.g. Craigslist email reply or Craigslist chat reply/capture.
- Do not send without approval.

### `follow_up_due_24h`

Default urgency: `high`, not `urgent`, unless explicit priority/next-action/schedule rules override it.

Recommended next action:

- Confirm whether the latest meaningful message was outbound and whether follow-up is appropriate.
- Draft a short follow-up if it is a real buyer/seller thread.
- If thread is a test/noise item, recommend closing or suppressing it instead.

### `new_thread`

Recommended next action:

- Identify contact/platform identity.
- Link listing/item only on strong evidence.
- Set purpose/stage if clear.
- Recommend owner and next step.

### `scheduled`

Recommended next action:

- Check whether pickup/delivery details are represented in `pickups_deliveries`.
- If logistics are missing, route to `furniture-movement-scheduling`.

## Output format

Use a concise action queue:

```text
Furniture conversation queue

Urgent
1. [platform] contact/listing — reason
   Latest: <preview>
   Next: <recommended action>
   Link: <source/listing link>

Normal / Watch
...

Suggested cleanup
- <test/noise/suppression items>
```

If there are more than 5 active rows, group lower-priority items and show only the top details unless the operator asks for the full list.

## Assignment defaults

- the operator: owner-level decisions, pricing, policy, sensitive replies, personal-account/platform-login needs.
- the operator: furniture-business operational replies, pickup/sales coordination, manual login/captcha/2FA help once access is set up.
- Lex: capture, normalize, summarize, draft, update DB/Jira, and prepare approved-send text.

## Noise control

- Do not repeatedly alert unchanged queue items.
- Call out repeated/test items as cleanup candidates instead of treating them as real urgent work.
- If a visible timestamp is coarse/provisional, mention that before escalating due-date urgency.

## References

Read `references/active-queue-review-reference.md` for schema fields, current known caveats, and related Jira context.
