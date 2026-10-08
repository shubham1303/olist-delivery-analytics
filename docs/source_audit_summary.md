# Source Audit Summary

Audit date: 2026-09-01  
Source: Brazilian E-Commerce Public Dataset by Olist  
Archive SHA-256: `967e41e04fc306fe604e2a693f488995a8b41e5047418f8a5c8e4abd6deca784`

## Source inventory

| Source | Rows | Columns | Exact duplicate rows | Missing cells |
| --- | ---: | ---: | ---: | ---: |
| Customers | 99,441 | 5 | 0 | 0 |
| Geolocation | 1,000,163 | 5 | 261,831 | 0 |
| Order items | 112,650 | 7 | 0 | 0 |
| Order payments | 103,886 | 5 | 0 | 0 |
| Order reviews | 99,224 | 7 | 0 | 145,903 |
| Orders | 99,441 | 8 | 0 | 4,908 |
| Products | 32,951 | 9 | 0 | 2,448 |
| Sellers | 3,095 | 4 | 0 | 0 |
| Category translation | 71 | 2 | 0 | 0 |

All required columns were present. The tested customer, order, item, payment,
product, seller, and translation keys contained no nulls or duplicates.

## Date and status coverage

- Purchase timestamps range from 2016-09-04 through 2018-10-17.
- 96,478 of 99,441 orders are marked delivered.
- Other statuses include shipped (1,107), canceled (625), unavailable (609),
  invoiced (314), processing (301), created (5), and approved (2).
- Eight delivered orders lack the dates needed for an on-time comparison.

## Grain risks

| Condition | Affected orders | Maximum records or sellers per order |
| --- | ---: | ---: |
| Multiple items | 9,803 | 21 items |
| Multiple payment records | 2,961 | 29 payments |
| Multiple sellers | 1,278 | 5 sellers |
| Multiple review rows | 547 | 3 reviews |

These facts must not be directly joined and then aggregated. Each fact is first
aggregated to the intended order, order-seller, or order-item grain.

`review_id` alone is not unique: 814 rows exceed the distinct review-ID count.
`order_id` alone is also not unique in reviews. The composite `(review_id,
order_id)` is unique in this source and will identify staged review rows. For
order-level customer-experience reporting, the latest answered review per order
will be selected deterministically by answer timestamp and review ID.

## Missingness and relationship findings

- Review titles are missing on 88.34% of review rows.
- Review messages are missing on 58.70% of review rows.
- Actual customer-delivery dates are missing on 2.98% of orders; carrier-handoff
  dates are missing on 1.79%; approval timestamps are missing on 0.16%.
- Product category and its related name/description/photo attributes are missing
  on 610 products (1.85%).
- Two products lack physical dimensions or weight.
- Thirteen categorized products do not match the English translation table:
  10 `portateis_cozinha_e_preparadores_de_alimentos` and 3 `pc_gamer` rows.
  These rows will be retained using the Portuguese category as a fallback.
- One order has no payment row, 775 orders have no item row, and 768 orders have
  no review row. These are left-join conditions, not automatic deletions.

## Geography findings

- The geolocation file has 1,000,163 rows but only 19,015 zip-code prefixes.
- It contains 261,831 exact duplicate rows.
- Eight zip prefixes are associated with more than one state and 8,556 with more
  than one city spelling or label.
- The raw geography will remain unchanged in staging. The curated layer will use
  one median coordinate per zip prefix. Customer and seller state fields—not the
  geolocation label—will remain authoritative for state-level reporting.

## Chronology exceptions

- 1,359 orders show carrier handoff before approval.
- 23 orders show customer delivery before carrier handoff.
- No orders show approval before purchase, customer delivery before purchase, or
  estimated delivery before purchase.

Negative seller-handling or carrier-transit durations will be flagged and
excluded from duration averages. The source rows themselves remain unchanged.

## Preliminary control totals

These are reconciliation values, not final dashboard claims:

| Measure | Control total |
| --- | ---: |
| Delivered orders | 96,478 |
| Comparable delivered orders | 96,470 |
| Late comparable orders | 6,534 |
| Preliminary late-delivery rate | 6.7731% |
| Delivered-order item GMV | R$13,221,498.11 |
| Delivered-order freight | R$2,198,275.64 |
| Average review score | 4.0864 |
| One- or two-star review rate | 14.6890% |
| Delivered customers | 93,358 |
| Repeat delivered customers | 2,801 |
| Preliminary repeat-customer rate | 3.0003% |

Final dashboard measures will be recalculated from governed SQL views and
reconciled back to these controls.
