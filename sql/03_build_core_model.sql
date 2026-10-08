/*
  Olist Delivery & Customer Experience Analytics
  Step 03: create the constrained and cleaned core data model.

  Safety behavior:
  - Source staging tables are never changed.
  - The script runs as one transaction.
  - The script refuses to overwrite an existing core model.
*/

USE OlistAnalytics;
GO

SET XACT_ABORT ON;
GO

IF EXISTS
(
    SELECT 1
    FROM sys.tables AS t
    INNER JOIN sys.schemas AS s
        ON s.schema_id = t.schema_id
    WHERE s.name = N'core'
      AND t.name IN
      (
          N'geolocation_zip',
          N'customers',
          N'products',
          N'sellers',
          N'orders',
          N'order_items',
          N'order_payments',
          N'order_reviews'
      )
)
BEGIN
    THROW 51000, 'One or more core tables already exist. No changes were made.', 1;
END;
GO

IF (SELECT COUNT_BIG(*) FROM stg.customers) <> 99441
   OR (SELECT COUNT_BIG(*) FROM stg.geolocation) <> 1000163
   OR (SELECT COUNT_BIG(*) FROM stg.order_items) <> 112650
   OR (SELECT COUNT_BIG(*) FROM stg.order_payments) <> 103886
   OR (SELECT COUNT_BIG(*) FROM stg.order_reviews) <> 99224
   OR (SELECT COUNT_BIG(*) FROM stg.orders) <> 99441
   OR (SELECT COUNT_BIG(*) FROM stg.products) <> 32951
   OR (SELECT COUNT_BIG(*) FROM stg.sellers) <> 3095
   OR (SELECT COUNT_BIG(*) FROM stg.product_category_translation) <> 71
BEGIN
    THROW 51001, 'Staging row counts do not match the audited source. No changes were made.', 1;
