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

Capture when available:

- `movement_type`
- `inventory_uid` and/or `inventory_group_id`
- `contact_id` or counterparty name/contact
- address/location
- scheduled start/end or time window
- assigned person/driver/helper
- `movement_status`: `planned`, `confirmed`, `completed`, `cancelled`, `rescheduled`
- notes
- `calendar_event_id` after creating a calendar event

## Calendar workflow

For furniture-business workdays/scheduling with Operations Partner:

- use Primary Partner's shared Lex-controlled calendar
- invite `primary-partner@example.invalid`
- invite Operations Partner at `ops-partner@example.invalid` and `ops-partner-alt@example.invalid`
- preview event metadata before creation unless Primary Partner explicitly says to create

Calendar event creation/update should mirror the DB row and write back `calendar_event_id`.

## Pending sale integration

When a deposit creates `pending_sale`, ask for buyer/contact and delivery/pickup timeline so a `pickups_deliveries` row can be created.
