---
name: furniture-contact-maintenance
description: Use when importing or maintaining furniture contacts, Contact List Google Sheet sync, contact_roles, buyer/seller/contractor/vendor/partner records, contractor ratings, or contact dedupe.
---

# Furniture Contact Maintenance

## Tables

- `contacts`
- `contact_roles`
- `contractor_ratings`

Role values:

- `buyer`
- `seller`
- `source`
- `contractor`
- `delivery_helper`
- `partner`
- `payer`
- `payee`
- `marketplace_lead`
- `vendor`
- `other`

## Import source

Google Sheet: `Furniture Ops Workbook` -> `Contact List`.

Current sheet seed import added contacts from the tab plus Primary Partner and Operations Partner.

## Dedupe

Prefer matching by:

- lower(display_name)
- phone when present
- email when present

Do not overwrite existing notes/ratings without preview.

## Conservative cleanup

If a phone number appears in an email column, import as phone and note the correction. Leave ambiguous values alone.

## Ratings

Contractor ratings are interaction/job based where possible, optionally tied to `pickups_deliveries.movement_id`.
