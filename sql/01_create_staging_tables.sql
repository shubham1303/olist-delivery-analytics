/*
  Olist Delivery & Customer Experience Analytics
  Step 01: create source-faithful SQL Server staging tables.

  Staging preserves source rows and adds load lineage. Business cleaning,
  deduplication, and conformed keys belong in the core layer.
*/

USE OlistAnalytics;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'stg.customers', N'U') IS NULL
BEGIN
    CREATE TABLE stg.customers
    (
        customer_id CHAR(32) NOT NULL,
        customer_unique_id CHAR(32) NOT NULL,
        customer_zip_code_prefix INT NOT NULL,
        customer_city NVARCHAR(100) NOT NULL,
        customer_state CHAR(2) NOT NULL,
        _source_row_number BIGINT NOT NULL,
        _load_batch_id UNIQUEIDENTIFIER NOT NULL,
        _loaded_at_utc DATETIME2(3) NOT NULL
    );
END;
GO

IF OBJECT_ID(N'stg.geolocation', N'U') IS NULL
BEGIN
    CREATE TABLE stg.geolocation
    (
        geolocation_zip_code_prefix INT NOT NULL,
        geolocation_lat DECIMAL(18, 15) NOT NULL,
        geolocation_lng DECIMAL(18, 15) NOT NULL,
        geolocation_city NVARCHAR(100) NOT NULL,
        geolocation_state CHAR(2) NOT NULL,
        _source_row_number BIGINT NOT NULL,
        _load_batch_id UNIQUEIDENTIFIER NOT NULL,
        _loaded_at_utc DATETIME2(3) NOT NULL
    );
END;
GO

IF OBJECT_ID(N'stg.order_items', N'U') IS NULL
BEGIN
    CREATE TABLE stg.order_items
    (
        order_id CHAR(32) NOT NULL,
        order_item_id SMALLINT NOT NULL,
        product_id CHAR(32) NOT NULL,
        seller_id CHAR(32) NOT NULL,
        shipping_limit_date DATETIME2(0) NOT NULL,
        price DECIMAL(14, 2) NOT NULL,
        freight_value DECIMAL(14, 2) NOT NULL,
        _source_row_number BIGINT NOT NULL,
        _load_batch_id UNIQUEIDENTIFIER NOT NULL,
        _loaded_at_utc DATETIME2(3) NOT NULL
    );
END;
GO

IF OBJECT_ID(N'stg.order_payments', N'U') IS NULL
BEGIN
    CREATE TABLE stg.order_payments
    (
        order_id CHAR(32) NOT NULL,
        payment_sequential SMALLINT NOT NULL,
        payment_type NVARCHAR(50) NOT NULL,
        payment_installments SMALLINT NOT NULL,
        payment_value DECIMAL(14, 2) NOT NULL,
        _source_row_number BIGINT NOT NULL,
        _load_batch_id UNIQUEIDENTIFIER NOT NULL,
        _loaded_at_utc DATETIME2(3) NOT NULL
    );
END;
GO

IF OBJECT_ID(N'stg.order_reviews', N'U') IS NULL
BEGIN
    CREATE TABLE stg.order_reviews
    (
        review_id CHAR(32) NOT NULL,
        order_id CHAR(32) NOT NULL,
        review_score TINYINT NOT NULL,
        review_comment_title NVARCHAR(100) NULL,
        review_comment_message NVARCHAR(1000) NULL,
        review_creation_date DATETIME2(0) NOT NULL,
        review_answer_timestamp DATETIME2(0) NOT NULL,
        _source_row_number BIGINT NOT NULL,
        _load_batch_id UNIQUEIDENTIFIER NOT NULL,
        _loaded_at_utc DATETIME2(3) NOT NULL
    );
END;
GO

IF OBJECT_ID(N'stg.orders', N'U') IS NULL
BEGIN
    CREATE TABLE stg.orders
    (
        order_id CHAR(32) NOT NULL,
        customer_id CHAR(32) NOT NULL,
        order_status NVARCHAR(50) NOT NULL,
        order_purchase_timestamp DATETIME2(0) NOT NULL,
        order_approved_at DATETIME2(0) NULL,
        order_delivered_carrier_date DATETIME2(0) NULL,
        order_delivered_customer_date DATETIME2(0) NULL,
        order_estimated_delivery_date DATETIME2(0) NOT NULL,
        _source_row_number BIGINT NOT NULL,
        _load_batch_id UNIQUEIDENTIFIER NOT NULL,
        _loaded_at_utc DATETIME2(3) NOT NULL
    );
END;
GO

IF OBJECT_ID(N'stg.products', N'U') IS NULL
BEGIN
    CREATE TABLE stg.products
    (
        product_id CHAR(32) NOT NULL,
        product_category_name NVARCHAR(100) NULL,
        product_name_lenght SMALLINT NULL,
        product_description_lenght INT NULL,
        product_photos_qty SMALLINT NULL,
        product_weight_g INT NULL,
        product_length_cm SMALLINT NULL,
        product_height_cm SMALLINT NULL,
        product_width_cm SMALLINT NULL,
        _source_row_number BIGINT NOT NULL,
        _load_batch_id UNIQUEIDENTIFIER NOT NULL,
        _loaded_at_utc DATETIME2(3) NOT NULL
    );
END;
GO

IF OBJECT_ID(N'stg.sellers', N'U') IS NULL
BEGIN
    CREATE TABLE stg.sellers
    (
        seller_id CHAR(32) NOT NULL,
        seller_zip_code_prefix INT NOT NULL,
        seller_city NVARCHAR(100) NOT NULL,
        seller_state CHAR(2) NOT NULL,
        _source_row_number BIGINT NOT NULL,
        _load_batch_id UNIQUEIDENTIFIER NOT NULL,
        _loaded_at_utc DATETIME2(3) NOT NULL
    );
END;
GO

IF OBJECT_ID(N'stg.product_category_translation', N'U') IS NULL
BEGIN
    CREATE TABLE stg.product_category_translation
    (
        product_category_name NVARCHAR(100) NOT NULL,
        product_category_name_english NVARCHAR(100) NOT NULL,
        _source_row_number BIGINT NOT NULL,
        _load_batch_id UNIQUEIDENTIFIER NOT NULL,
        _loaded_at_utc DATETIME2(3) NOT NULL
    );
END;
GO

SELECT
    schema_name(schema_id) AS schema_name,
    name AS table_name
FROM sys.tables
WHERE schema_name(schema_id) = N'stg'
ORDER BY name;
GO
