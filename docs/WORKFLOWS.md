# Workflows

## Acquisition intake

When an item is acquired, capture acquisition date, source, cost, payer, storage location, condition, and whether it is standalone or a true bundle/set. Do not assign marketplace listing IDs until the item is actually listed.

## Listing workflow

When a marketplace listing goes live, create/update `listings`, write the initial asking price to `listing_price_history`, and move the item to `listed_active`.

## Pending sale workflow

When someone says an item is pending, ask whether a deposit has been received. An item should enter `pending_sale` once a deposit exists. Capture buyer/contact, deposit amount, payment method, paid-to party, delivery/pickup timeline, and scheduled movement details.

## Sold workflow

Move an item to `sold_delivered` only when final payment is recorded and the item is delivered or picked up. Realized revenue is based on `cash_flows` sale/payment rows.

## Split payment workflow

If a buyer pays with multiple methods or to multiple recipients, create multiple cash-flow rows. Example: deposit by Venmo and final cash payment are two records.

## Scheduling workflow

Use `pickups_deliveries` for acquisition pickups, buyer pickups, seller deliveries, contractor deliveries, storage transfers, returns, and reschedules. Calendar integrations can write back `calendar_event_id`.