END;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    CREATE TABLE core.geolocation_zip
    (
        geolocation_zip_code_prefix INT NOT NULL,
        median_lat DECIMAL(10, 6) NOT NULL,
        median_lng DECIMAL(10, 6) NOT NULL,
        raw_source_rows BIGINT NOT NULL,
        distinct_coordinate_rows BIGINT NOT NULL,
        CONSTRAINT PK_core_geolocation_zip
            PRIMARY KEY CLUSTERED (geolocation_zip_code_prefix),
        CONSTRAINT CK_core_geolocation_zip_counts
            CHECK (raw_source_rows >= distinct_coordinate_rows
                   AND distinct_coordinate_rows > 0)
    );

    CREATE TABLE core.customers
    (
        customer_id CHAR(32) NOT NULL,
        customer_unique_id CHAR(32) NOT NULL,
        customer_zip_code_prefix INT NOT NULL,
        customer_city NVARCHAR(100) NOT NULL,
        customer_state CHAR(2) NOT NULL,
        CONSTRAINT PK_core_customers
            PRIMARY KEY CLUSTERED (customer_id)
    );

    CREATE TABLE core.products
    (
        product_id CHAR(32) NOT NULL,
        product_category_name_original NVARCHAR(100) NULL,
        product_category_name_english NVARCHAR(100) NOT NULL,
        category_translation_status NVARCHAR(20) NOT NULL,
        product_name_length SMALLINT NULL,
        product_description_length INT NULL,
        product_photos_qty SMALLINT NULL,
        product_weight_g INT NULL,
        product_length_cm SMALLINT NULL,
        product_height_cm SMALLINT NULL,
        product_width_cm SMALLINT NULL,
        CONSTRAINT PK_core_products
            PRIMARY KEY CLUSTERED (product_id),
        CONSTRAINT CK_core_products_translation_status
            CHECK
            (
                category_translation_status IN
                (N'translated', N'fallback_original', N'missing_category')
            ),
        CONSTRAINT CK_core_products_nonnegative
            CHECK
            (
                (product_name_length IS NULL OR product_name_length >= 0)
                AND (product_description_length IS NULL OR product_description_length >= 0)
                AND (product_photos_qty IS NULL OR product_photos_qty >= 0)
                AND (product_weight_g IS NULL OR product_weight_g >= 0)
                AND (product_length_cm IS NULL OR product_length_cm >= 0)
                AND (product_height_cm IS NULL OR product_height_cm >= 0)
                AND (product_width_cm IS NULL OR product_width_cm >= 0)
            )
    );

    CREATE TABLE core.sellers
    (
        seller_id CHAR(32) NOT NULL,
        seller_zip_code_prefix INT NOT NULL,
        seller_city NVARCHAR(100) NOT NULL,
        seller_state CHAR(2) NOT NULL,
        CONSTRAINT PK_core_sellers
            PRIMARY KEY CLUSTERED (seller_id)
    );

    CREATE TABLE core.orders
    (
        order_id CHAR(32) NOT NULL,
        customer_id CHAR(32) NOT NULL,
        order_status NVARCHAR(50) NOT NULL,
        order_purchase_timestamp DATETIME2(0) NOT NULL,
        order_approved_at DATETIME2(0) NULL,
        order_delivered_carrier_date DATETIME2(0) NULL,
        order_delivered_customer_date DATETIME2(0) NULL,
        order_estimated_delivery_date DATETIME2(0) NOT NULL,
        is_delivered BIT NOT NULL,
        delivery_performance NVARCHAR(10) NOT NULL,
        is_late BIT NULL,
        approval_to_carrier_hours DECIMAL(12, 2) NULL,
        carrier_to_customer_hours DECIMAL(12, 2) NULL,
        purchase_to_customer_days DECIMAL(12, 2) NULL,
        carrier_before_approval_flag BIT NOT NULL,
        customer_before_carrier_flag BIT NOT NULL,
        CONSTRAINT PK_core_orders
            PRIMARY KEY CLUSTERED (order_id),
        CONSTRAINT FK_core_orders_customers
            FOREIGN KEY (customer_id) REFERENCES core.customers (customer_id),
        CONSTRAINT CK_core_orders_delivery_performance
            CHECK (delivery_performance IN (N'early', N'on_time', N'late', N'unknown')),
        CONSTRAINT CK_core_orders_is_late
            CHECK
            (
                (delivery_performance = N'late' AND is_late = 1)
                OR (delivery_performance IN (N'early', N'on_time') AND is_late = 0)
                OR (delivery_performance = N'unknown' AND is_late IS NULL)
            )
    );

    CREATE TABLE core.order_items
    (
        order_id CHAR(32) NOT NULL,
        order_item_id SMALLINT NOT NULL,
        product_id CHAR(32) NOT NULL,
        seller_id CHAR(32) NOT NULL,
        shipping_limit_date DATETIME2(0) NOT NULL,
        price DECIMAL(14, 2) NOT NULL,
        freight_value DECIMAL(14, 2) NOT NULL,
        CONSTRAINT PK_core_order_items
            PRIMARY KEY CLUSTERED (order_id, order_item_id),
        CONSTRAINT FK_core_order_items_orders
            FOREIGN KEY (order_id) REFERENCES core.orders (order_id),
        CONSTRAINT FK_core_order_items_products
            FOREIGN KEY (product_id) REFERENCES core.products (product_id),
        CONSTRAINT FK_core_order_items_sellers
            FOREIGN KEY (seller_id) REFERENCES core.sellers (seller_id),
        CONSTRAINT CK_core_order_items_nonnegative
            CHECK (price >= 0 AND freight_value >= 0)
    );

    CREATE TABLE core.order_payments
    (
        order_id CHAR(32) NOT NULL,
        payment_sequential SMALLINT NOT NULL,
        payment_type NVARCHAR(50) NOT NULL,
        payment_installments SMALLINT NOT NULL,
        payment_value DECIMAL(14, 2) NOT NULL,
        CONSTRAINT PK_core_order_payments
            PRIMARY KEY CLUSTERED (order_id, payment_sequential),
        CONSTRAINT FK_core_order_payments_orders
            FOREIGN KEY (order_id) REFERENCES core.orders (order_id),
        CONSTRAINT CK_core_order_payments_nonnegative
            CHECK (payment_installments >= 0 AND payment_value >= 0)
    );

    CREATE TABLE core.order_reviews
    (
        review_id CHAR(32) NOT NULL,
        order_id CHAR(32) NOT NULL,
        review_score TINYINT NOT NULL,
        review_comment_title NVARCHAR(100) NULL,
        review_comment_message NVARCHAR(1000) NULL,
        review_creation_date DATETIME2(0) NOT NULL,
        review_answer_timestamp DATETIME2(0) NOT NULL,
        CONSTRAINT PK_core_order_reviews
            PRIMARY KEY CLUSTERED (review_id, order_id),
        CONSTRAINT FK_core_order_reviews_orders
            FOREIGN KEY (order_id) REFERENCES core.orders (order_id),
        CONSTRAINT CK_core_order_reviews_score
            CHECK (review_score BETWEEN 1 AND 5)
    );

    ;WITH distinct_points AS
    (
        SELECT DISTINCT
            geolocation_zip_code_prefix,
            geolocation_lat,
            geolocation_lng
        FROM stg.geolocation
    ),
    median_points AS
    (
        SELECT
            geolocation_zip_code_prefix,
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY geolocation_lat)
                OVER (PARTITION BY geolocation_zip_code_prefix) AS median_lat,
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY geolocation_lng)
                OVER (PARTITION BY geolocation_zip_code_prefix) AS median_lng
        FROM distinct_points
    ),
    raw_counts AS
    (
        SELECT
            geolocation_zip_code_prefix,
            COUNT_BIG(*) AS raw_source_rows
        FROM stg.geolocation
        GROUP BY geolocation_zip_code_prefix
    ),
    distinct_counts AS
    (
        SELECT
            geolocation_zip_code_prefix,
            COUNT_BIG(*) AS distinct_coordinate_rows
        FROM distinct_points
        GROUP BY geolocation_zip_code_prefix
    )
    INSERT INTO core.geolocation_zip
    (
        geolocation_zip_code_prefix,
        median_lat,
        median_lng,
        raw_source_rows,
        distinct_coordinate_rows
    )
    SELECT
        m.geolocation_zip_code_prefix,
        CAST(MIN(m.median_lat) AS DECIMAL(10, 6)),
        CAST(MIN(m.median_lng) AS DECIMAL(10, 6)),
        r.raw_source_rows,
        d.distinct_coordinate_rows
    FROM median_points AS m
    INNER JOIN raw_counts AS r
        ON r.geolocation_zip_code_prefix = m.geolocation_zip_code_prefix
    INNER JOIN distinct_counts AS d
        ON d.geolocation_zip_code_prefix = m.geolocation_zip_code_prefix
    GROUP BY
        m.geolocation_zip_code_prefix,
        r.raw_source_rows,
        d.distinct_coordinate_rows;

    INSERT INTO core.customers
    (
        customer_id,
        customer_unique_id,
        customer_zip_code_prefix,
        customer_city,
        customer_state
    )
    SELECT
        customer_id,
        customer_unique_id,
        customer_zip_code_prefix,
        customer_city,
        customer_state
    FROM stg.customers;

    INSERT INTO core.products
    (
        product_id,
        product_category_name_original,
        product_category_name_english,
        category_translation_status,
        product_name_length,
        product_description_length,
        product_photos_qty,
        product_weight_g,
        product_length_cm,
        product_height_cm,
        product_width_cm
    )
    SELECT
        p.product_id,
        p.product_category_name,
        COALESCE
        (
            t.product_category_name_english,
            p.product_category_name,
            N'unknown'
        ),
        CASE
            WHEN p.product_category_name IS NULL THEN N'missing_category'
            WHEN t.product_category_name IS NOT NULL THEN N'translated'
            ELSE N'fallback_original'
        END,
        p.product_name_lenght,
        p.product_description_lenght,
        p.product_photos_qty,
        p.product_weight_g,
        p.product_length_cm,
        p.product_height_cm,
        p.product_width_cm
    FROM stg.products AS p
    LEFT JOIN stg.product_category_translation AS t
        ON t.product_category_name = p.product_category_name;

    INSERT INTO core.sellers
    (
        seller_id,
        seller_zip_code_prefix,
        seller_city,
        seller_state
    )
    SELECT
        seller_id,
        seller_zip_code_prefix,
        seller_city,
        seller_state
    FROM stg.sellers;

    INSERT INTO core.orders
    (
        order_id,
        customer_id,
        order_status,
        order_purchase_timestamp,
        order_approved_at,
        order_delivered_carrier_date,
        order_delivered_customer_date,
        order_estimated_delivery_date,
        is_delivered,
        delivery_performance,
        is_late,
        approval_to_carrier_hours,
        carrier_to_customer_hours,
        purchase_to_customer_days,
        carrier_before_approval_flag,
        customer_before_carrier_flag
    )
    SELECT
        o.order_id,
        o.customer_id,
        o.order_status,
        o.order_purchase_timestamp,
        o.order_approved_at,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        CASE WHEN o.order_status = N'delivered' THEN 1 ELSE 0 END,
        CASE
            WHEN o.order_status <> N'delivered'
                 OR o.order_delivered_customer_date IS NULL
                 OR o.order_estimated_delivery_date IS NULL
                THEN N'unknown'
            WHEN CAST(o.order_delivered_customer_date AS DATE)
                 < CAST(o.order_estimated_delivery_date AS DATE)
                THEN N'early'
            WHEN CAST(o.order_delivered_customer_date AS DATE)
                 = CAST(o.order_estimated_delivery_date AS DATE)
                THEN N'on_time'
            ELSE N'late'
        END,
        CASE
            WHEN o.order_status <> N'delivered'
                 OR o.order_delivered_customer_date IS NULL
                 OR o.order_estimated_delivery_date IS NULL
                THEN NULL
            WHEN CAST(o.order_delivered_customer_date AS DATE)
                 > CAST(o.order_estimated_delivery_date AS DATE)
                THEN 1
            ELSE 0
        END,
        CASE
            WHEN o.order_approved_at IS NOT NULL
                 AND o.order_delivered_carrier_date >= o.order_approved_at
                THEN CAST
                (
                    DATEDIFF_BIG
                    (
                        MINUTE,
                        o.order_approved_at,
                        o.order_delivered_carrier_date
                    ) / 60.0
                    AS DECIMAL(12, 2)
                )
            ELSE NULL
        END,
        CASE
            WHEN o.order_delivered_carrier_date IS NOT NULL
                 AND o.order_delivered_customer_date >= o.order_delivered_carrier_date
                THEN CAST
                (
                    DATEDIFF_BIG
                    (
                        MINUTE,
                        o.order_delivered_carrier_date,
                        o.order_delivered_customer_date
                    ) / 60.0
                    AS DECIMAL(12, 2)
                )
            ELSE NULL
        END,
        CASE
            WHEN o.order_delivered_customer_date >= o.order_purchase_timestamp
                THEN CAST
                (
                    DATEDIFF_BIG
                    (
                        MINUTE,
                        o.order_purchase_timestamp,
                        o.order_delivered_customer_date
                    ) / 1440.0
                    AS DECIMAL(12, 2)
                )
            ELSE NULL
        END,
        CASE
            WHEN o.order_approved_at IS NOT NULL
                 AND o.order_delivered_carrier_date < o.order_approved_at
                THEN 1
            ELSE 0
        END,
        CASE
            WHEN o.order_delivered_carrier_date IS NOT NULL
                 AND o.order_delivered_customer_date < o.order_delivered_carrier_date
                THEN 1
            ELSE 0
        END
    FROM stg.orders AS o;

    INSERT INTO core.order_items
    (
        order_id,
        order_item_id,
        product_id,
        seller_id,
        shipping_limit_date,
        price,
        freight_value
    )
    SELECT
        order_id,
        order_item_id,
        product_id,
        seller_id,
        shipping_limit_date,
        price,
        freight_value
    FROM stg.order_items;

    INSERT INTO core.order_payments
    (
        order_id,
        payment_sequential,
        payment_type,
        payment_installments,
        payment_value
    )
    SELECT
        order_id,
        payment_sequential,
        payment_type,
        payment_installments,
        payment_value
    FROM stg.order_payments;

    INSERT INTO core.order_reviews
    (
        review_id,
        order_id,
        review_score,
        review_comment_title,
        review_comment_message,
        review_creation_date,
        review_answer_timestamp
    )
    SELECT
        review_id,
        order_id,
        review_score,
        review_comment_title,
        review_comment_message,
        review_creation_date,
        review_answer_timestamp
    FROM stg.order_reviews;

    CREATE INDEX IX_core_customers_unique_id
        ON core.customers (customer_unique_id)
        INCLUDE (customer_id, customer_state);

    CREATE INDEX IX_core_orders_purchase
        ON core.orders (order_purchase_timestamp)
        INCLUDE (order_status, delivery_performance, customer_id);

    CREATE INDEX IX_core_orders_delivery
        ON core.orders (delivery_performance, order_status)
        INCLUDE (order_purchase_timestamp, customer_id);

    CREATE INDEX IX_core_order_items_seller
        ON core.order_items (seller_id, order_id)
        INCLUDE (product_id, price, freight_value);

    CREATE INDEX IX_core_order_items_product
        ON core.order_items (product_id, order_id)
        INCLUDE (seller_id, price, freight_value);

    CREATE INDEX IX_core_order_payments_order
        ON core.order_payments (order_id)
        INCLUDE (payment_type, payment_value);

    CREATE INDEX IX_core_order_reviews_order
        ON core.order_reviews (order_id, review_answer_timestamp DESC)
        INCLUDE (review_id, review_score);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

