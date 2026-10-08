# Data-Quality Checklist

## Source receipt

- [ ] All nine expected CSV files are present.
- [ ] Filenames and required columns match the published structure.
- [ ] Row and column counts are recorded.
- [ ] File encoding and delimiter are readable.

## Completeness and validity

- [ ] Missing values are profiled by column.
- [ ] Timestamp fields parse successfully.
- [ ] `review_score` values are within 1–5 when present.
- [ ] `price`, `freight_value`, and `payment_value` are nonnegative.
- [ ] State abbreviations and order statuses are enumerated.
- [ ] Delivered orders with missing actual-delivery dates are investigated.
- [ ] Chronological anomalies are quantified rather than silently removed.

## Keys and relationships

- [ ] `orders.order_id` is unique.
- [ ] `customers.customer_id` is unique.
- [ ] `products.product_id` is unique.
- [ ] `sellers.seller_id` is unique.
- [ ] `(order_id, order_item_id)` is unique in order items.
- [ ] `(order_id, payment_sequential)` is unique in payments.
- [ ] Orphaned foreign keys are counted for every planned relationship.
- [ ] Multiple reviews per order are quantified before choosing the review grain.
- [ ] Duplicate geolocation records are measured and a zip-level aggregation rule is documented.

## Reconciliation controls

- [ ] Raw row counts reconcile to staging row counts.
- [ ] Distinct order counts reconcile between source and governed views.
- [ ] GMV is calculated before joining to payment or review facts.
- [ ] Payment totals are calculated at payment grain and reconciled separately.
- [ ] Power BI totals reconcile to SQL control queries.

## Documentation

- [ ] Each cleaning rule records the original issue, transformation, and impact.
- [ ] Exclusions are quantified.
- [ ] KPI denominators and date filters are visible.
- [ ] Historical-data limitations are stated in the dashboard and README.
