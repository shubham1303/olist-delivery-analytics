/*
  Olist Delivery & Customer Experience Analytics
  Step 04: create governed analytics views.

  Grain rule:
  - Items, payments, and reviews are reduced independently before they are
    joined to orders.
  - Seller and category views declare their attribution grain explicitly.

  Rerun behavior:
  - CREATE OR ALTER VIEW makes this script safe to rerun.
  - Core tables are read only and are never changed.
*/

USE OlistAnalytics;
GO

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'core.customers', N'U') IS NULL
   OR OBJECT_ID(N'core.products', N'U') IS NULL
   OR OBJECT_ID(N'core.sellers', N'U') IS NULL
   OR OBJECT_ID(N'core.orders', N'U') IS NULL
   OR OBJECT_ID(N'core.order_items', N'U') IS NULL
   OR OBJECT_ID(N'core.order_payments', N'U') IS NULL
   OR OBJECT_ID(N'core.order_reviews', N'U') IS NULL
   OR OBJECT_ID(N'core.geolocation_zip', N'U') IS NULL
BEGIN
    THROW 51010, 'The complete core model is required before analytics views are created.', 1;
END;
GO

CREATE OR ALTER VIEW analytics.v_order_financials
AS
WITH item_rollup AS
(
    SELECT
        oi.order_id,
        COUNT_BIG(*) AS item_count,
        COUNT(DISTINCT oi.product_id) AS product_count,
        COUNT(DISTINCT oi.seller_id) AS seller_count,
        CAST(SUM(oi.price) AS DECIMAL(18, 2)) AS gmv,
        CAST(SUM(oi.freight_value) AS DECIMAL(18, 2)) AS freight_value
    FROM core.order_items AS oi
    GROUP BY oi.order_id
),
payment_rollup AS
(
    SELECT
        op.order_id,
        COUNT_BIG(*) AS payment_record_count,
        COUNT(DISTINCT op.payment_type) AS payment_method_count,
        CAST(SUM(op.payment_value) AS DECIMAL(18, 2)) AS payment_total
    FROM core.order_payments AS op
    GROUP BY op.order_id
)
SELECT
    o.order_id,
    COALESCE(i.item_count, CAST(0 AS BIGINT)) AS item_count,
    COALESCE(i.product_count, 0) AS product_count,
    COALESCE(i.seller_count, 0) AS seller_count,
    CAST(COALESCE(i.gmv, 0) AS DECIMAL(18, 2)) AS gmv,
    CAST(COALESCE(i.freight_value, 0) AS DECIMAL(18, 2)) AS freight_value,
    CAST(COALESCE(i.gmv, 0) + COALESCE(i.freight_value, 0) AS DECIMAL(18, 2))
        AS item_total_with_freight,
    COALESCE(p.payment_record_count, CAST(0 AS BIGINT)) AS payment_record_count,
    COALESCE(p.payment_method_count, 0) AS payment_method_count,
    CAST(COALESCE(p.payment_total, 0) AS DECIMAL(18, 2)) AS payment_total,
    CAST
    (
        COALESCE(p.payment_total, 0)
        - COALESCE(i.gmv, 0)
        - COALESCE(i.freight_value, 0)
        AS DECIMAL(18, 2)
    ) AS payment_item_difference,
    CAST(CASE WHEN i.order_id IS NULL THEN 0 ELSE 1 END AS BIT) AS has_item,
    CAST(CASE WHEN p.order_id IS NULL THEN 0 ELSE 1 END AS BIT) AS has_payment
FROM core.orders AS o
LEFT JOIN item_rollup AS i
    ON i.order_id = o.order_id
LEFT JOIN payment_rollup AS p
    ON p.order_id = o.order_id;
GO

