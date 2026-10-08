# KPI Dictionary

All monetary values are Brazilian reais (BRL). Unless a visual says otherwise,
time-series reporting uses `order_purchase_timestamp`.

| KPI | Definition | Default population and grain | Main source fields | Guardrail |
| --- | --- | --- | --- | --- |
| GMV | Sum of item `price` | Order-item grain; non-canceled orders | order items, orders | Do not sum after joining raw payments or reviews. |
| Freight value | Sum of item `freight_value` | Order-item grain; non-canceled orders | order items, orders | Report separately from GMV. |
| Orders | Distinct `order_id` | Order grain; all orders unless status filter is shown | orders | Never count joined rows as orders. |
| Average order value | GMV divided by distinct non-canceled orders | Order grain | order items, orders | State whether freight is excluded; version 1 excludes it. |
| Delivered-order rate | Delivered orders divided by all orders | Order grain | orders | Keep denominator visible when comparing periods. |
| Cancellation rate | Canceled or unavailable orders divided by all orders | Order grain | orders | Show component statuses in drilldown. |
| Late-delivery rate | Delivered orders where actual delivery date is later than estimated date, divided by delivered orders with both dates | Order grain | orders | Exclude undelivered orders and missing comparison dates. |
| Average delivery days | Average days from purchase to customer delivery | Delivered-order grain | orders | Report median alongside average when useful because delays are skewed. |
| Seller-handling days | Days from approval to carrier handoff | Order-item/seller grain | orders, order items | One order can involve multiple sellers; seller attribution is item based. |
| Carrier-transit days | Days from carrier handoff to customer delivery | Delivered-order grain | orders | Carrier identity is unavailable, so this is a stage metric, not a carrier ranking. |
| Average review score | Mean review score | Review/order grain | reviews, orders | Document handling of rare multiple-review orders. |
| Low-rating rate | Reviews scored 1 or 2 divided by scored reviews | Review/order grain | reviews | Do not assume missing reviews are neutral. |
| Repeat-customer rate | Unique customers with at least two delivered orders divided by unique customers with at least one delivered order | `customer_unique_id` grain | customers, orders | Use `customer_unique_id`, never `customer_id`. |

## Delivery classification

- **Early:** actual delivery date is before the estimated delivery date.
- **On time:** actual and estimated delivery dates have the same calendar date.
- **Late:** actual delivery date is after the estimated delivery date.
- **Unknown:** the order is not delivered or either comparison date is missing.

## Seller scorecard rule

Seller rankings must include a minimum delivered-item or delivered-order threshold.
The threshold will be selected after the source distribution is profiled and must
be visible on the dashboard. This prevents a seller with one transaction from
being presented as meaningfully best or worst.
