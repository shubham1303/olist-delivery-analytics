"""Validate and load the Olist CSV files into SQL Server staging tables.

Examples:
    python scripts/02_load_sql_server.py --dry-run
    python scripts/02_load_sql_server.py
    python scripts/02_load_sql_server.py --truncate

The default load refuses to append when any target table already contains rows.
Use --truncate only when intentionally replacing an earlier staging load.
"""

from __future__ import annotations

import argparse
import os
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING
from urllib.parse import quote_plus
from uuid import uuid4

import pandas as pd

if TYPE_CHECKING:
    from sqlalchemy.engine import Engine


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RAW_DIR = ROOT / "data" / "raw"


@dataclass(frozen=True)
class SourceSpec:
    table: str
    columns: tuple[str, ...]
    date_columns: tuple[str, ...] = ()
    integer_columns: tuple[str, ...] = ()


SOURCES: dict[str, SourceSpec] = {
    "olist_customers_dataset.csv": SourceSpec(
        "customers",
        (
            "customer_id",
            "customer_unique_id",
            "customer_zip_code_prefix",
            "customer_city",
            "customer_state",
        ),
        integer_columns=("customer_zip_code_prefix",),
    ),
    "olist_geolocation_dataset.csv": SourceSpec(
        "geolocation",
        (
            "geolocation_zip_code_prefix",
            "geolocation_lat",
            "geolocation_lng",
            "geolocation_city",
            "geolocation_state",
        ),
        integer_columns=("geolocation_zip_code_prefix",),
    ),
    "olist_order_items_dataset.csv": SourceSpec(
        "order_items",
        (
            "order_id",
            "order_item_id",
            "product_id",
            "seller_id",
            "shipping_limit_date",
            "price",
            "freight_value",
        ),
        date_columns=("shipping_limit_date",),
        integer_columns=("order_item_id",),
    ),
    "olist_order_payments_dataset.csv": SourceSpec(
        "order_payments",
        (
            "order_id",
            "payment_sequential",
            "payment_type",
            "payment_installments",
            "payment_value",
        ),
        integer_columns=("payment_sequential", "payment_installments"),
    ),
    "olist_order_reviews_dataset.csv": SourceSpec(
        "order_reviews",
        (
            "review_id",
            "order_id",
            "review_score",
            "review_comment_title",
            "review_comment_message",
            "review_creation_date",
            "review_answer_timestamp",
        ),
        date_columns=("review_creation_date", "review_answer_timestamp"),
        integer_columns=("review_score",),
    ),
    "olist_orders_dataset.csv": SourceSpec(
        "orders",
        (
            "order_id",
            "customer_id",
            "order_status",
            "order_purchase_timestamp",
            "order_approved_at",
            "order_delivered_carrier_date",
            "order_delivered_customer_date",
            "order_estimated_delivery_date",
        ),
        date_columns=(
            "order_purchase_timestamp",
            "order_approved_at",
            "order_delivered_carrier_date",
            "order_delivered_customer_date",
            "order_estimated_delivery_date",
        ),
    ),
    "olist_products_dataset.csv": SourceSpec(
        "products",
        (
            "product_id",
            "product_category_name",
            "product_name_lenght",
            "product_description_lenght",
            "product_photos_qty",
            "product_weight_g",
            "product_length_cm",
            "product_height_cm",
            "product_width_cm",
        ),
        integer_columns=(
            "product_name_lenght",
            "product_description_lenght",
            "product_photos_qty",
            "product_weight_g",
            "product_length_cm",
            "product_height_cm",
            "product_width_cm",
        ),
    ),
    "olist_sellers_dataset.csv": SourceSpec(
        "sellers",
        ("seller_id", "seller_zip_code_prefix", "seller_city", "seller_state"),
        integer_columns=("seller_zip_code_prefix",),
    ),
    "product_category_name_translation.csv": SourceSpec(
        "product_category_translation",
        ("product_category_name", "product_category_name_english"),
    ),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-dir", type=Path, default=DEFAULT_RAW_DIR)
    parser.add_argument("--chunk-size", type=int, default=20_000)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate all files and conversions without connecting to SQL Server.",
    )
    parser.add_argument(
        "--truncate",
        action="store_true",
        help="Delete the existing staging rows before loading this source batch.",
    )
    return parser.parse_args()


