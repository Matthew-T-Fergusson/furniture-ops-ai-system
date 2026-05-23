# Portfolio Case Study

## Problem

A small resale business generated operational data across chat, spreadsheets, receipts, listing platforms, contractors, and calendar events. The data was useful but messy: sales could include deposits, split payments, delivery fees, partner receipts, pending pickups, and unclear status transitions.

## Approach

The system creates a structured operating layer in Postgres and uses AI-agent skills to translate business events into normalized records.

## Highlights

- Status history enables throughput metrics like acquired-to-listed time and stale inventory.
- Cash-flow rows preserve each actual money movement, making split payments auditable.
- Guardrail views prevent agents from silently writing incomplete or contradictory data.
- Skills encode business rules so other agents can review, reuse, and improve the workflow.

## Result

The system turns conversational operations into a database-backed workflow with auditability, reconciliation, and KPI potential.
