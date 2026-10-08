"""Profile and validate the nine raw Olist CSV files.

Run from the repository root:
    python scripts/01_profile_data.py

Outputs:
    reports/file_profile.csv
    reports/column_profile.csv
    reports/key_checks.csv
    reports/relationship_checks.csv
"""

from __future__ import annotations

from pathlib import Path
from typing import Iterable

import pandas as pd


ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = ROOT / "data" / "raw"
REPORT_DIR = ROOT / "reports"

EXPECTED_COLUMNS: dict[str, list[str]] = {
    "olist_customers_dataset.csv": [
        "customer_id",
        "customer_unique_id",
        "customer_zip_code_prefix",
        "customer_city",
        "customer_state",
    ],
    "olist_geolocation_dataset.csv": [
        "geolocation_zip_code_prefix",
        "geolocation_lat",
        "geolocation_lng",
        "geolocation_city",
        "geolocation_state",
    ],
    "olist_order_items_dataset.csv": [
        "order_id",
        "order_item_id",
        "product_id",
        "seller_id",
        "shipping_limit_date",
        "price",
        "freight_value",
    ],
    "olist_order_payments_dataset.csv": [
        "order_id",
        "payment_sequential",
        "payment_type",
        "payment_installments",
        "payment_value",
    ],
    "olist_order_reviews_dataset.csv": [
        "review_id",
        "order_id",
        "review_score",
        "review_comment_title",
        "review_comment_message",
        "review_creation_date",
        "review_answer_timestamp",
    ],
    "olist_orders_dataset.csv": [
        "order_id",
        "customer_id",
        "order_status",
        "order_purchase_timestamp",
        "order_approved_at",
        "order_delivered_carrier_date",
        "order_delivered_customer_date",
        "order_estimated_delivery_date",
    ],
    "olist_products_dataset.csv": [
        "product_id",
        "product_category_name",
        "product_name_lenght",
        "product_description_lenght",
        "product_photos_qty",
        "product_weight_g",
        "product_length_cm",
        "product_height_cm",
        "product_width_cm",
    ],
    "olist_sellers_dataset.csv": [
        "seller_id",
        "seller_zip_code_prefix",
        "seller_city",
        "seller_state",
    ],
    "product_category_name_translation.csv": [
        "product_category_name",
        "product_category_name_english",
    ],
}

KEYS: dict[str, list[str]] = {
    "olist_customers_dataset.csv": ["customer_id"],
    "olist_order_items_dataset.csv": ["order_id", "order_item_id"],
    "olist_order_payments_dataset.csv": ["order_id", "payment_sequential"],
    "olist_orders_dataset.csv": ["order_id"],
    "olist_products_dataset.csv": ["product_id"],
    "olist_sellers_dataset.csv": ["seller_id"],
    "product_category_name_translation.csv": ["product_category_name"],
}

RELATIONSHIPS = [
    ("olist_orders_dataset.csv", "customer_id", "olist_customers_dataset.csv", "customer_id"),
    ("olist_order_items_dataset.csv", "order_id", "olist_orders_dataset.csv", "order_id"),
    ("olist_order_payments_dataset.csv", "order_id", "olist_orders_dataset.csv", "order_id"),
    ("olist_order_reviews_dataset.csv", "order_id", "olist_orders_dataset.csv", "order_id"),
    ("olist_order_items_dataset.csv", "product_id", "olist_products_dataset.csv", "product_id"),
    ("olist_order_items_dataset.csv", "seller_id", "olist_sellers_dataset.csv", "seller_id"),
    (
        "olist_products_dataset.csv",
        "product_category_name",
        "product_category_name_translation.csv",
        "product_category_name",
    ),
]


def require_source_files() -> None:
    missing = [name for name in EXPECTED_COLUMNS if not (RAW_DIR / name).exists()]
    if missing:
        formatted = "\n".join(f"  - {name}" for name in missing)
        raise SystemExit(
            f"Missing {len(missing)} required file(s) in {RAW_DIR}:\n{formatted}\n"
            "Download the Olist archive from Kaggle, extract it, and rerun this script."
        )


def load_sources() -> dict[str, pd.DataFrame]:
    return {
        name: pd.read_csv(RAW_DIR / name, low_memory=False)
        for name in EXPECTED_COLUMNS
    }


def joined(values: Iterable[str]) -> str:
    return " | ".join(values)