CREATE OR ALTER VIEW analytics.v_latest_order_review
AS
WITH ranked_reviews AS
(
    SELECT
        r.review_id,
        r.order_id,
        r.review_score,
        r.review_comment_title,
        r.review_comment_message,
        r.review_creation_date,
        r.review_answer_timestamp,
        ROW_NUMBER() OVER
        (
            PARTITION BY r.order_id
            ORDER BY
                r.review_answer_timestamp DESC,
                r.review_creation_date DESC,
                r.review_id DESC
        ) AS review_rank
    FROM core.order_reviews AS r
)
SELECT
    review_id,
    order_id,
    review_score,
    review_comment_title,
    review_comment_message,
    review_creation_date,
    review_answer_timestamp,
    CAST(CASE WHEN review_score IN (1, 2) THEN 1 ELSE 0 END AS BIT)
        AS is_low_rating
FROM ranked_reviews
WHERE review_rank = 1;
GO

CREATE OR ALTER VIEW analytics.v_order_summary
AS
SELECT
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.customer_zip_code_prefix,
    c.customer_city,
    c.customer_state,
    g.median_lat AS customer_lat,
    g.median_lng AS customer_lng,
    o.order_status,
    CAST(o.order_purchase_timestamp AS DATE) AS order_purchase_date,
    DATEFROMPARTS
    (
        YEAR(o.order_purchase_timestamp),
        MONTH(o.order_purchase_timestamp),
        1
    ) AS order_purchase_month,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    o.is_delivered,
    CAST
    (
        CASE WHEN o.order_status IN (N'canceled', N'unavailable') THEN 1 ELSE 0 END
        AS BIT
    ) AS is_canceled_or_unavailable,
    CAST
    (
        CASE WHEN o.delivery_performance IN (N'early', N'on_time', N'late')
             THEN 1 ELSE 0 END
        AS BIT
    ) AS is_comparable_delivery,
    o.delivery_performance,
    o.is_late,
    o.approval_to_carrier_hours,
    o.carrier_to_customer_hours,
    o.purchase_to_customer_days,
    o.carrier_before_approval_flag,
    o.customer_before_carrier_flag,
    f.item_count,
    f.product_count,
    f.seller_count,
    f.gmv,
    f.freight_value,
    f.item_total_with_freight,
    f.payment_record_count,
    f.payment_method_count,
    f.payment_total,
    f.payment_item_difference,
    f.has_item,
    f.has_payment,
    r.review_id,
    r.review_score,
    r.is_low_rating,
    r.review_creation_date,
    r.review_answer_timestamp,
    CAST(CASE WHEN r.order_id IS NULL THEN 0 ELSE 1 END AS BIT) AS has_review
FROM core.orders AS o
INNER JOIN core.customers AS c
    ON c.customer_id = o.customer_id
LEFT JOIN core.geolocation_zip AS g
    ON g.geolocation_zip_code_prefix = c.customer_zip_code_prefix
INNER JOIN analytics.v_order_financials AS f
    ON f.order_id = o.order_id
LEFT JOIN analytics.v_latest_order_review AS r
    ON r.order_id = o.order_id;
GO

CREATE OR ALTER VIEW analytics.v_order_seller_performance
AS
WITH seller_item_rollup AS
(
    SELECT
        oi.order_id,
        oi.seller_id,
        COUNT_BIG(*) AS seller_item_count,
        COUNT(DISTINCT oi.product_id) AS seller_product_count,
        CAST(SUM(oi.price) AS DECIMAL(18, 2)) AS seller_gmv,
        CAST(SUM(oi.freight_value) AS DECIMAL(18, 2)) AS seller_freight_value
    FROM core.order_items AS oi
    GROUP BY
        oi.order_id,
        oi.seller_id
)
SELECT
    si.order_id,
    si.seller_id,
    s.seller_zip_code_prefix,
    s.seller_city,
    s.seller_state,
    g.median_lat AS seller_lat,
    g.median_lng AS seller_lng,
    os.order_purchase_date,
    os.order_purchase_month,
    os.order_status,
    os.is_delivered,
    os.is_canceled_or_unavailable,
    os.is_comparable_delivery,
    os.delivery_performance,
    os.is_late,
    os.approval_to_carrier_hours,
    os.carrier_to_customer_hours,
    os.purchase_to_customer_days,
    os.customer_state,
    os.seller_count AS order_seller_count,
    CAST(CASE WHEN os.seller_count > 1 THEN 1 ELSE 0 END AS BIT)
        AS is_multi_seller_order,
    si.seller_item_count,
    si.seller_product_count,
    si.seller_gmv,
    si.seller_freight_value,
    os.has_review,
    os.review_score,
    os.is_low_rating
