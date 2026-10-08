# Core Model Design

The `core` schema converts source-faithful staging rows into constrained,
analysis-ready entities. It does not delete or modify the `stg` tables.

## Tables and grains

| Table | Grain | Primary key |
| --- | --- | --- |
| `core.geolocation_zip` | One row per zip-code prefix | `geolocation_zip_code_prefix` |
| `core.customers` | One order-linked customer record | `customer_id` |
| `core.products` | One product | `product_id` |
| `core.sellers` | One seller | `seller_id` |
| `core.orders` | One order | `order_id` |
| `core.order_items` | One item position within an order | `(order_id, order_item_id)` |
| `core.order_payments` | One payment sequence within an order | `(order_id, payment_sequential)` |
| `core.order_reviews` | One review/order association | `(review_id, order_id)` |

## Transformation decisions

### Geography

Staging retains all 1,000,163 geolocation rows. The core layer produces one
coordinate per zip prefix using independent median latitude and longitude values
after exact coordinate deduplication. Medians reduce the effect of extreme source
coordinates. Customer and seller state fields remain authoritative for state
analysis because several zip prefixes have conflicting geolocation labels.

### Product categories

English translations are joined when available. Missing categories receive the
label `unknown`; the 13 categorized products without translation matches retain
their original category text. `category_translation_status` exposes which rule
was applied instead of silently dropping or relabeling records.

### Order chronology and delivery performance

The source timestamps remain intact. Derived durations are populated only when
their endpoints exist and occur in chronological order. Invalid negative
durations become null and are represented by explicit quality flags.

Delivery performance is based on calendar dates for delivered orders:

- `early`: actual date precedes estimated date;
- `on_time`: actual and estimated dates match;
- `late`: actual date follows estimated date; and
- `unknown`: the order is not delivered or a comparison date is unavailable.

### Reviews

Neither `review_id` nor `order_id` is unique independently. The composite
`(review_id, order_id)` uniquely identifies all source review rows and is used as
the core key. A later analytics view will select the latest answered review per
order so orders with multiple review rows are not overweighted.

## Safety and rerun behavior

The core build runs inside a transaction and refuses to execute if any target
core table already exists. This prevents accidental replacement of a curated
model. A deliberate rebuild should use a separately reviewed teardown or
migration script rather than hiding destructive drops inside the build.