def require_setting(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise SystemExit(f"Missing required environment setting: {name}")
    return value


def build_engine() -> "Engine":
    try:
        from dotenv import load_dotenv
        from sqlalchemy import create_engine
    except ImportError as exc:
        raise SystemExit(
            "SQL Server loading dependencies are missing. Run "
            "'python -m pip install -r requirements.txt' and try again."
        ) from exc

    load_dotenv(ROOT / ".env")
    server = require_setting("OLIST_SQL_SERVER")
    database = os.getenv("OLIST_SQL_DATABASE", "OlistAnalytics")
    username = require_setting("OLIST_SQL_USERNAME")
    password = require_setting("OLIST_SQL_PASSWORD")
    driver = os.getenv("OLIST_SQL_DRIVER", "ODBC Driver 18 for SQL Server")
    encrypt = os.getenv("OLIST_SQL_ENCRYPT", "yes")
    trust_certificate = os.getenv("OLIST_SQL_TRUST_SERVER_CERTIFICATE", "yes")

    odbc = (
        f"DRIVER={{{driver}}};SERVER={server};DATABASE={database};"
        f"UID={username};PWD={password};Encrypt={encrypt};"
        f"TrustServerCertificate={trust_certificate};"
    )
    return create_engine(
        f"mssql+pyodbc:///?odbc_connect={quote_plus(odbc)}",
        fast_executemany=True,
        future=True,
    )


def validate_header(path: Path, spec: SourceSpec) -> None:
    if not path.exists():
        raise SystemExit(f"Required source file is missing: {path}")
    actual = tuple(pd.read_csv(path, nrows=0).columns)
    if actual != spec.columns:
        raise SystemExit(
            f"Unexpected columns in {path.name}.\n"
            f"Expected: {list(spec.columns)}\nActual:   {list(actual)}"
        )


def prepare_chunk(
    chunk: pd.DataFrame,
    spec: SourceSpec,
    row_offset: int,
    load_batch_id: str,
    loaded_at_utc: pd.Timestamp,
) -> pd.DataFrame:
    for column in spec.date_columns:
        chunk[column] = pd.to_datetime(chunk[column], errors="raise")
    for column in spec.integer_columns:
        chunk[column] = pd.to_numeric(chunk[column], errors="raise").astype("Int64")

    chunk["_source_row_number"] = range(row_offset + 2, row_offset + len(chunk) + 2)
    chunk["_load_batch_id"] = load_batch_id
    chunk["_loaded_at_utc"] = loaded_at_utc
    return chunk


def validate_sources(raw_dir: Path, chunk_size: int) -> dict[str, int]:
    row_counts: dict[str, int] = {}
    validation_batch = str(uuid4())
    validation_time = pd.Timestamp.now(tz="UTC").tz_localize(None)
    for filename, spec in SOURCES.items():
        path = raw_dir / filename
        validate_header(path, spec)
        row_count = 0
        for chunk in pd.read_csv(path, chunksize=chunk_size, low_memory=False):
            prepare_chunk(chunk, spec, row_count, validation_batch, validation_time)
            row_count += len(chunk)
        row_counts[spec.table] = row_count
        print(f"Validated stg.{spec.table}: {row_count:,} row(s)")
    return row_counts


def assert_empty_or_truncate(engine: "Engine", truncate: bool) -> None:
    from sqlalchemy import text

    with engine.begin() as connection:
        existing = {
            spec.table: int(
                connection.execute(
                    text(f"SELECT COUNT_BIG(*) FROM stg.{spec.table}")
                ).scalar_one()
            )
            for spec in SOURCES.values()
        }
        populated = {table: count for table, count in existing.items() if count}
        if populated and not truncate:
            details = ", ".join(f"stg.{table}={count:,}" for table, count in populated.items())
            raise SystemExit(
                "The staging area is not empty. The loader will not append into a "
                f"previous batch: {details}. Rerun with --truncate only if replacement is intended."
            )
        if truncate:
            for spec in reversed(tuple(SOURCES.values())):
                connection.execute(text(f"TRUNCATE TABLE stg.{spec.table}"))


def load_sources(engine: "Engine", raw_dir: Path, chunk_size: int) -> None:
    from sqlalchemy import text

    load_batch_id = str(uuid4())
    loaded_at_utc = pd.Timestamp.now(tz="UTC").tz_localize(None)

    with engine.begin() as connection:
        for filename, spec in SOURCES.items():
            row_count = 0
            path = raw_dir / filename
            for chunk in pd.read_csv(path, chunksize=chunk_size, low_memory=False):
                prepared = prepare_chunk(
                    chunk,
                    spec,
                    row_count,
                    load_batch_id,
                    loaded_at_utc,
                )
                prepared.to_sql(
                    spec.table,
                    schema="stg",
                    con=connection,
                    if_exists="append",
                    index=False,
                    chunksize=chunk_size,
                    method=None,
                )
                row_count += len(prepared)

            sql_count = int(
                connection.execute(
                    text(
                        f"SELECT COUNT_BIG(*) FROM stg.{spec.table} "
                        "WHERE _load_batch_id = :load_batch_id"
                    ),
                    {"load_batch_id": load_batch_id},
                ).scalar_one()
            )
            if sql_count != row_count:
                raise RuntimeError(
                    f"Row-count mismatch for stg.{spec.table}: "
                    f"CSV={row_count:,}, SQL={sql_count:,}"
                )
            print(f"Loaded stg.{spec.table}: {row_count:,} row(s)")

    print(f"Load completed successfully. Batch ID: {load_batch_id}")


def main() -> None:
    args = parse_args()
    if args.chunk_size <= 0:
        raise SystemExit("--chunk-size must be greater than zero.")

    raw_dir = args.raw_dir.resolve()
    validate_sources(raw_dir, args.chunk_size)
    if args.dry_run:
        print("Dry run completed. No database changes were made.")
        return

    engine = build_engine()
    try:
        assert_empty_or_truncate(engine, args.truncate)
        load_sources(engine, raw_dir, args.chunk_size)
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
