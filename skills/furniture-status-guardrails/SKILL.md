---
name: furniture-status-guardrails
description: Use when updating furniture inventory status, interpreting chat phrases like pending/sold/cancelled/delivered/held/disposed, writing inventory.status or inventory_status_history, or running furniture DB guardrail checks before/after DB changes.
---

# Furniture Status + Guardrails

## Rules

- DB: local Postgres `furniture_ops_poc` in container `postgres`.
- Preview-first for DB mutations unless Primary Partner explicitly says to apply.
- Before and after writes, run `select * from furniture_db_guardrail_summary;`.
- Status changes must update both:
  - `inventory.status`, `status_updated_at`
  - `inventory_status_history`

## Current statuses

Allowed `inventory.status` values:

- `sourced`
- `acquired_unlisted`
- `refurb_needed`
- `ready_to_list`
- `listed_active`
- `pending_sale`
- `sold_delivered`
- `disposed`
- `hold`

Cancelled/returned/no-show is usually not a long-lived status. Record it as a transition reason, usually:

- `pending_sale -> listed_active`
- `pending_sale -> ready_to_list`
- `pending_sale -> hold`

## Required questions by chat phrase

If someone says **pending**:

1. Has a deposit been received?
2. Amount?
3. Payment method?
4. Paid to Primary Partner, Operations Partner, or business account?
5. Buyer name/contact?
6. Pickup/delivery date, time window, and location?

Only move to `pending_sale` once a deposit exists. If no deposit, keep `listed_active` and record as lead/follow-up if needed.

If someone says **sold**:

1. Fully paid and delivered/picked up?
2. Final payment amount/method/paid_to?
3. Buyer/contact?
4. Delivery/pickup completed date/time?

Only move to `sold_delivered` when sale is final + delivered/picked up + cash-flow sale/payment row exists. Pending expected revenue must not count as realized revenue.

If someone says **cancelled / fell through / no-show**:

1. Was there a deposit? Refunded or kept?
2. Should item go back to `listed_active`, `ready_to_list`, or `hold`?
3. Was listing taken down?

## SQL pattern

Use transaction + backup for mutations:

```sql
BEGIN;
CREATE TABLE IF NOT EXISTS inventory_backup_<reason>_<yyyymmdd_hhmm> AS TABLE inventory;
CREATE TABLE IF NOT EXISTS inventory_status_history_backup_<reason>_<yyyymmdd_hhmm> AS TABLE inventory_status_history;
-- update inventory
-- insert inventory_status_history
SELECT * FROM furniture_db_guardrail_summary;
COMMIT;
```

## Do not

- Do not infer sold from expected revenue alone.
- Do not create realized revenue without a cash-flow row.
- Do not delete history rows; add corrective transition events.
