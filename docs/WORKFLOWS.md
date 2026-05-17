# Workflows

## Acquisition intake

When an item is acquired, capture acquisition date, source, cost, payer, storage location, condition, and whether it is standalone or a true bundle/set. Do not assign marketplace listing IDs until the item is actually listed.

If paid from a business account, treat partner economics as 50/50 unless explicitly overridden.

## Listing workflow

When a marketplace listing goes live, create/update `listings`, write the initial asking price to `listing_price_history`, and move the item to `listed_active`.

If an active listing expires or is found inactive while the item still needs to be sold, create a relist task and surface the item as needing relist action even if it is cross-listed elsewhere. If the schema does not yet have a dedicated `relist_needed` status, use `hold` plus listing-status/notes/task metadata.

## Pending sale workflow

When someone says an item is pending, ask whether a deposit has been received. An item should enter `pending_sale` once a deposit or firm reservation exists. Capture buyer/contact, deposit amount, payment method, paid-to party, item price, delivery fee, balance owed, delivery/pickup timeline, and scheduled movement details as they arrive.

Missing contact/scheduling details are usually warnings, not blockers, if the deposit/status facts are clear.

## Sold workflow

Move an item to `sold_delivered` only when final payment is recorded and the item is delivered or picked up. Realized revenue is based on `cash_flows` sale/payment rows.

When moving to `sold_delivered`, set `inventory.sold=true`. When moving out of `sold_delivered`, set `inventory.sold=false`.

## Split payment workflow

If a buyer pays with multiple methods or to multiple recipients, create multiple cash-flow rows. Example: deposit by app payment and final cash payment are two records.

Delivery fees should be captured separately from item price when known so item margin and delivery economics can be reported independently.

Forfeited deposits are rare but should be classified separately from normal final sale revenue when feasible.

## Expense receipt workflow

Every expense receipt should be captured in both places:

1. receipt ledger CSV
2. Postgres `cash_flows`

Save the source image, OCR/extract the transaction details, and preserve image path/link plus extracted details in both the CSV and DB row.

A DB receipt row should be auditable on its own without opening the CSV.

## Repair/refurb workflow

Item-specific hired repair/refurb labor should be captured as a cash-flow row tied to the item when known. Bulk materials/supplies are usually overhead because they are used across future repairs; only allocate materials to one item when clearly item-specific.

## Scheduling workflow

Use `pickups_deliveries` for acquisition pickups, buyer pickups, seller deliveries, contractor deliveries, storage transfers, returns, and reschedules. Calendar integrations can write back `calendar_event_id`.

For confirmed pickup/delivery details, preview calendar metadata before creation unless the operator explicitly allows automation.

## Contact workflow

Exact phone/email matches are likely duplicates. High-probability fuzzy name matches without phone/email should be flagged for human review rather than merged automatically.
