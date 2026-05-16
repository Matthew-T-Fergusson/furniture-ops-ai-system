# Guardrails

Agents should run guardrail checks before and after mutations.

## Examples of guarded conditions

- Listed or pending inventory without real listing identity
- Pending sale without deposit payment record
- Sold item without sale date
- Sold item without cash-flow sale/payment row
- Zero-cost inventory without cost-basis source
- Multi-item group whose child allocations do not match group total
- Sale/payment rows missing payment method
- Sale/payment rows missing paid-to party

## Principle

When notes do not clearly support a value, leave it blank and flag it for later review instead of fabricating certainty.
