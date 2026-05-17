---
name: furniture-acquisition-intake
description: Use when adding newly acquired furniture inventory, acquisition pickups, sourced-but-not-acquired items, unlisted inventory, refurb-needed items, cost/source/payer details, or preventing fake listing IDs before an item is actually listed.
---

# Furniture Acquisition / Unlisted Inventory Intake

## Default status

- `sourced`: identified lead/opportunity, not acquired yet.
- `acquired_unlisted`: owned/acquired but not listing-ready yet; may need cleaning, repair, photos, pricing, split/quantity modeling, or other prep.
- `refurb_needed`: owned and explicitly needs repair/refurb before listing.
- `ready_to_list`: prep/photos are complete enough to list; no live marketplace listing yet.
- `listed_active`: live marketplace listing exists.
- `hold`: blocked, paused, expired listing needing relist decision, owner decision needed, or not currently for sale.

Do not assign `item_id` or `cl_url` until actually listed. Placeholder values like `TBD`, `N/A`, blanks, or borrowed/old marketplace IDs should not count as real listing identity.

## Required fields

For new acquisitions capture:

- title/description
- acquisition date
- cost/acquisition cost
- payer/investment source (`paid_by`) and/or `cash_flows` payment row. If paid from `Business Account`, treat it as 50/50 Primary Partner/Operations Partner funded for partner economics unless Primary Partner says otherwise.
- seller/source contact if known; for inventory purchases, default `paid_to` to the seller/source when known, otherwise use `Seller`
- storage location
- condition/refurb needs
- pickup/delivery schedule if known
- whether standalone vs bundle/set/split listing

Default to standalone unless Primary Partner/Operations Partner explicitly identify a bundle/set/parent-child relationship.

Repairs/refurb:

- Item-specific hired repair/refurb labor should be captured in `cash_flows` and tied to the item when known.
- Bulk materials/supplies usually should not be allocated to a single item because they are used across future repairs; treat as supplies/overhead unless Primary Partner explicitly allocates them.
- Item-specific materials can be item COGS only when clearly purchased for that item.

## DB actions

Likely inserts/updates:

- `inventory`
- `inventory_status_history`
- `cash_flows` for purchase/COGS/labor if money moved; inventory purchase defaults: `paid_by` = Primary Partner/Operations Partner/Business funding source, `paid_to` = seller/source (`Seller` if unknown), `payment_stage` = `inventory_purchase`
- `contacts` / `contact_roles` for seller/source/helper
- `pickups_deliveries` for acquisition pickup or storage move

Run guardrails before/after and preview anomalies.
