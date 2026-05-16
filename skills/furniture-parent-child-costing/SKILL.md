---
name: furniture-parent-child-costing
description: Use when deciding or updating furniture parent/child inventory groups, split listings, bundles, sets, lots, cost allocation, cost_basis_source, parent_inventory_uid, or preventing double-counted cost basis.
---

# Furniture Parent / Child + Cost Allocation

## Default

Default every item to standalone. Only create parent/child or shared group links when Primary Partner/Operations Partner explicitly confirms the relationship.

## Concepts

- `inventory_uid`: specific item/listing row
- `inventory_group_id`: rollup for bundle/set/lot/acquisition group
- `parent_inventory_uid`: parent row if a child item belongs to another inventory row
- `allocated_cost`: child-level allocated cost
- `cost_basis_source`: direct/imported/free/bundle_child/gifted/unknown_needs_review

## Guardrails

- Do not double-count parent and child cost.
- If group has multiple children, sum child `allocated_cost` should equal group total unless explicitly unresolved.
- Cash-flow COGS can link to group-level for bundle acquisition or row-level for standalone/item-specific cost.

## Candidate examples needing confirmation

- `SRMF-00129` / `SRMF-00130`
- `SRMF-00121` / `SRMF-00123`

Do not link candidates without Primary Partner confirmation.

## Validation query

```sql
select g.inventory_group_id, g.total_acquisition_cost, sum(coalesce(i.allocated_cost,0)) allocated
from inventory_groups g
join inventory i using (inventory_group_id)
group by g.inventory_group_id, g.total_acquisition_cost
having count(*) > 1;
```
