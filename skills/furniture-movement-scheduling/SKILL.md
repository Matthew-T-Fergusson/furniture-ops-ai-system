---
name: furniture-movement-scheduling
description: Use when creating or updating furniture pickup, delivery, storage transfer, buyer pickup, contractor move, or calendar-driven scheduled movement rows in pickups_deliveries.
---

# Furniture Pickup / Delivery Scheduling

## Table

Use `pickups_deliveries` as the single scheduling table for:

- `acquisition_pickup`
- `buyer_pickup`
- `seller_delivery`
- `storage_transfer`
- `contractor_delivery`
- `return_pickup`
- `other`

## Required fields

When Primary Partner/Operations Partner says an item is sold or has a deposit, capture scheduling details as they arrive. Missing buyer/contact/address/time details are warnings/follow-ups, not blockers for recording the deposit/status when the money/status facts are clear.

Capture when available:

- `movement_type`
- `inventory_uid` and/or `inventory_group_id`
- customer/counterparty name
- customer phone/email/contact method
- `contact_id` when known, otherwise counterparty name/contact
- delivery/pickup address/location
- storage unit / origin location
- planned delivery/pickup date and target arrival/delivery time
- scheduled start/end or time window
- assigned person/driver/helper
- payment summary: item price, delivery fee, total owed, deposit paid, balance owed, who received deposit, expected final method
- special instructions: stairs, elevator, loading dock, gate code, carry distance, tools/blankets, etc.
- `movement_status`: `planned`, `confirmed`, `completed`, `cancelled`, `rescheduled`
- notes
- `calendar_event_id` after creating a calendar event

## Calendar workflow

For furniture-business workdays/scheduling with Operations Partner:

- use Primary Partner's shared Lex-controlled calendar
- invite `primary@example.invalid`
- invite Operations Partner at `ops@example.invalid` and `ops-alt@example.invalid`
- preview event metadata before creation/update for now unless Primary Partner explicitly says to create. Primary Partner may later allow automation if calendar previews become a drag because the underlying delivery data was already confirmed.

Calendar event details must include item name/ID, customer name/contact, address/location, Google Maps navigation link when address is available, storage/origin, assigned person/helper, special instructions, and payment summary (price, delivery fee, total owed, deposit paid/who received it, balance owed, expected final method if known).

Delivery timing rule:

- target delivery time = customer-agreed delivery/arrival time
- default load time = 45 minutes
- estimate drive time from storage/origin to destination
- event start = target delivery time - drive time - 45 minutes
- event end = target delivery time + 45 minutes
- example: 11:00 delivery, 1h drive, 45m load -> event 9:15-11:45

For any day with deliveries/pickups, create/update one all-day summary invite for Primary Partner and Operations Partner with item name, time, and contact for each activity.

Calendar event creation/update should mirror the DB row and write back `calendar_event_id`. Any delivery/pickup update should update both DB row and related calendar invite(s).

## Pending sale integration

When a deposit creates `pending_sale`, ask for buyer/contact and delivery/pickup timeline so a `pickups_deliveries` row can be created.

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
