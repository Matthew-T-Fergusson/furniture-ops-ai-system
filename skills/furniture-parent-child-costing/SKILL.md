---
name: furniture-parent-child-costing
description: Use when deciding or updating furniture parent/child inventory groups, split listings, bundles, sets, lots, cost allocation, cost_basis_source, parent_inventory_uid, or preventing double-counted cost basis.
---

# Furniture Parent / Child + Cost Allocation

## Default

Default every item to standalone. Only create parent/child or shared group links when Primary Partner/Operations Partner explicitly confirms the relationship.

## User-approved cost treatment (2026-05-17)

Use one cost-bearing economic parent as the default for split sets / relisted remainder pieces:

- Original set/listing carries the acquisition COGS.
- When part of a set sells and remaining pieces are relisted, the new/relisted child rows normally carry `$0` acquisition COGS with an explicit cost-basis reason.
- When selling both a full set and individual pieces separately, keep the acquisition COGS associated with the full-set/original listing; related piece listings normally carry `$0` acquisition COGS.
- Do not require parent listing price/value to equal the sum of child listing prices/values; splitting can intentionally create higher aggregate asking price.
- Guardrail priority is no double-counted acquisition COGS, not parent/child price equality.
- Item-specific post-split costs (repair/refurb/delivery specific to one child) may be assigned to that child even when acquisition COGS is `$0`. Group-benefiting costs stay at parent/group level.

## Concepts

- `inventory_uid`: specific item/listing row
- `inventory_group_id`: rollup for bundle/set/lot/acquisition group
- `parent_inventory_uid`: parent row if a child item belongs to another inventory row
- `allocated_cost`: child-level allocated cost
- `cost_basis_source`: direct_purchase/direct_or_imported/free/gifted/parent_absorbed/split_child_zero_cogs/bundle_child_zero_cogs/unknown_needs_review

## Guardrails

- Do not double-count parent and child cost.
- If group has multiple children, sum child `allocated_cost` should equal group total only when using proportional allocation. For User-approved parent-absorbed / child-zero-COGS treatment, children may sum to `$0` while parent/group carries the acquisition COGS.
- Cash-flow COGS can link to group-level for bundle acquisition or row-level for standalone/item-specific cost.

## Validation query

```sql
select g.inventory_group_id, g.total_acquisition_cost, sum(coalesce(i.allocated_cost,0)) allocated
from inventory_groups g
join inventory i using (inventory_group_id)
group by g.inventory_group_id, g.total_acquisition_cost
having count(*) > 1;
```
