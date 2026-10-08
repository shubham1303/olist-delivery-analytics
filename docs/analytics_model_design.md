# Analytics Model Design

The `analytics` schema exposes governed views for Power BI and reusable SQL
analysis. Each view has one declared grain so items, payments, sellers, product
categories, and reviews do not multiply one another during joins.

## Views and grains

| View | Grain | Primary use |
| --- | --- | --- |
| `analytics.v_order_financials` | One row per order | Independently reconciled item and payment totals |
| `analytics.v_latest_order_review` | One selected review per reviewed order | Customer-experience measures without duplicate order reviews |
| `analytics.v_order_summary` | One row per order | Executive, delivery, geographic, and order-level KPIs |
| `analytics.v_order_seller_performance` | One row per order and seller | Seller attribution and operational drilldown |
| `analytics.v_order_category_performance` | One row per order and category | Category attribution and drilldown |
| `analytics.v_customer_repeat_summary` | One row per unique customer | Delivered-customer and repeat-customer measures |
| `analytics.v_seller_scorecard` | One row per seller | Governed seller ranking and threshold filtering |
| `analytics.v_monthly_kpis` | One row per purchase month | Reconciled KPI trends |

## Grain protection

`v_order_financials` aggregates items and payments in separate common table
expressions before joining either fact to orders. The order summary then joins
only one-row-per-order inputs. This prevents the many-to-many inflation that
would occur if raw items, payments, and reviews were joined directly.

`v_latest_order_review` selects the most recently answered review for each
order. Ties are resolved deterministically using creation timestamp and review
ID. Orders without reviews remain in `v_order_summary` with `has_review = 0`.

## Seller and category attribution

The seller view has one row for every order-seller combination. An order with
multiple sellers contributes once to each involved seller's delivery and review
outcomes, while GMV and freight remain limited to that seller's items. The view
exposes `is_multi_seller_order` so this limitation can be analyzed explicitly.

The category view applies the same rule at order-category grain. Item GMV and
freight are category-specific, while order-level delivery and review outcomes
are attributed to every category present in the order. `is_multi_category_order`
identifies orders whose outcome appears under more than one category.

## Governed KPI populations

- GMV is item price and excludes freight.
- Commercial GMV and average order value exclude `canceled` and `unavailable`
  orders unless a report explicitly states otherwise.
- Late-delivery rate uses late orders divided by delivered orders with valid
  actual and estimated dates.
- Low-rating rate uses latest reviews scored 1 or 2 divided by reviewed orders.
- Repeat-customer rate uses customers with at least two delivered orders divided
  by customers with at least one delivered order.
- Seller rankings require at least 20 delivered orders. This leaves 804 eligible
  sellers and avoids presenting very small samples as meaningful rankings.

## Power BI starting point

Use `v_order_summary` as the main order fact, `v_order_seller_performance` for
seller analysis, `v_order_category_performance` for category analysis, and
`v_customer_repeat_summary` for repeat-customer measures. Import
`v_monthly_kpis` as a SQL reconciliation table rather than the only source for
interactive measures.
