---
name: furniture-listing-price-sync
description: Use when adding/updating marketplace/Facebook/marketplace listings, item_id/cl_url, listing status, asking price, markdowns, delisting, or listing_price_history for furniture inventory.
---

# Furniture Listing + Price History Sync

## Listing identity

Only set `inventory.item_id` / `inventory.cl_url` when actually listed. Never borrow marketplace IDs for acquired-unlisted inventory.

Use:

- `listings` for marketplace listing metadata
- `listing_price_history` for every initial price or markdown
- `inventory.status='listed_active'` when live

## Required fields

- `inventory_uid`
- platform: marketplace, facebook, etc.
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

## marketplace pacing

For marketplace-related searches/syncs, use slow randomized pacing to reduce blocking/rate limits.

## Validation

Check for duplicate real external listing IDs/URLs before writes. Placeholder IDs like N/A/TBD should not be treated as real listing IDs.
