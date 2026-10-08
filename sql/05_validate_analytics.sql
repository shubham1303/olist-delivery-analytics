/*
  Olist Delivery & Customer Experience Analytics
  Step 05: reconcile analytics views to audited control totals.
*/

USE OlistAnalytics;
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'analytics.v_order_summary', N'V') IS NULL
   OR OBJECT_ID(N'analytics.v_seller_scorecard', N'V') IS NULL
   OR OBJECT_ID(N'analytics.v_monthly_kpis', N'V') IS NULL
BEGIN
    THROW 51011, 'Run sql/04_create_analytics_views.sql before validation.', 1;
END;
GO

WITH view_row_counts AS
(
    SELECT N'v_customer_repeat_summary' AS view_name,
           COUNT_BIG(*) AS actual_rows, CAST(96096 AS BIGINT) AS expected_rows
    FROM analytics.v_customer_repeat_summary
    UNION ALL SELECT N'v_latest_order_review', COUNT_BIG(*), 98673
    FROM analytics.v_latest_order_review
    UNION ALL SELECT N'v_monthly_kpis', COUNT_BIG(*), 25
    FROM analytics.v_monthly_kpis
    UNION ALL SELECT N'v_order_category_performance', COUNT_BIG(*), 99470
    FROM analytics.v_order_category_performance
    UNION ALL SELECT N'v_order_financials', COUNT_BIG(*), 99441
    FROM analytics.v_order_financials
    UNION ALL SELECT N'v_order_seller_performance', COUNT_BIG(*), 100010
    FROM analytics.v_order_seller_performance
    UNION ALL SELECT N'v_order_summary', COUNT_BIG(*), 99441
    FROM analytics.v_order_summary
    UNION ALL SELECT N'v_seller_scorecard', COUNT_BIG(*), 3095
    FROM analytics.v_seller_scorecard
)
SELECT
    view_name,
    actual_rows,
    expected_rows,
    actual_rows - expected_rows AS row_difference,
    CASE WHEN actual_rows = expected_rows THEN N'PASS' ELSE N'FAIL' END
        AS check_status
FROM view_row_counts
ORDER BY view_name;
GO

WITH order_controls AS
(
    SELECT
        SUM(CASE WHEN is_delivered = 1 THEN CAST(1 AS BIGINT) ELSE 0 END)
            AS delivered_orders,
        SUM(CASE WHEN is_comparable_delivery = 1 THEN CAST(1 AS BIGINT) ELSE 0 END)
            AS comparable_delivered_orders,
        SUM(CASE WHEN is_late = 1 THEN CAST(1 AS BIGINT) ELSE 0 END)
            AS late_orders,
        CAST
        (
            SUM(CASE WHEN is_delivered = 1 THEN gmv ELSE 0 END)
            AS DECIMAL(18, 2)
        ) AS delivered_gmv,
        CAST
        (
            SUM(CASE WHEN is_delivered = 1 THEN freight_value ELSE 0 END)
            AS DECIMAL(18, 2)
        ) AS delivered_freight,
        SUM(CASE WHEN has_review = 1 THEN CAST(1 AS BIGINT) ELSE 0 END)
            AS reviewed_orders,
        SUM(CASE WHEN is_low_rating = 1 THEN CAST(1 AS BIGINT) ELSE 0 END)
            AS low_rating_orders,
        CAST(AVG(CAST(review_score AS DECIMAL(18, 6))) AS DECIMAL(10, 4))
            AS average_review_score
    FROM analytics.v_order_summary
)
SELECT
    control_name,
    actual_value,
    expected_value,
    CASE WHEN actual_value = expected_value THEN N'PASS' ELSE N'FAIL' END
        AS check_status
FROM order_controls AS oc
CROSS APPLY
(
    VALUES
        (N'delivered_orders', CAST(oc.delivered_orders AS DECIMAL(20, 4)), CAST(96478 AS DECIMAL(20, 4))),
        (N'comparable_delivered_orders', CAST(oc.comparable_delivered_orders AS DECIMAL(20, 4)), CAST(96470 AS DECIMAL(20, 4))),
        (N'late_orders', CAST(oc.late_orders AS DECIMAL(20, 4)), CAST(6534 AS DECIMAL(20, 4))),
        (N'delivered_gmv', CAST(oc.delivered_gmv AS DECIMAL(20, 4)), CAST(13221498.11 AS DECIMAL(20, 4))),
        (N'delivered_freight', CAST(oc.delivered_freight AS DECIMAL(20, 4)), CAST(2198275.64 AS DECIMAL(20, 4))),
        (N'reviewed_orders', CAST(oc.reviewed_orders AS DECIMAL(20, 4)), CAST(98673 AS DECIMAL(20, 4))),
        (N'low_rating_orders', CAST(oc.low_rating_orders AS DECIMAL(20, 4)), CAST(14494 AS DECIMAL(20, 4))),
        (N'average_review_score', CAST(oc.average_review_score AS DECIMAL(20, 4)), CAST(4.0864 AS DECIMAL(20, 4)))
) AS controls(control_name, actual_value, expected_value)
ORDER BY control_name;
GO

SELECT
    SUM(CASE WHEN has_delivered_order = 1 THEN CAST(1 AS BIGINT) ELSE 0 END)
        AS delivered_customers,
    SUM(CASE WHEN is_repeat_delivered_customer = 1 THEN CAST(1 AS BIGINT) ELSE 0 END)
        AS repeat_delivered_customers,
    CAST
    (
        CAST
        (
            SUM(CASE WHEN is_repeat_delivered_customer = 1
                     THEN CAST(1 AS BIGINT) ELSE 0 END)
            AS DECIMAL(18, 6)
        )
        / NULLIF
          (
              SUM(CASE WHEN has_delivered_order = 1
                       THEN CAST(1 AS BIGINT) ELSE 0 END),
              0
          )
        AS DECIMAL(12, 6)
    ) AS repeat_customer_rate,
    CASE
        WHEN SUM(CASE WHEN has_delivered_order = 1 THEN 1 ELSE 0 END) = 93358
         AND SUM(CASE WHEN is_repeat_delivered_customer = 1 THEN 1 ELSE 0 END) = 2801
        THEN N'PASS' ELSE N'FAIL'
    END AS check_status
FROM analytics.v_customer_repeat_summary;
GO

SELECT
    SUM(CASE WHEN has_item = 0 THEN CAST(1 AS BIGINT) ELSE 0 END)
        AS orders_without_items,
    SUM(CASE WHEN has_payment = 0 THEN CAST(1 AS BIGINT) ELSE 0 END)
        AS orders_without_payments,
    CAST(SUM(payment_total) AS DECIMAL(18, 2)) AS payment_total,
    CASE
        WHEN SUM(CASE WHEN has_item = 0 THEN 1 ELSE 0 END) = 775
         AND SUM(CASE WHEN has_payment = 0 THEN 1 ELSE 0 END) = 1
         AND CAST(SUM(payment_total) AS DECIMAL(18, 2)) = 16008872.12
        THEN N'PASS' ELSE N'FAIL'
    END AS check_status
FROM analytics.v_order_financials;
GO

SELECT
    SUM(CASE WHEN meets_20_delivered_order_threshold = 1
             THEN CAST(1 AS BIGINT) ELSE 0 END) AS eligible_sellers,
    CAST(20 AS INT) AS delivered_order_threshold,
    CASE
        WHEN SUM(CASE WHEN meets_20_delivered_order_threshold = 1
                      THEN 1 ELSE 0 END) = 804
        THEN N'PASS' ELSE N'FAIL'
    END AS check_status
FROM analytics.v_seller_scorecard;
GO
