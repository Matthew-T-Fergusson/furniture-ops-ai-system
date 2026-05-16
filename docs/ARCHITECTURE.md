# Architecture

The POC uses Postgres as the source of truth for operations and agent workflows as the structured intake layer.

## Core components

1. **Inventory** — one row per specific sellable or trackable item.
2. **Inventory groups** — optional rollup layer for true bundles, sets, split listings, or lots.
3. **Status history** — append-only lifecycle events for throughput metrics.
4. **Cash flows** — one row per money movement.
5. **Listings + price history** — marketplace state and markdown tracking.
6. **Pickups/deliveries** — unified scheduling table for acquisition pickups, buyer pickups, deliveries, storage transfers, and returns.
7. **Contacts + roles** — buyers, sellers, contractors, vendors, partners, payers, payees.
8. **Guardrail views** — anomaly checks agents run before and after writes.
9. **Agent skills** — workflow memory that tells agents how to safely translate chat/business events into database changes.

## Human-in-the-loop design

The system is intentionally preview-first for ambiguous or external actions. Agents prepare proposed rows and anomaly checks, then ask for confirmation when needed.
