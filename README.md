# Furniture Ops AI POC

A proof-of-concept operating system for a small furniture resale business, built around a Postgres database and AI-agent workflows.

This project demonstrates how messy real-world business activity — chat messages, spreadsheet rows, pickups, deliveries, deposits, split payments, contractors, and marketplace listings — can be normalized into an auditable operating database with guardrails.

## What this shows

- Inventory lifecycle tracking with status history
- Cash-flow records for purchases, deposits, split payments, final payments, refunds, labor, storage, and expenses
- Payment-method tracking at the individual money-movement level
- Unified pickup/delivery scheduling model suitable for calendar automation
- Contact and contractor management
- Listing and price-history tracking
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

The SQL files in `sql/` initialize the schema, guardrail views, and synthetic sample rows.

## Privacy note

This repo uses synthetic/anonymized sample data. It intentionally excludes real receipts, contacts, legal documents, addresses, private notes, secrets, and raw operational exports.
