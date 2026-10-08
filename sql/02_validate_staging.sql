/*
  Olist Delivery & Customer Experience Analytics
  Step 02: validate the staging load against source control totals.
*/

USE OlistAnalytics;
GO

WITH row_counts AS
(
    SELECT N'customers' AS table_name, COUNT_BIG(*) AS actual_rows, CAST(99441 AS BIGINT) AS expected_rows FROM stg.customers
    UNION ALL SELECT N'geolocation', COUNT_BIG(*), 1000163 FROM stg.geolocation
    UNION ALL SELECT N'order_items', COUNT_BIG(*), 112650 FROM stg.order_items
    UNION ALL SELECT N'order_payments', COUNT_BIG(*), 103886 FROM stg.order_payments
    UNION ALL SELECT N'order_reviews', COUNT_BIG(*), 99224 FROM stg.order_reviews
    UNION ALL SELECT N'orders', COUNT_BIG(*), 99441 FROM stg.orders
    UNION ALL SELECT N'products', COUNT_BIG(*), 32951 FROM stg.products
    UNION ALL SELECT N'sellers', COUNT_BIG(*), 3095 FROM stg.sellers
    UNION ALL SELECT N'product_category_translation', COUNT_BIG(*), 71 FROM stg.product_category_translation
)
SELECT
    table_name,
    actual_rows,
    expected_rows,
    actual_rows - expected_rows AS row_difference,
    CASE WHEN actual_rows = expected_rows THEN N'PASS' ELSE N'FAIL' END AS check_status
FROM row_counts
ORDER BY table_name;
GO

SELECT
    N'orders.order_id uniqueness' AS check_name,
    COUNT_BIG(*) - COUNT_BIG(DISTINCT order_id) AS exception_rows
FROM stg.orders
UNION ALL
SELECT
    N'customers.customer_id uniqueness',
    COUNT_BIG(*) - COUNT_BIG(DISTINCT customer_id)
FROM stg.customers
UNION ALL
SELECT
    N'products.product_id uniqueness',
    COUNT_BIG(*) - COUNT_BIG(DISTINCT product_id)
FROM stg.products
UNION ALL
SELECT
    N'sellers.seller_id uniqueness',
    COUNT_BIG(*) - COUNT_BIG(DISTINCT seller_id)
FROM stg.sellers;
GO

SELECT
    p.product_category_name,
    COUNT_BIG(*) AS affected_products
FROM stg.products AS p
LEFT JOIN stg.product_category_translation AS t
    ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL
GROUP BY p.product_category_name
ORDER BY affected_products DESC, p.product_category_name;
GO

SELECT
    SUM(CASE WHEN order_delivered_carrier_date < order_approved_at THEN 1 ELSE 0 END) AS carrier_before_approval,
    SUM(CASE WHEN order_delivered_customer_date < order_delivered_carrier_date THEN 1 ELSE 0 END) AS customer_before_carrier,
    SUM(CASE WHEN order_approved_at < order_purchase_timestamp THEN 1 ELSE 0 END) AS approval_before_purchase,
    SUM(CASE WHEN order_delivered_customer_date < order_purchase_timestamp THEN 1 ELSE 0 END) AS customer_before_purchase
FROM stg.orders;
GO
