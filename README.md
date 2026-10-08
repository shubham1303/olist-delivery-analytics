# Olist delivery analytics

Which sellers, product categories and regions are behind late deliveries and bad
reviews on Olist (a Brazilian e-commerce marketplace)? This project loads the public
Olist dataset into SQL Server, builds a clean reporting model on top of it, and
answers that question in a Power BI dashboard (`olist_delivery_analytics.pbix`).

I scoped it like an analyst job at a marketplace ops team would be: a project
charter, KPI definitions, data quality checks, and then the dashboard. Docs for all
of that are in `docs/`.

## Some numbers from the data

From the source audit, ~99k orders between Sep 2016 and Oct 2018:

- 96,478 delivered orders, **6.8% of them late** (vs. the estimated date shown to the customer)
- R$13.2M in delivered item GMV plus R$2.2M freight
- average review 4.09, but 14.7% of reviews are 1 or 2 stars
- only 3% of customers ever order twice
- 804 sellers have at least 20 delivered orders, which is the cutoff I used for
  ranking sellers so tiny sellers don't top the charts by luck

## How it's built

```
9 Kaggle CSVs
  -> python profiler (row counts, nulls, key + relationship checks)
  -> stg.*        raw-ish staging tables in SQL Server
  -> core.*       cleaned, typed tables with proper keys
  -> analytics.*  8 views, one fixed grain each, for Power BI
  -> Power BI
```

The thing that took the most care was grain. An order can have several items,
several payments, several sellers and occasionally several reviews. If you join all
of that raw you double or triple count revenue. So every view in `analytics` has
exactly one grain (per order, per order+seller, per seller, per month, etc.) and
items and payments are aggregated separately before being joined. Details in
[docs/analytics_model_design.md](docs/analytics_model_design.md).

Some data quirks worth knowing about:
- the geolocation file has 1M rows but only ~19k zip prefixes (262k exact duplicates)
- 1,359 orders show the carrier picking up the package before payment was approved
- a couple of product category names are missing from the English translation table

## Running it

You need Docker, the ODBC Driver 18 for SQL Server, Python 3.11+ and Power BI Desktop
(Windows) to open the report.

1. Download the [Olist dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
   and drop the 9 CSVs into `data/raw/` without renaming them.
2. Start SQL Server 2022 in Docker:
   ```sh
   docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=<your password>" -p 1433:1433 --name olist-sqlserver -d mcr.microsoft.com/mssql/server:2022-latest
   ```
3. Python setup and profiling:
   ```powershell
   py -m venv .venv
   .\.venv\Scripts\Activate.ps1
   pip install -r requirements.txt
   python scripts/01_profile_data.py
   ```
4. Copy `.env.example` to `.env` and fill in your SQL Server login.
5. Run the SQL scripts in order (I used VS Code with the mssql extension), with the
   loader in between:
   - `sql/00_create_database.sql`
   - `sql/01_create_staging_tables.sql`
   - `python scripts/02_load_sql_server.py --dry-run`, then again without `--dry-run`
   - `sql/02_validate_staging.sql`
   - `sql/03_build_core_model.sql`
   - `sql/04_create_analytics_views.sql`
   - `sql/05_validate_analytics.sql` (checks the views against the expected totals)
6. Open the .pbix and point the data source at your server if it isn't `localhost`.

## Repo

- `scripts/` - profiler and the CSV -> SQL Server loader
- `sql/` - numbered in the order you run them
- `reports/` - output of the profiler
- `docs/` - charter, KPI dictionary, model design, source audit
- `olist_delivery_analytics.pbix` - the dashboard

## Data

The dataset is by Olist, published on Kaggle under CC BY-NC-SA 4.0. The CSVs aren't
included here, you have to download them yourself.
