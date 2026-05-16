---
name: furniture-acquisition-intake
description: Use when adding newly acquired furniture inventory, acquisition pickups, sourced-but-not-acquired items, unlisted inventory, refurb-needed items, cost/source/payer details, or preventing fake listing IDs before an item is actually listed.
---

# Furniture Acquisition / Unlisted Inventory Intake

## Default status

- `sourced`: identified, not acquired yet
- `acquired_unlisted`: owned, not listed
- `refurb_needed`: owned, needs repair/cleaning
- `ready_to_list`: ready for photos/listing

Do not assign `item_id` or `cl_url` until actually listed.

## Required fields

For new acquisitions capture:

- title/description
- acquisition date
- cost/acquisition cost
- payer (`paid_by`) and/or `cash_flows` payment row
- seller/source contact if known
- storage location
- condition/refurb needs
- pickup/delivery schedule if known
- whether standalone vs bundle/set/split listing

Default to standalone unless Primary Partner/Operations Partner explicitly identify a bundle/set/parent-child relationship.

## DB actions

Likely inserts/updates:

- `inventory`
- `inventory_status_history`
- `cash_flows` for purchase/COGS/labor if money moved
- `contacts` / `contact_roles` for seller/source/helper
- `pickups_deliveries` for acquisition pickup or storage move

Run guardrails before/after and preview anomalies.
