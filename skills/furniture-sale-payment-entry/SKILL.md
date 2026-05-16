---
name: furniture-sale-payment-entry
description: Use when logging furniture sale payments, deposits, split payments, refunds, payment methods, paid_to/paid_by, or updating cash_flows for realized revenue and AWF-68 payment tracking.
---

# Furniture Sale / Deposit / Payment Entry

## Source of truth

- Realized revenue lives in `cash_flows` rows where `txn_type='Payment'` and `category='Sale'`.
- Inventory pending/expected prices may exist operationally but do not count as realized revenue until final + delivered/picked up.
- One `cash_flows` row per actual money movement.

## Required fields

For each payment movement ask/capture:

- inventory item (`inventory_uid` / `inventory_id`)
- amount
- date
- `paid_to`: Primary Partner, Operations Partner, business account, or contact
- `payment_method`: `cash`, `venmo`, `zelle`, `cashapp`, `card`, `check`, `other`; leave blank if unsupported/unknown
- `payment_stage`: `deposit`, `partial_payment`, `final_payment`, `refund`, `reimbursement`, `other`
- buyer/contact if known
- notes/source message

For split payments, create separate rows. Example: $200 Venmo deposit + $750 cash final = two `cash_flows` rows.

## Status coupling

- Deposit received -> normally move inventory to `pending_sale` and insert `inventory_status_history`.
- Final payment + delivered/picked up -> move to `sold_delivered`.
- If sale falls through, use status workflow skill.

## Validation

Before/after mutation:

```sql
select * from furniture_db_guardrail_summary;
select inventory_id, sum(amount)
from cash_flows
where txn_type='Payment' and category='Sale'
group by inventory_id;
```

Reconciliation checks should preserve totals when splitting existing rows.

## Conservative historical cleanup

Only backfill `payment_method` when notes explicitly support it. Leave blank when unclear so Primary Partner/Operations Partner can decide later.
