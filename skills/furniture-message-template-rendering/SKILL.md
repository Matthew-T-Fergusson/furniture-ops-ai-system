---
name: furniture-message-template-rendering
description: Render approval-gated furniture CRM reply templates from message_templates for Craigslist/Facebook/manual marketplace replies, including merge-field validation, missing-field preview messages, channel/base template handling, and handoff to human-approved send workflows. Use when drafting repeatable marketplace replies such as still available, pickup scheduling, dimensions, delivery terms, or conservative counteroffer/hold-price responses.
---

# Furniture Message Template Rendering

Use this skill when drafting repeatable furniture-business marketplace replies from the `message_templates` table.

## Policy

- Templates are **draft/preview only**. Never send externally from this skill.
- Human approval is required before any Craigslist/Facebook/email/chat/SMS send.
- DNC/send guardrails still apply at send/log time.
- `message_templates.use_count` counts actual logged/sent outbound usage, not previews.
- Default pricing posture: do **not** invite negotiation. Use hold-price wording unless Matt/Stephen explicitly approves a different strategy.

## Template model

Core table: `message_templates`

Important columns:
- `template_key` — stable snake_case key, e.g. `still_available`.
- `body` — base template using `{{field_name}}` syntax.
- `merge_fields_json` — required/optional fields plus source hints.
- `channels` — where the base template is valid. `base` means generally reusable across channels.
- `channel_overrides_json` — channel-specific notes/suffixes/instructions while preserving one base template.
- `active`, `version_no`, `supersedes_template_id` — versioning. Prefer new versions over in-place rewrites for material wording changes.
- `use_count` — increment only after an outbound message is logged/sent with `conversation_messages.template_id`.

Outbound/logged message linkage:
- `conversation_messages.template_id` points to the template used for an outbound message.
- Leave null for inbound, purely manual, or non-template messages.

## Rendering workflow

1. Select candidate template by intent and channel.
   - Availability → `still_available`
   - Scheduling → `pickup_scheduling`
   - Dimensions/details → `dimensions_reply`
   - Delivery logistics → `delivery_terms`
   - Price counteroffer → `counteroffer_hold_price`
2. Collect values from canonical sources where available:
   - `conversation_threads`
   - `contacts`
   - `listings`
   - `inventory`
   - `pickups_deliveries`
   - manual context from Matt/Stephen
3. Render with SQL helper:

```sql
SELECT *
FROM render_message_template(
  'still_available',
  'craigslist_email',
  '{"listing_title":"Walnut side table","pickup_area":"Frederick","availability_window":"Tomorrow afternoon can work."}'::jsonb
);
```

4. If `preview_status = 'needs_fields'`:
   - Show the preview body with visible `{{missing_field}}` placeholders.
   - Show `missing_fields` and `preview_message`.
   - Ask Matt/Stephen for the missing value or offer a manual wording edit.
5. If `preview_status = 'blocked'`:
   - Do not use that template/channel combination without explicit manual override.
6. If `preview_status = 'ready'`:
   - Present the draft as a pre-send preview.
   - Include template key, channel, missing fields = none, and approval reminder.
   - Hand off to the appropriate send workflow only after explicit approval.

## Preview format

Use this compact preview before any send:

```text
Template: <template_key> / v<version_no if known>
Channel: <channel>
Status: <ready|needs_fields|blocked>
Missing: <none or field list>

Draft:
<rendered_body>

Approval required before external send.
```

## Current seeded templates

- `still_available`
- `pickup_scheduling`
- `dimensions_reply`
- `delivery_terms`
- `counteroffer_hold_price`

## Editing/versioning guidance

- Minor typo fix before use: edit in place is acceptable.
- Material wording/policy change: create a new row with incremented `version_no`, set `supersedes_template_id`, and deactivate the old row.
- Add future channels by adding channel names to `channels` and optional entries in `channel_overrides_json`; avoid duplicating whole templates unless wording truly diverges.
