# Data Model

## Key design choices

- `inventory_uid` is the durable item key.
- `inventory_group_id` groups true bundles/sets/lots without forcing every item into parent-child structure.
- Current item state lives on `inventory.status`; history lives in `inventory_status_history`.
- `inventory.sold` remains a strict Y/N boolean supplement to status: `true` only for `sold_delivered`, `false` for every other status.
- Realized revenue is represented by `cash_flows`, not by expected sale prices.
- One cash-flow row equals one actual money movement.
- Payment method is recorded at the cash-flow row level because one sale can have multiple payment methods.
- Expense receipts are stored in both the receipt ledger and `cash_flows`; image path/link and OCR/extracted details are preserved in both places.
- Pickups and deliveries share one table so the same model can drive calendar automation.
- For split sets/relisted remainder pieces, use one cost-bearing economic parent: acquisition COGS stays on the original/full-set listing, and child listings can carry `$0` acquisition COGS with an explicit source/reason.

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

## Cost basis and parent/child policy

Default every row to standalone unless a bundle/set/split relationship is confirmed.

For confirmed split sets or relisted remainder pieces:

- original/full-set listing carries acquisition COGS
- related child/relisted piece rows may carry `$0` acquisition COGS
- child rows must have an explicit `cost_basis_source`, such as `split_child_zero_cogs`, `bundle_child_zero_cogs`, or `parent_absorbed`
- parent asking price/value is not required to equal the sum of child asking prices/values
- guardrails focus on avoiding double-counted COGS, not forcing parent/child price equality

Item-specific post-split repair/refurb costs may be tied to a child item when clearly attributable. Bulk materials are usually treated as supplies/overhead rather than allocated to a single item.

## Partner/accounting attribution

`paid_by` / `paid_to` capture partner/accounting attribution. Literal payer/payee details can be preserved in notes or optional cash-movement fields.

If a business account funds or receives a transaction, default partner economics are 50/50 between the two partners unless explicitly overridden.

## Receipt/audit fields

`cash_flows.file_path`, `cash_flows.file_link`, and `cash_flows.notes` make each DB expense row auditable without opening the CSV ledger. OCR/extracted receipt details should include date, vendor/location, total amount, card tail/payment details, gallons/item lines, authorization/transaction IDs, and useful notes when visible.

## Planned taxonomy enhancement

A future iteration should enforce a strict high-level furniture type for analytics while preserving a flexible secondary subtype for merchandising/search. Example: a high-level category can normalize shelves/bookcases/wall units while a secondary subtype differentiates the exact presentation.
