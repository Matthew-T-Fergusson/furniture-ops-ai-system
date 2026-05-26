---
name: furniture-ops-dashboard-report
description: Generate, refresh, analyze, improve, or package an executive furniture-operations KPI dashboard with operator-written commentary, anomaly/action cues, and Jira/work-item prioritization.
---

# Furniture Ops Dashboard Report

Use this skill for repeatable furniture-operations dashboard/report generation.

## Non-negotiable principle

Do **not** let code generate generic executive prose. Code should gather metrics and render the report. The analysis step must be written from the actual data.

Bad commentary: restating numbers already visible in KPI cards/tables.
Good commentary: trends, implications, risks, operational focus, exceptions, bottlenecks, recent accomplishments, and concrete next actions.

Write as if business operators are reviewing the company. Avoid vague template language, obvious statements, unsupported claims, or generic AI phrasing.

## Standard workflow

1. Refresh analytics materialized views.
2. Generate/update the raw dashboard structure.
3. Export compact dashboard context for analysis. Include the full available furniture-related work-item/Jira universe, not only a small cache.
4. Inspect the context data and write an analysis JSON/file. If a point cannot be supported by the context, omit it or mark it as a hypothesis.
5. Regenerate the dashboard with the analysis injected.
6. Package the HTML/report artifacts.
7. Run quality gates before sharing or publishing.

## Commentary standards

### Executive summary
- Discuss monthly trend and YTD progress, but do **not** compare a single month to YTD as if they are equivalent periods.
- Mention what is improving, what is deteriorating, what changed recently, and what decision deserves attention next.
- Use numbers sparingly to support the point; do not duplicate KPI cards.
- Keep it decision-oriented: what should executives pay attention to, what is the YTD story, and what should change operationally next.

### Operational commentary
- Act like a COO reviewing day-to-day execution.
- Cover what is going well, what is going badly, bottlenecks, recent accomplishments, risks, and near-term operating focus.
- Tie statements to data: aging listings, stale statuses, margins, cash trend, inventory pipeline, and work items.

### Chart / visualization standards
- Category labels must be readable. Do not use raw overlapping category strings directly on charts when they create clutter.
- Normalize/roll up overlapping furniture categories before category charts, e.g. Bedroom Sets, Sofas & Sectionals, Bookcases / Wall Units, Cabinets / Entertainment, Dining, Chairs / Recliners, Patio / Outdoor, Armoires, Desks, Beds, Rugs, Art / Decor, Tables, Other / Misc.
- Use wrapped horizontal labels or another readable approach; avoid tiny diagonal fragments.
- Add hover/rollover tooltips where feasible. Tooltips should expose relevant values for that point/category and be easy to adjust.
- Add supporting summary tables under complex charts so key values remain visible without hovering.

### Profitability section
Must distinguish:
- top item margins,
- worst margins by dollar gross margin,
- worst margins by gross-margin percentage,
- category-level clustered columns for average revenue + average dollar gross margin on the left axis, plus average gross-margin percentage as a right-axis line, for month/YTD selections,
- sold count by category in tooltips and the supporting table.

### Aging inventory section
Must include:
- category-level average days in active inventory vs turnover-rate chart for month/YTD selections,
- average days labeled as current active listing age until historical month-end inventory snapshots exist,
- turnover defined as sold items in the selected period divided by current active listings in the category,
- on-chart count labels showing outstanding/current active count, not sold count,
- both outstanding/current active count and sold count in tooltip/supporting table.

### Anomalies / action cues
- Group similar anomalies instead of listing every raw row.
- Include item IDs and names/descriptions for concrete items.
- Add recommended action for each group: markdown, relist, photo refresh, cross-post, bundle, dispose, status correction, cost/revenue correction, etc.

### Work-item/Jira cues
- Do not show only the first cached rows.
- Use the full available repository/export for furniture-related work: direct project issues plus any issue whose key/summary/description/labels mention furniture, Craigslist/marketplace, listing, inventory, sourcing, storage, compliance, bookkeeping, tax, payment processors, or furniture DB work.
- Deduplicate by issue key, then rank by business impact rather than file order: legal/compliance/banking/bookkeeping, active listing blockers, aging-inventory actions, sourcing/growth engine, data reliability/automation.
- Separate direct operating blockers from background system-maturity work.
- Mention issue keys and why each group matters operationally.

## Quality gate before sharing

- Confirm analysis was injected; no fallback/generic commentary remains.
- Grep the HTML/report for placeholder phrases such as `analysis missing`, `not supplied`, `analysis pending`, or metric-only executive summaries.
- Read the rendered commentary once as a human would. If it sounds templated, rewrite it.
- Confirm `Operational commentary: anomalies, trends, outstanding work` exists if that section is part of the report.
- Confirm anomaly cues are grouped/actionable, not raw row dumps.
- Confirm work-item cues came from the full available furniture-related context.
- Confirm profitability chart shows clustered average revenue + average dollar gross-margin bars and average gross-margin percentage line.
- Confirm aging chart labels outstanding/current active count on-chart and includes sold count in tooltip/table.
- Confirm chart category labels are readable and normalized/rolled up.
- Confirm graph tooltips work where feasible.
- Confirm every major section has meaningful commentary or an intentional reason why commentary is omitted.
