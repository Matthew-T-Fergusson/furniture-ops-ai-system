# Data Model

## Key design choices

- `inventory_uid` is the durable item key.
- `inventory_group_id` groups true bundles/sets/lots without forcing every item into parent-child structure.
- Current item state lives on `inventory.status`; history lives in `inventory_status_history`.
- Realized revenue is represented by `cash_flows`, not by expected sale prices.
- One cash-flow row equals one actual money movement.
- Payment method is recorded at the cash-flow row level because one sale can have multiple payment methods.
- Pickups and deliveries share one table so the same model can drive calendar automation.

## Main tables

- `inventory_groups`
- `inventory`
- `inventory_status_history`
- `cash_flows`
- `contacts`
- `contact_roles`
- `listings`
- `listing_price_history`
- `pickups_deliveries`
- `contractor_ratings`

## Statuses

Allowed inventory statuses:

- `sourced`
- `acquired_unlisted`
- `refurb_needed`
- `ready_to_list`
- `listed_active`
- `pending_sale`
- `sold_delivered`
- `disposed`
- `hold`

Cancelled/no-show events are usually transitions, not permanent statuses: for example `pending_sale -> listed_active` with reason `buyer_no_show`.