FROM seller_item_rollup AS si
INNER JOIN core.sellers AS s
    ON s.seller_id = si.seller_id
INNER JOIN analytics.v_order_summary AS os
    ON os.order_id = si.order_id
LEFT JOIN core.geolocation_zip AS g
    ON g.geolocation_zip_code_prefix = s.seller_zip_code_prefix;
GO

CREATE OR ALTER VIEW analytics.v_order_category_performance
AS
WITH category_item_rollup AS
(
    SELECT
        oi.order_id,
        p.product_category_name_english AS product_category,
        COUNT_BIG(*) AS category_item_count,
        COUNT(DISTINCT oi.product_id) AS category_product_count,
        COUNT(DISTINCT oi.seller_id) AS category_seller_count,
        CAST(SUM(oi.price) AS DECIMAL(18, 2)) AS category_gmv,
        CAST(SUM(oi.freight_value) AS DECIMAL(18, 2)) AS category_freight_value
    FROM core.order_items AS oi
    INNER JOIN core.products AS p
        ON p.product_id = oi.product_id
    GROUP BY
        oi.order_id,
        p.product_category_name_english
),
category_with_count AS
(
    SELECT
        c.*,
        COUNT_BIG(*) OVER (PARTITION BY c.order_id) AS order_category_count
    FROM category_item_rollup AS c
)
SELECT
    c.order_id,
    c.product_category,
    os.order_purchase_date,
    os.order_purchase_month,
    os.order_status,
    os.is_delivered,
    os.is_canceled_or_unavailable,
    os.is_comparable_delivery,
    os.delivery_performance,
    os.is_late,
    os.approval_to_carrier_hours,
    os.carrier_to_customer_hours,
    os.purchase_to_customer_days,
    os.customer_state,
    c.order_category_count,
    CAST(CASE WHEN c.order_category_count > 1 THEN 1 ELSE 0 END AS BIT)
        AS is_multi_category_order,
    c.category_item_count,
    c.category_product_count,
    c.category_seller_count,
    c.category_gmv,
    c.category_freight_value,
    os.has_review,
    os.review_score,
    os.is_low_rating
FROM category_with_count AS c
INNER JOIN analytics.v_order_summary AS os
    ON os.order_id = c.order_id;
GO

CREATE OR ALTER VIEW analytics.v_customer_repeat_summary
AS
SELECT
    os.customer_unique_id,
    MIN(os.order_purchase_date) AS first_order_date,
    MAX(os.order_purchase_date) AS latest_order_date,
    COUNT_BIG(*) AS total_orders,
    SUM(CASE WHEN os.is_delivered = 1 THEN CAST(1 AS BIGINT) ELSE 0 END)
        AS delivered_orders,
    CAST
    (
        SUM(CASE WHEN os.is_delivered = 1 THEN os.gmv ELSE 0 END)
        AS DECIMAL(18, 2)
    ) AS delivered_gmv,
    CAST
    (
        CASE WHEN SUM(CASE WHEN os.is_delivered = 1 THEN 1 ELSE 0 END) >= 1
             THEN 1 ELSE 0 END
        AS BIT
    ) AS has_delivered_order,
    CAST
    (
        CASE WHEN SUM(CASE WHEN os.is_delivered = 1 THEN 1 ELSE 0 END) >= 2
             THEN 1 ELSE 0 END
        AS BIT
    ) AS is_repeat_delivered_customer
