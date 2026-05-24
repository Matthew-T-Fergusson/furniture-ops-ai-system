---
name: furniture-sale-payment-entry
description: Use when logging furniture sale payments, deposits, split payments, refunds, payment methods, paid_to/paid_by, or updating cash_flows for realized revenue and payment-method payment tracking.
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
- `paid_by`: buyer / payment source for the sale; default to `Buyer` if unknown, or use the buyer name from pickup/delivery/contact records when known
- `paid_to`: partner/accounting attribution recipient for balance/investment tracking; usually `Primary Partner`, `Operations Partner`, or `Business Account`
- `partner_balance_effect`: usually `sale_proceeds_credit` for sale proceeds
- `tax_category_code`: classify revenue as `gross_sales_revenue`, `delivery_revenue`, `forfeited_deposit_revenue`, `refund_or_reversal`, or `unknown_needs_review` so reporting/dashboard rows are not blank
- `tax_treatment_notes`: short reason for the revenue classification or why review is needed
- `payment_method`: `cash`, `venmo`, `zelle`, `cashapp`, `card`, `check`, `other`; leave blank if unsupported/unknown
- `payment_stage`: `deposit`, `partial_payment`, `final_payment`, `refund`, `reimbursement`, `other`
- buyer/contact if known
- notes/source message

For sales, do not default `paid_by` to Primary Partner/Operations Partner just because they received the money. `paid_by` should be the buyer/source; if the buyer name is unknown, use `Buyer`. Use notes/contact links when needed to preserve who physically received cash.

Partner/accounting attribution:

- `paid_to` for sale proceeds is the partner/account receiving accounting credit: `Primary Partner`, `Operations Partner`, or `Business Account`.
- If sale proceeds or purchase funding go through `Business Account`, treat partner economics as 50/50 funded/credited unless Primary Partner says otherwise; Primary Partner/Operations Partner fields exist for internal cost accounting/equalization, not necessarily literal cash movement.
- Use `cash_paid_by` / `cash_paid_to` when available for literal payer/payee/handler details.

For split payments, create separate rows. Example: $200 Venmo deposit + $750 cash final = two `cash_flows` rows.

Delivery fees:

- Capture delivery fee separately from item price whenever known.
- Prefer separate cash-flow/category treatment such as `Delivery Revenue` / delivery-fee line with `tax_category_code='delivery_revenue'` so KPI reporting can distinguish item margin from delivery economics.
- If the current source bundles item price + delivery fee for simplicity, preserve total and add a note/split fields when known.

Forfeited deposits:

- Rare and usually immaterial, but classify separately when feasible (`forfeited_deposit_revenue` / sale-adjacent income) rather than ordinary final sale revenue.
- Preserve original deposit row; add notes/status history explaining refund vs forfeiture and whether the item returned to market.

Tax/reporting categorization is a dashboard/review aid, not tax advice. If revenue treatment is ambiguous, use `unknown_needs_review`; that should surface a warning, not block an otherwise valid operational record.

## Confirmation before writes

Before changing the DB, preview the intended rows/field updates in chat and ask for confirmation unless Primary Partner explicitly says no confirmation is needed for that case.

If transaction info is incomplete, ask for the missing fields before mutation.

## Deposit / pending-sale workflow

Deposit received means:

- move inventory to `pending_sale`
- set `inventory.pending_at` when entering pending status if not already populated
- set `inventory.reserved_until` when a deposit/hold deadline is known
- create one `cash_flows` row for the deposit
- update notes with:
  - item price + delivery fee = total owed
  - total owed - deposit = balance owed by customer
  - who received the deposit
  - payment method, if known
  - linked cash-flow record ID

Required deposit fields:

- agreed item price
- delivery fee, if any
- deposit amount
- balance owed
- who received deposit / partner credit
- payment method if known
- buyer/customer name/contact if known

Missing deposit details are usually warnings, not blockers, when Primary Partner/Operations Partner are giving data piecemeal. Block only if the write would create wrong money/accounting semantics: unclear amount, unclear receiving partner/account, duplicate payment, or impossible status transition.

## Status coupling

- Deposit received -> move inventory to `pending_sale` and insert status history after confirmation.
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

## Notes policy

Legacy notes may contain startup shorthand like "paid by Operations Partner", "Primary Partner paid", or "Operations Partner received". Treat those as historical flags/evidence, not as authoritative accounting fields when they conflict with structured columns.

Important historical convention: in older transaction notes, wording around a slash often means **before the slash = purchaser / payer from the inventory table**, and **after the slash = who received the sale funds** for partner tracking. Example pattern: `paid by Operations Partner / Primary Partner received $1100`. Do not read the pre-slash person as the buyer on sale transactions; use it as historical context explaining why the row was entered that way.

Going forward:

- Keep useful historical note context; do not erase it just because it is messy.
- Put current accounting interpretation in structured fields: `paid_by`, `paid_to`, `payment_method`, `payment_stage`, `partner_balance_effect`.
- If editing notes, append/clarify with `Current structured interpretation: ...` rather than deleting old evidence.
- Do not infer `payment_method` from "paid by" or "received" wording.
- If note wording conflicts with structured fields, flag it for review instead of silently changing accounting.

## Conservative historical cleanup

Only backfill `payment_method` when notes explicitly support it. Leave blank when unclear so Primary Partner/Operations Partner can decide later.

## Agent action audit trail

For any AI-assisted workflow that previews, writes, blocks, or fails, create an `agent_action_log` entry or equivalent implementation note with:

- `skill_name` matching this skill
- capped/sanitized `chat_input_excerpt`
- `operation_summary` with enough detail to replicate the action
- summarized `guardrails_before` and `guardrails_after`
- affected `entity_type` / `entity_id`
- status: `preview_only`, `success`, `failed`, `blocked_by_guardrail`, or `needs_human_review`
- `human_feedback` when Matt, a reviewer, or a collaborator corrects behavior

Public examples must stay synthetic. Do not include real private chat text, receipts, customer/contact data, credentials, addresses, phone numbers, or raw production SQL payloads in the published repository.
