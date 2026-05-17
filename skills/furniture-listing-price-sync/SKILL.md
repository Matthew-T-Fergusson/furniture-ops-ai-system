---
name: furniture-listing-price-sync
description: Use when adding/updating marketplace/secondary marketplace/marketplace listings, item_id/cl_url, listing status, asking price, markdowns, delisting, or listing_price_history for furniture inventory.
---

# Furniture Listing + Price History Sync

## Listing identity

Only set `inventory.item_id` / `inventory.cl_url` when actually listed. Never borrow marketplace IDs for acquired-unlisted inventory.

Use:

- `listings` for marketplace listing metadata
- `listing_price_history` for every initial price or markdown
- `inventory.status='ready_to_list'` when prep/photos are done but no live listing exists
- `inventory.status='listed_active'` when a live marketplace listing exists
- `inventory.status='hold'` when listing is expired/inactive and relist/follow-up is needed

## Required fields

- `inventory_uid`
- platform: marketplace, secondary marketplace, etc.
- external listing ID
- listing URL
- title
- current asking price
- listed_at
- listing status: `draft`, `active`, `paused`, `pending`, `sold`, `delisted`, `cancelled`

## Price changes

Every asking-price change gets a new `listing_price_history` row with:

- listing_id
- price
- changed_at
- reason/source

## Listing expiry / relist workflow

If an active listing expires or is found inactive when an item needs to go back for sale, automatically create a Jira ticket to relist/refresh the item and link/cross-reference the inventory/listing record. Do this even if the item is listed on other platforms; Primary Partner wants the inventory/listing status to surface a relist action when any marketplace listing needs attention.

Relist status convention: if the DB enum does not support a dedicated `relist_needed` inventory status yet, set/keep inventory on `hold` and record relist need in `listing_status`, notes, and the Jira ticket.

If buyer backs out after deposit:

- check whether listing is still active
- if active: inventory can return to `listed_active`
- if inactive/expired/delisted/unknown: set/keep item on `hold`, remind Primary Partner/Operations Partner to relist, and create a Jira relist ticket

## marketplace pacing

For marketplace-related searches/syncs, use slow randomized pacing to reduce blocking/rate limits.

## Validation

Check for duplicate real external listing IDs/URLs before writes. Placeholder IDs like N/A/TBD should not be treated as real listing IDs.

Duplicate real listing IDs/URLs are blockers. Expired/inactive listing details are warnings/action triggers unless the requested update depends on them.