WITH core_row_counts AS
(
    SELECT N'customers' AS table_name, COUNT_BIG(*) AS actual_rows, CAST(99441 AS BIGINT) AS expected_rows FROM core.customers
    UNION ALL SELECT N'geolocation_zip', COUNT_BIG(*), 19015 FROM core.geolocation_zip
    UNION ALL SELECT N'order_items', COUNT_BIG(*), 112650 FROM core.order_items
    UNION ALL SELECT N'order_payments', COUNT_BIG(*), 103886 FROM core.order_payments
    UNION ALL SELECT N'order_reviews', COUNT_BIG(*), 99224 FROM core.order_reviews
    UNION ALL SELECT N'orders', COUNT_BIG(*), 99441 FROM core.orders
    UNION ALL SELECT N'products', COUNT_BIG(*), 32951 FROM core.products
    UNION ALL SELECT N'sellers', COUNT_BIG(*), 3095 FROM core.sellers
)
SELECT
    table_name,
    actual_rows,
    expected_rows,
    actual_rows - expected_rows AS row_difference,
    CASE WHEN actual_rows = expected_rows THEN N'PASS' ELSE N'FAIL' END AS check_status
FROM core_row_counts
ORDER BY table_name;
GO

SELECT
    category_translation_status,
    COUNT_BIG(*) AS products
FROM core.products
GROUP BY category_translation_status
ORDER BY category_translation_status;
GO

SELECT
    delivery_performance,
    COUNT_BIG(*) AS orders
FROM core.orders
GROUP BY delivery_performance
ORDER BY delivery_performance;
GO

SELECT
    SUM(CAST(carrier_before_approval_flag AS BIGINT)) AS carrier_before_approval,
    SUM(CAST(customer_before_carrier_flag AS BIGINT)) AS customer_before_carrier,
    SUM(CASE WHEN is_delivered = 1 AND delivery_performance = N'unknown' THEN 1 ELSE 0 END)
        AS delivered_with_unknown_performance
FROM core.orders;
GO
