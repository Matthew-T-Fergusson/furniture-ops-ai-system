---
name: expense-receipt-capture
description: Record business expense receipts from chat messages into the shared ledger and DB. Use when Primary Partner or Operations Partner asks to log/record a receipt, especially with an attached image. Saves the image to receipts/business-expenses, appends a row to receipts/index.csv, and upserts the same expense into Postgres cash_flows.
---

# Receipt Ledger Capture

## Workflow

1. Confirm a receipt image is available. If missing, ask for resend.
2. OCR/extract visible fields from the receipt (date, vendor/location, total amount, optional gallons/price/card tail/time, item lines when useful, tax/fees, payment/card tail, auth/transaction IDs).
3. Save the source image into:
   - `receipts/business-expenses/`
4. Append a row to:
   - `receipts/index.csv`
5. Upsert the same row into Postgres:
   - DB: local Postgres `furniture_ops_poc` in container `postgres`
   - Table: `cash_flows`
   - Use receipt `id` as `cash_flows.cf_record_id`
6. Reply in chat with a concise confirmation including ID, date, amount, category, saved file path, and DB status.

## Required fields for ledger row

- `date` (YYYY-MM-DD)
- `vendor`
- `amount`
- `category` (Fuel, Disposal, etc.)
- `purpose`
- `file_path`
- `file_link`
- `notes` (put OCR/extracted receipt details here)

## DB mapping for expense receipts

For each CSV receipt row, create/update one `cash_flows` row:

- `cf_record_id` = receipt `id`
- `txn_type` = `Expense`
- `txn_date` / `txn_date_raw` = receipt date
- `vendor_or_description` = vendor
- `amount` / `amount_raw` = amount
- `currency` = receipt currency, usually `USD`
- `category` = receipt category
- `purpose` = receipt purpose
- `file_path` / `file_link` = receipt source image path/link
- `notes` = same OCR/extracted receipt details used in CSV, including card tail/time/gallons/item lines when visible/useful
- `paid_by` = payer; if Operations Partner submitted/says paid by Operations Partner, use `Operations Partner`
- `paid_to` = vendor/payee when known, otherwise vendor text
- `payment_stage` = `other` unless a more specific allowed value applies (`storage`, `labor`, `inventory_purchase`, etc.)
- `partner_balance_effect` = `expense_paid` for normal business expenses; use `labor_payment`, `no_cash_movement`, or other explicit values only when appropriate
- `source_system` = `expense-receipt-capture`

Before/after DB write, run `select * from furniture_db_guardrail_summary;`. Existing unrelated warnings do not block the receipt insert.

Use a transaction + backup for DB upserts:

```sql
BEGIN;
CREATE TABLE IF NOT EXISTS cash_flows_backup_receipt_<yyyymmdd_hhmm> AS TABLE cash_flows;
-- INSERT ... ON CONFLICT (cf_record_id) DO UPDATE ...
SELECT * FROM furniture_db_guardrail_summary;
COMMIT;
```

Do not only update the CSV. Expense receipts must be represented in both `receipts/index.csv` and `cash_flows` unless the DB is unavailable; if DB insert is blocked/unavailable, say so explicitly and create a follow-up.

Both places must preserve the image reference and OCR details:

- CSV: `file_path`, `file_link`, `notes`
- DB: `file_path`, `file_link`, `notes`

The DB row should be able to stand alone as an audit record without opening the CSV.

## Card-statement line item rule (important)

When parsing multi-line card statement receipts/screenshots:
- Record **debit spend transactions only** (actual expenses).
- **Do not** log credits, refunds, reversals, balance adjustments, payments, or positive entries (e.g., `+$500.00`).
- If uncertain whether a line is spend vs credit, ask one focused clarification before logging.

## Command (preferred)

Use the bundled script:

```bash
python3 skills/expense-receipt-capture/scripts/add_receipt.py \
  --csv receipts/index.csv \
  --source-image "<inbound-image-path>" \
  --date "YYYY-MM-DD" \
  --vendor "<vendor>" \
  --amount "00.00" \
  --category "Fuel" \
  --purpose "<business purpose>" \
  --notes "<details>"
```

The script will:
- generate an ID like `R-YYYY-MM-DD-###`
- copy image into `receipts/business-expenses/`
- append row to `receipts/index.csv`

After the script prints the generated ID, upsert that row into `cash_flows` using the DB mapping above.

## Sender handling in this group

When directly asked by Primary Partner or Operations Partner to record a receipt, prioritize immediate execution.
If Operations Partner sends a receipt, default the purpose/notes to explicitly include `paid by Operations Partner` unless he says otherwise.
If image/data is insufficient, ask one focused follow-up only.

## Output format (chat)

Use this compact confirmation:

- Logged ✅
- ID: <id>
- Date: <date>
- Amount: $<amount>
- Category: <category>
- File: <file_path>
- DB: added to `cash_flows` / blocked with reason

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