FROM analytics.v_order_summary AS os
GROUP BY os.customer_unique_id;
GO

CREATE OR ALTER VIEW analytics.v_seller_scorecard
AS
WITH seller_rollup AS
(
    SELECT
        osp.seller_id,
        MAX(osp.seller_city) AS seller_city,
        MAX(osp.seller_state) AS seller_state,
        MIN(osp.order_purchase_date) AS first_order_date,
        MAX(osp.order_purchase_date) AS latest_order_date,
        COUNT_BIG(*) AS total_orders,
        SUM(CASE WHEN osp.is_delivered = 1 THEN CAST(1 AS BIGINT) ELSE 0 END)
            AS delivered_orders,
        SUM(CASE WHEN osp.is_comparable_delivery = 1 THEN CAST(1 AS BIGINT) ELSE 0 END)
            AS comparable_delivered_orders,
        SUM(CASE WHEN osp.is_late = 1 THEN CAST(1 AS BIGINT) ELSE 0 END)
            AS late_orders,
        SUM(osp.seller_item_count) AS sold_items,
        CAST
        (
            SUM
            (
                CASE WHEN osp.is_canceled_or_unavailable = 0
                     THEN osp.seller_gmv ELSE 0 END
            ) AS DECIMAL(18, 2)
        ) AS noncanceled_gmv,
        CAST
        (
            SUM
            (
                CASE WHEN osp.is_canceled_or_unavailable = 0
                     THEN osp.seller_freight_value ELSE 0 END
            ) AS DECIMAL(18, 2)
        ) AS noncanceled_freight_value,
        SUM(CASE WHEN osp.has_review = 1 THEN CAST(1 AS BIGINT) ELSE 0 END)
            AS reviewed_orders,
        SUM(CASE WHEN osp.is_low_rating = 1 THEN CAST(1 AS BIGINT) ELSE 0 END)
            AS low_rating_orders,
        CAST(AVG(CAST(osp.approval_to_carrier_hours AS DECIMAL(18, 4))) AS DECIMAL(18, 2))
            AS average_approval_to_carrier_hours,
        CAST(AVG(CAST(osp.carrier_to_customer_hours AS DECIMAL(18, 4))) AS DECIMAL(18, 2))
            AS average_carrier_to_customer_hours,
        CAST(AVG(CAST(osp.review_score AS DECIMAL(18, 4))) AS DECIMAL(10, 4))
            AS average_review_score
    FROM analytics.v_order_seller_performance AS osp
    GROUP BY osp.seller_id
)
SELECT
    sr.seller_id,
    sr.seller_city,
    sr.seller_state,
    sr.first_order_date,
    sr.latest_order_date,
    sr.total_orders,
    sr.delivered_orders,
    sr.comparable_delivered_orders,
    sr.late_orders,
    sr.sold_items,
    sr.noncanceled_gmv,
    sr.noncanceled_freight_value,
    sr.reviewed_orders,
    sr.low_rating_orders,
    sr.average_approval_to_carrier_hours,
    sr.average_carrier_to_customer_hours,
    sr.average_review_score,
    CAST
    (
        CAST(sr.late_orders AS DECIMAL(18, 6))
        / NULLIF(sr.comparable_delivered_orders, 0)
        AS DECIMAL(12, 6)
    ) AS late_delivery_rate,
    CAST
    (
        CAST(sr.low_rating_orders AS DECIMAL(18, 6))
        / NULLIF(sr.reviewed_orders, 0)
        AS DECIMAL(12, 6)
    ) AS low_rating_rate,
    CAST(CASE WHEN sr.delivered_orders >= 20 THEN 1 ELSE 0 END AS BIT)
        AS meets_20_delivered_order_threshold
FROM seller_rollup AS sr;
GO