def build_file_profile(frames: dict[str, pd.DataFrame]) -> pd.DataFrame:
    records: list[dict[str, object]] = []
    for name, frame in frames.items():
        expected = EXPECTED_COLUMNS[name]
        missing_columns = [column for column in expected if column not in frame.columns]
        extra_columns = [column for column in frame.columns if column not in expected]
        total_cells = frame.shape[0] * frame.shape[1]
        missing_cells = int(frame.isna().sum().sum())
        records.append(
            {
                "file": name,
                "rows": len(frame),
                "columns": len(frame.columns),
                "exact_duplicate_rows": int(frame.duplicated().sum()),
                "missing_cells": missing_cells,
                "missing_cell_pct": round(100 * missing_cells / total_cells, 4)
                if total_cells
                else 0.0,
                "missing_expected_columns": joined(missing_columns),
                "unexpected_columns": joined(extra_columns),
                "column_check_passed": not missing_columns,
            }
        )
    return pd.DataFrame(records)


def build_column_profile(frames: dict[str, pd.DataFrame]) -> pd.DataFrame:
    records: list[dict[str, object]] = []
    for name, frame in frames.items():
        for column in frame.columns:
            series = frame[column]
            records.append(
                {
                    "file": name,
                    "column": column,
                    "inferred_dtype": str(series.dtype),
                    "rows": len(series),
                    "non_null_rows": int(series.notna().sum()),
                    "missing_rows": int(series.isna().sum()),
                    "missing_pct": round(100 * series.isna().mean(), 4),
                    "distinct_non_null_values": int(series.nunique(dropna=True)),
                }
            )
    return pd.DataFrame(records)


def build_key_checks(frames: dict[str, pd.DataFrame]) -> pd.DataFrame:
    records: list[dict[str, object]] = []
    for name, columns in KEYS.items():
        frame = frames[name]
        if any(column not in frame.columns for column in columns):
            records.append(
                {
                    "file": name,
                    "key_columns": joined(columns),
                    "null_key_rows": None,
                    "duplicate_key_rows": None,
                    "key_check_passed": False,
                    "note": "One or more key columns are missing.",
                }
            )
            continue

        null_key_rows = int(frame[columns].isna().any(axis=1).sum())
        duplicate_key_rows = int(frame.duplicated(subset=columns, keep=False).sum())
        records.append(
            {
                "file": name,
                "key_columns": joined(columns),
                "null_key_rows": null_key_rows,
                "duplicate_key_rows": duplicate_key_rows,
                "key_check_passed": null_key_rows == 0 and duplicate_key_rows == 0,
                "note": "",
            }
        )
    return pd.DataFrame(records)


def build_relationship_checks(frames: dict[str, pd.DataFrame]) -> pd.DataFrame:
    records: list[dict[str, object]] = []
    for child_file, child_column, parent_file, parent_column in RELATIONSHIPS:
        child = frames[child_file]
        parent = frames[parent_file]
        if child_column not in child.columns or parent_column not in parent.columns:
            records.append(
                {
                    "child": f"{child_file}.{child_column}",
                    "parent": f"{parent_file}.{parent_column}",
                    "non_null_child_rows": None,
                    "orphan_rows": None,
                    "orphan_distinct_values": None,
                    "relationship_check_passed": False,
                    "note": "A required relationship column is missing.",
                }
            )
            continue

        child_values = child[child_column].dropna()
        parent_values = set(parent[parent_column].dropna().unique())
        orphan_mask = ~child_values.isin(parent_values)
        records.append(
            {
                "child": f"{child_file}.{child_column}",
                "parent": f"{parent_file}.{parent_column}",
                "non_null_child_rows": len(child_values),
                "orphan_rows": int(orphan_mask.sum()),
                "orphan_distinct_values": int(child_values[orphan_mask].nunique()),
                "relationship_check_passed": not orphan_mask.any(),
                "note": "",
            }
        )
    return pd.DataFrame(records)


def main() -> None:
    require_source_files()
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    frames = load_sources()

    reports = {
        "file_profile.csv": build_file_profile(frames),
        "column_profile.csv": build_column_profile(frames),
        "key_checks.csv": build_key_checks(frames),
        "relationship_checks.csv": build_relationship_checks(frames),
    }

    for filename, report in reports.items():
        report.to_csv(REPORT_DIR / filename, index=False)

    print("Olist source profiling complete.")
    for filename, report in reports.items():
        print(f"  {filename}: {len(report):,} check row(s)")

    file_failures = int((~reports["file_profile.csv"]["column_check_passed"]).sum())
    key_failures = int((~reports["key_checks.csv"]["key_check_passed"]).sum())
    relationship_failures = int(
        (~reports["relationship_checks.csv"]["relationship_check_passed"]).sum()
    )
    print(
        "Review summary: "
        f"{file_failures} file-column failure(s), "
        f"{key_failures} key failure(s), and "
        f"{relationship_failures} relationship failure(s)."
    )


if __name__ == "__main__":
    main()
