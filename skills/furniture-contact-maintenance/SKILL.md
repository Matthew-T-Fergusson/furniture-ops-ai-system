---
name: furniture-contact-maintenance
description: Use when importing or maintaining furniture contacts, Contact List Google Sheet sync, contact_roles, buyer/seller/contractor/vendor/partner records, contractor ratings, or contact dedupe.
---

# Furniture Contact Maintenance

## Tables

- `contacts`
- `contact_roles`
- `contractor_ratings`

Role values:

- `buyer`
- `seller`
- `source`
- `contractor`
- `delivery_helper`
- `partner`
- `payer`
- `payee`
- `marketplace_lead`
- `vendor`
- `other`

## Import source

Google Sheet: `Furniture Biz Operations 2026` -> `Contact List`.

Current sheet seed import added contacts from the tab plus Primary Partner and Operations Partner.

## Dedupe

Prefer matching by:

- phone when present
- email when present

Policy:

- Exact phone and/or exact email match = likely same contact; preview if merging would overwrite fields/notes/ratings.
- High-probability fuzzy name match without phone/email = flag for Primary Partner/Operations Partner decision; do not merge automatically.
- Name-only matches are not enough for automatic dedupe.

Do not overwrite existing notes/ratings without preview.

## Conservative cleanup

If a phone number appears in an email column, import as phone and note the correction. Leave ambiguous values alone.

## Ratings

Contractor ratings are interaction/job based where possible, optionally tied to `pickups_deliveries.movement_id`.

## Agent action audit trail

For any AI-assisted workflow that previews, writes, blocks, or fails, create an `agent_action_log` entry or equivalent implementation note with:

- `skill_name` matching this skill
- capped/sanitized `chat_input_excerpt`
- `operation_summary` with enough detail to replicate the action
- summarized `guardrails_before` and `guardrails_after`
- affected `entity_type` / `entity_id`
- status: `preview_only`, `success`, `failed`, `blocked_by_guardrail`, or `needs_human_review`
- `human_feedback` when Matt, a reviewer, or a collaborator corrects behavior

Public examples must stay synthetic. Do not include real private chat text, receipts, customer/contact data, credentials, addresses, phone numbers, or raw production SQL payloads in the published repository.
