---
name: furniture-status-guardrails
description: Use when updating furniture inventory status, interpreting chat phrases like pending/sold/cancelled/delivered/held/disposed, writing inventory.status or inventory_status_history, or running furniture DB guardrail checks before/after DB changes.
---

# Furniture Status + Guardrails

## Rules

- DB: local Postgres `furniture_ops_poc` in container `postgres`.
- Confirmation threshold:
  - Preview/confirm before money, status, calendar, destructive, or ambiguous partner-accounting changes.
  - Auto-apply low-risk routine metadata cleanup when the source is clear: notes cleanup, contact/listing metadata fixes, non-accounting typo/format corrections.
  - If Primary Partner explicitly says to apply/implement/close, proceed and verify.
- Before and after writes, run `select * from furniture_db_guardrail_summary;`.
- Guardrail severity:
  - **Blocker/error** = do not write until clarified or explicitly overridden. Examples: active listing missing real listing identity, `sold_delivered` without final sale cash-flow, zero COGS without reason/source, duplicate real listing ID/URL, or accounting fields that would double-count revenue/COGS.
  - **Warning** = proceed if the current update is otherwise valid; preserve the warning as a follow-up because data often arrives piecemeal. Examples: pending sale missing deadline, buyer contact, pickup/delivery details, calendar event, payment method, or balance note.
  - Warnings should not block unrelated updates.
- When new pending-sale/payment/scheduling edge cases appear, note them and update this skill/guardrails so the workflow improves.
- Status changes must update:
  - `inventory.status`, `status_updated_at`
  - `inventory.sold` as a strict Y/N boolean supplement: `true` only for `sold_delivered`, `false` for every other status
  - `inventory_status_history`

## Current statuses

Allowed `inventory.status` values and meanings:

- `sourced`: identified lead/opportunity, not yet acquired.
- `acquired_unlisted`: owned/acquired but not ready to list yet; may need cleaning, repair, photos, pricing, split/quantity modeling, or other prep. Do not require real listing IDs/URLs.
- `refurb_needed`: owned and explicitly needs repair/refurb before listing.
- `ready_to_list`: prep/photos are complete enough to list; no live marketplace listing yet. Listing work should create/update a Jira/listing task as needed.
- `listed_active`: live marketplace listing exists; must have real listing identity/URL unless explicitly non-marketplace.
- `pending_sale`: deposit/reservation/sold-but-not-complete; use `pending_at`, `reserved_until`, sale cash-flow rows, and `pickups_deliveries` for details.
- `sold_delivered`: final payment plus pickup/delivery completion.
- `disposed`: non-sale disposition/dump/donation/loss.
- `hold`: blocked, not currently for sale, expired listing needing relist decision, owner decision needed, or otherwise paused.
- `relist_needed` / relist status tracking: if the DB enum does not yet support a dedicated `relist_needed` inventory status, use `hold` plus listing status/relist Jira ticket. Primary Partner wants expired/inactive listings to surface as relist action items even when the item is cross-listed elsewhere.

Cancelled/returned/no-show is usually not a long-lived status. Record it as a transition reason, usually:

- `pending_sale -> listed_active`
- `pending_sale -> ready_to_list`
- `pending_sale -> hold`

## Required questions by chat phrase

If someone says **pending / deposit received**:

1. Has a deposit been received?
2. Deposit amount?
3. Payment method?
4. Who received the deposit / partner credit: Primary Partner, Operations Partner, or business account?
5. Agreed item price?
6. Delivery fee, if any?
7. Total owed = price + delivery fee?
8. Balance owed = total owed - deposit?
9. Buyer name/contact?
10. Pickup/delivery date, target time, address/location, and storage/origin?

Once a deposit exists and Primary Partner confirms the preview, move to `pending_sale`, set `inventory.pending_at`, set `inventory.reserved_until` if a buyer deadline/hold expiration is known, create the deposit cash-flow row, and update notes with price + delivery fee = total owed; total owed - deposit = balance owed; who received deposit; payment method if known; linked cash-flow ID.

If no deposit, keep `listed_active` and record as lead/follow-up if needed.

If someone says **sold**:

1. Fully paid and delivered/picked up?
2. Final payment amount/method/paid_to?
3. Buyer/contact?
4. Delivery/pickup completed date/time?

Only move to `sold_delivered` when sale is final + delivered/picked up + cash-flow sale/payment row exists. Pending expected revenue must not count as realized revenue. When moving to `sold_delivered`, set `inventory.sold=true`; when moving out of `sold_delivered`, set `inventory.sold=false`.

If someone says **cancelled / fell through / no-show**:

1. Was there a deposit? Refunded or kept/forfeited?
2. Is the listing still active?
3. Was listing taken down, expired, or unknown?
4. Are related delivery/pickup/calendar events cancelled?

If buyer backs out and forfeits deposit, keep the deposit cash-flow row and note forfeiture. If listing is still active, move item back to `listed_active`. If listing is inactive/expired/delisted/unknown, move/keep item on `hold`, remind Primary Partner/Operations Partner to relist, and create a Jira relist ticket.

Forfeited deposit accounting: rare/materiality usually low. Prefer separate sale-adjacent income classification (`forfeited_deposit`) rather than normal final sale revenue when feasible; preserve the original deposit row and note that the item returned to market.

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

## Notes policy

Legacy inventory/cash-flow notes may contain rough startup flags about who paid, who collected cash, or who should get credit. Do not treat old note prose as more authoritative than current structured fields. Preserve useful historical note context, but prefer adding a clear current-state note over deleting old evidence.

Historical convention for older notes: when a note has a slash, text before the slash often identifies the purchaser/payer from the inventory table, while text after the slash identifies who received the sale funds for partner tracking. Example: `paid by Operations Partner / Primary Partner received $1100`. Do not read the pre-slash person as the buyer on sale transactions.

If a note could change accounting interpretation, flag it for review and compare against `cash_flows.paid_by`, `cash_flows.paid_to`, `payment_method`, `payment_stage`, and `partner_balance_effect`.

## Do not

- Do not infer sold from expected revenue alone.
- Do not treat `inventory.sold` as a replacement for `inventory.status`; it is only a Y/N supplement that must align with status.
- Do not create realized revenue without a cash-flow row.
- Do not delete history rows; add corrective transition events.
- Do not rewrite accounting based only on ambiguous note phrases like "paid by Operations Partner" or "Primary Partner paid".

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
