# Cash-Flow Tax / Reporting Taxonomy

This repository separates operational cash-flow categories from tax/reporting categories.

## Why this exists

Furniture resale transactions serve multiple purposes at once:

- operational tracking: what happened in the business?
- partner accounting: who paid, who received money, and who gets credit?
- margin analysis: what was revenue, COGS, labor, storage, or overhead?
- tax readiness: which rows need review before year-end reporting?

A free-form `cash_flows.category` field is useful for operations but too loose for tax-aware dashboards. `tax_categories` and `cash_flows.tax_category_code` provide a reusable reporting layer for resale and similar inventory-driven small businesses.

This is **not tax advice**. The taxonomy is a public-safe reporting structure that should be reviewed against the business's actual accounting/tax requirements.

## Design

- `cash_flows.category` remains the operational category, such as `COGS - Inventory`, `Sale`, or `Storage`.
- `cash_flows.tax_category_code` stores the normalized tax/reporting category.
- `tax_categories.category_kind` identifies whether the category is `expense`, `revenue`, `contra_revenue`, `non_tax`, or `review`.
- `tax_categories.default_deductible` gives a dashboard default for deductible expense totals.
- `cash_flows.deductible_override` can override the category default when a row has reviewed special treatment.
- `cash_flows.tax_treatment_notes` stores a short explanation or why review is needed.

## Expense categories

Examples include:

- `inventory_cogs`
- `labor_contract`
- `storage`
- `vehicle_fuel`
- `vehicle_mileage`
- `supplies`
- `marketplace_fees`
- `advertising`
- `professional_services`
- `software`
- `insurance`
- `taxes_licenses`
- `meals`
- `bank_fees`
- `other_expense`
- `not_deductible`
- `unknown_needs_review`

## Revenue categories

Revenue rows should also be categorized so dashboards do not show blank or ambiguous income treatment.

Examples include:

- `gross_sales_revenue`
- `delivery_revenue`
- `forfeited_deposit_revenue`
- `refund_or_reversal`
- `owner_contribution`
- `unknown_needs_review`

## Guardrail behavior

Missing or review-needed tax categories are **warnings, not blockers**. There is gray area in tax classification, and operational work should not stop merely because a row needs later accounting review.

Current warnings:

- expense older than 30 days with null or `unknown_needs_review` tax category
- sale/delivery revenue row with null or `unknown_needs_review` tax category
- expense row using revenue category, or revenue row using expense category

## Dashboarding

`analytics_cash_flow_tax_category_period_mv` rolls cash flows up by week/month, tax category, category kind, and Schedule C-style reporting hint. It supports dashboards that combine operational performance with tax-aware expense/revenue review.

Useful dashboard cards/tables:

- deductible expense total by month
- revenue by category
- rows needing tax review
- marketplace/storage/labor/supply expense trend
- gross sales vs COGS vs deductible overhead

## Public repo privacy boundary

Do not add real accountant guidance, actual tax filings, private vendor details, customer records, personal tax strategy, or legal/tax conclusions to this public repository. Keep examples synthetic and broadly reusable.
