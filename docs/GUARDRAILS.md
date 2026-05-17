# Guardrails

Agents should run guardrail checks before and after mutations.

## Severity model

- **Blocker/error**: stop before writing unless the user explicitly overrides. The write would likely create materially wrong data.
- **Warning**: proceed if the current update is otherwise valid, and leave a follow-up. Operational data often arrives piecemeal.

Warnings should not block unrelated updates.

## Examples of blockers/errors

- Listed or pending inventory without real listing identity
- `inventory.sold` not aligned with `inventory.status`
- Sold item without sale date/timestamp
- Sold item without cash-flow sale/payment row
- Zero-cost inventory without cost-basis source/reason
- Duplicate real external listing ID or URL
- Parent/child cost treatment that would double-count acquisition COGS
- Ambiguous money recipient/source where the write would change partner accounting

## Examples of warnings

- Pending sale missing hold deadline / reserved-until date
- Pending sale missing buyer contact, pickup/delivery details, or calendar event
- Pending sale missing balance note
- Sale/payment row missing payment method when historical notes do not clearly support one
- Expense receipt missing optional OCR fields when amount/vendor/date/payer are clear

## Current guarded conditions

- Active/pending listing identity completeness
- Sold flag/status alignment
- Pending sale deposit evidence
- Pending-sale reserved-until reminder
- Pending-sale pickup/delivery/calendar reminders
- Sold-delivered sale date and sale cash-flow evidence
- Zero-cost inventory cost-basis source
- Group allocated-cost mismatch, excluding parent-absorbed / child-zero-COGS groups
- Sale/payment missing payment method
- Sale/payment missing paid-to party

## Principle

When notes do not clearly support a value, leave it blank and flag it for later review instead of fabricating certainty. Prefer explicit source/reason fields over silent assumptions.