CREATE OR ALTER VIEW analytics.v_monthly_kpis
AS
WITH monthly_rollup AS
(
    SELECT
        os.order_purchase_month,
        COUNT_BIG(*) AS total_orders,
        SUM(CASE WHEN os.is_delivered = 1 THEN CAST(1 AS BIGINT) ELSE 0 END)
            AS delivered_orders,
        SUM
        (
            CASE WHEN os.is_canceled_or_unavailable = 1
                 THEN CAST(1 AS BIGINT) ELSE 0 END
        ) AS canceled_or_unavailable_orders,
        SUM
        (
            CASE WHEN os.is_comparable_delivery = 1
                 THEN CAST(1 AS BIGINT) ELSE 0 END
        ) AS comparable_delivered_orders,
        SUM(CASE WHEN os.is_late = 1 THEN CAST(1 AS BIGINT) ELSE 0 END)
            AS late_orders,
        SUM(CASE WHEN os.has_review = 1 THEN CAST(1 AS BIGINT) ELSE 0 END)
            AS reviewed_orders,
        SUM(CASE WHEN os.is_low_rating = 1 THEN CAST(1 AS BIGINT) ELSE 0 END)
            AS low_rating_orders,
        SUM(CASE WHEN os.is_canceled_or_unavailable = 0 THEN CAST(1 AS BIGINT) ELSE 0 END)
            AS noncanceled_orders,
        CAST
        (
            SUM
            (
                CASE WHEN os.is_canceled_or_unavailable = 0 THEN os.gmv ELSE 0 END
            ) AS DECIMAL(18, 2)
        ) AS noncanceled_gmv,
        CAST
        (
            SUM
            (
                CASE WHEN os.is_canceled_or_unavailable = 0
                     THEN os.freight_value ELSE 0 END
            ) AS DECIMAL(18, 2)
        ) AS noncanceled_freight_value,
        CAST(AVG(CAST(os.purchase_to_customer_days AS DECIMAL(18, 4))) AS DECIMAL(18, 2))
            AS average_delivery_days,
        CAST(AVG(CAST(os.review_score AS DECIMAL(18, 4))) AS DECIMAL(10, 4))
            AS average_review_score
    FROM analytics.v_order_summary AS os
    GROUP BY os.order_purchase_month
)
SELECT
    mr.order_purchase_month,
    mr.total_orders,
    mr.delivered_orders,
    mr.canceled_or_unavailable_orders,
    mr.comparable_delivered_orders,
    mr.late_orders,
    mr.reviewed_orders,
    mr.low_rating_orders,
    mr.noncanceled_orders,
    mr.noncanceled_gmv,
    mr.noncanceled_freight_value,
    mr.average_delivery_days,
    mr.average_review_score,
    CAST
    (
        CAST(mr.delivered_orders AS DECIMAL(18, 6)) / NULLIF(mr.total_orders, 0)
        AS DECIMAL(12, 6)
    ) AS delivered_order_rate,
    CAST
    (
        CAST(mr.canceled_or_unavailable_orders AS DECIMAL(18, 6))
        / NULLIF(mr.total_orders, 0)
        AS DECIMAL(12, 6)
    ) AS cancellation_rate,
    CAST
    (
        CAST(mr.late_orders AS DECIMAL(18, 6))
        / NULLIF(mr.comparable_delivered_orders, 0)
        AS DECIMAL(12, 6)
    ) AS late_delivery_rate,
    CAST
    (
        CAST(mr.low_rating_orders AS DECIMAL(18, 6))
        / NULLIF(mr.reviewed_orders, 0)
        AS DECIMAL(12, 6)
    ) AS low_rating_rate,
    CAST
    (
        mr.noncanceled_gmv / NULLIF(mr.noncanceled_orders, 0)
        AS DECIMAL(18, 2)
    ) AS average_order_value
FROM monthly_rollup AS mr;
GO

SELECT
    SCHEMA_NAME(v.schema_id) AS schema_name,
    v.name AS view_name
FROM sys.views AS v
WHERE SCHEMA_NAME(v.schema_id) = N'analytics'
ORDER BY v.name;
GO
