# Furniture Ops AI POC

[![CI Smoke](https://github.com/Matthew-T-Fergusson/furniture-ops-ai-poc/actions/workflows/ci-smoke.yml/badge.svg)](https://github.com/Matthew-T-Fergusson/furniture-ops-ai-poc/actions/workflows/ci-smoke.yml)

A proof-of-concept operating system for a small furniture resale business, built around a Postgres database and AI-agent workflows.

This project demonstrates how messy real-world business activity — chat messages, spreadsheet rows, pickups, deliveries, deposits, split payments, contractors, and marketplace listings — can be normalized into an auditable operating database with guardrails.

## What this shows

- Inventory lifecycle tracking with status history
- Cash-flow records for purchases, deposits, split payments, final payments, refunds, labor, storage, and expenses
- Payment-method tracking at the individual money-movement level
- Receipt/image audit trail for expense OCR, file paths, and extracted transaction details
- Parent/child cost-basis handling for split sets and relisted remainder pieces
- Sold flag/status alignment guardrails
- Unified pickup/delivery scheduling model suitable for calendar automation
- Contact and contractor management
- Listing and price-history tracking, including relist-needed workflow hooks
- Guardrail views that catch risky or incomplete DB writes
- Agent skills that encode repeatable business workflows

## Architecture

![Data model](assets/data_model.png)

See:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md)
- [`docs/WORKFLOWS.md`](docs/WORKFLOWS.md)
- [`docs/GUARDRAILS.md`](docs/GUARDRAILS.md)
- [`docs/PORTFOLIO_CASE_STUDY.md`](docs/PORTFOLIO_CASE_STUDY.md)

## Quick start

```bash
cp .env.example .env
docker compose up -d
```

The SQL files in `sql/` initialize the schema, guardrail views, synthetic sample rows, and dashboard-ready analytics materialized views.

## Analytics and disaster recovery

- `docs/ANALYTICS.md` explains the KPI/dashboard materialized views, including inventory pipeline, margin, listing performance, status aging, transitions, and cycle-time metrics.
- `docs/BACKUP_RECOVERY.md` documents the secure restore model: GitHub for code/runbooks, encrypted backups offsite, and the decryption passphrase stored separately.
- `scripts/create_encrypted_backup.sh` and `scripts/upload_encrypted_backup_to_drive.sh` are public-safe reference scripts. They are heavily commented to show the restore logic without exposing private backup destinations or secrets.

## Tests and CI smoke

Run the same schema/guardrail gate locally and in GitHub Actions:

```bash
make ci-smoke
```

The smoke test resets the local POC database schema, loads `sql/001_schema.sql`,
`sql/002_guardrail_views.sql`, `sql/003_sample_seed.sql`, and
`sql/004_analytics_views.sql`, then fails if the synthetic seed produces any
error-severity guardrails. It also runs
`tests/guardrail_regressions.sql`, which exercises representative guardrail cases
using synthetic rows only:

- listing identity
- pending sale deposit / reserved-until
- sold-delivered completeness
- zero-cost basis
- group cost allocation
- sold/status alignment
- dashboard KPI unsold-count regression
- status-history analytics population

## Privacy note

This repo uses synthetic/anonymized sample data. It intentionally excludes real receipts, contacts, legal documents, addresses, private notes, secrets, and raw operational exports.
