# Roadmap

This roadmap tracks the public-safe portfolio version of the Furniture Ops AI System. Private/live deployments may include additional operational integrations, credentials, customer details, or partner-specific finance data that are intentionally excluded here.

## Current maturity focus — v3 critique follow-up

A May 2026 maturity review moved the project from “schema/guardrail POC” toward a stronger AI-assisted operations system. The SQL/data-model layer is now the strongest part of the work; the next credibility gap is the application/governance layer around it.

Highest-leverage next steps:

1. **Code-enforced audit trail**
   - Every deterministic helper should write an `agent_action_log` row in the same transaction as the operation.
   - Logging should cover success, failure, preview-only, and blocked-by-guardrail outcomes.
   - The system should not depend on an agent remembering to log after the fact.

2. **Python quality gates**
   - Add `ruff`, `mypy`, and `pytest` for dashboard/context-export/helper code.
   - Cover pure functions first: numeric coercion, money/percent formatting, HTML escaping, table rendering, context shaping, and analysis-file handling.
   - CI should fail if dashboard code regresses even when SQL/materialized-view tests pass.

3. **Analytics refresh orchestration**
   - Add a refresh script for materialized views in dependency order.
   - Record/report freshness so dashboards can warn when views are stale.
   - Dashboard output should show view age, not just generated-at time.

4. **Tamper-evident / append-only audit log**
   - Add an UPDATE/DELETE prevention trigger for `agent_action_log`.
   - Consider a hash chain (`prev_row_hash`, `row_hash`) for stronger tamper evidence.

5. **Agent observability**
   - Extend audit rows with model/skill/cost/latency metadata.
   - Add `analytics_agent_performance_*` views for action volume, error rate, guardrail-block rate, correction rate, preview-to-commit ratio, and cost trend.

6. **Guardrail maturity**
   - Classify guardrails as hard blockers vs review-only warnings.
   - Promote true invariants to constraints/triggers where feasible.
   - Keep judgment-call anomalies as detective views.

7. **Portfolio polish and drift prevention**
   - Maintain a CHANGELOG/ADR trail.
   - Generate `SCHEMA_REFERENCE.md` from live schema comments/types/FKs.
   - Keep the public demo dashboard synthetic but representative of the private dashboard workflow.

## Carried-forward product roadmap

- Add deterministic helper scripts for common workflow mutations: movement scheduling, listing updates, status transitions, sale payments, and receipt capture.
- Add pytest/dbt-style validation tests around guardrail views.
- Add synthetic scenario fixtures for acquisition, pending sale, split payment, cancellation, delivery completion, stale listings, messy contacts, and ambiguous bundles.
- Expand dashboard queries for throughput, stale inventory, gross margin, delivery-fee economics, contractor reliability, and agent-performance analytics.
- Enforce a strict high-level furniture type taxonomy plus flexible secondary subtype.
- Add expired-listing detector that creates relist tasks automatically.
- Add media/listing-photo and storage-unit tables for richer inventory operations.
- Add backup/restore and migration tooling suitable for a small production deployment.

## Later phases

### Phase 2 — production single shop

- RBAC / row-level security for helpers, partners, and finance-sensitive data.
- Operations metrics log and per-skill service-level objectives.
- Data quarantine pattern for low-confidence imports.
- Compliance views for sales tax, 1099/vendor review, and partner/tax-prep support.
- Deterministic helper suite with code-enforced audit logging from day one.

### Phase 3 — multi-location / multi-channel

- Warehouse/location management.
- Marketplace integrations with fee tracking.
- Customer-facing catalog and self-scheduling.
- Contractor/vendor portal.
- Pricing intelligence from comparable sales.
- Accounting export.

### Phase 4 — platform / scale decision

Choose between deeper vertical tooling for the furniture operation — ML pricing, computer-vision intake, predictive sourcing — and a broader multi-tenant platform path with tenant isolation, billing, and SOC 2-style controls. Defer this decision until Phase 3 is consolidated.
