/*
  Olist Delivery & Customer Experience Analytics
  Step 00: create the local SQL Server database and logical schemas.

  Run this script while connected to a local SQL Server instance with permission
  to create databases. It is intentionally rerunnable.
*/

USE master;
GO

IF DB_ID(N'OlistAnalytics') IS NULL
BEGIN
    CREATE DATABASE OlistAnalytics;
END;
GO

USE OlistAnalytics;
GO

IF SCHEMA_ID(N'stg') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA stg AUTHORIZATION dbo;');
END;
GO

IF SCHEMA_ID(N'core') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA core AUTHORIZATION dbo;');
END;
GO

IF SCHEMA_ID(N'analytics') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA analytics AUTHORIZATION dbo;');
END;
GO

SELECT
    DB_NAME() AS database_name,
    name AS schema_name
FROM sys.schemas
WHERE name IN (N'stg', N'core', N'analytics')
ORDER BY name;
GO
