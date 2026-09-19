"""Load the public Olist CSV dataset into SQL Server staging tables.

The database schema must be created first with ``01_database_schema.sql``.
This script loads the original CSV files into the existing ``dbo`` tables while
preserving their SQL Server data types.

Example (Windows authentication):

    python load_olist_to_sql.py ^
      --data-dir "C:\\data\\olist" ^
      --server "localhost\\SQLEXPRESS"

Use ``--truncate`` only when you intentionally want to replace existing rows.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
from urllib.parse import quote_plus

import pandas as pd
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine


CSV_TO_TABLE = {
    "olist_customers_dataset.csv": "olist_customers",
    "olist_geolocation_dataset.csv": "olist_geolocation",
    "olist_order_items_dataset.csv": "olist_order_items",
    "olist_order_payments_dataset.csv": "olist_order_payments",
    "olist_order_reviews_dataset.csv": "olist_order_reviews",
    "olist_orders_dataset.csv": "olist_orders",
    "olist_products_dataset.csv": "olist_products",
    "olist_sellers_dataset.csv": "olist_sellers",
    "product_category_name_translation.csv": "product_category_translation",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Load Olist CSV files into the Olist_Portfolio database."
    )
    parser.add_argument(
        "--data-dir",
        type=Path,
        default=os.getenv("OLIST_DATA_DIR"),
        help="Folder containing the nine Olist CSV files (or OLIST_DATA_DIR).",
    )
    parser.add_argument(
        "--server",
        default=os.getenv("SQL_SERVER", r"localhost\SQLEXPRESS"),
        help="SQL Server instance (or SQL_SERVER).",
    )
    parser.add_argument(
        "--database",
        default=os.getenv("SQL_DATABASE", "Olist_Portfolio"),
        help="Target database (or SQL_DATABASE).",
    )
    parser.add_argument(
        "--driver",
        default=os.getenv("SQL_DRIVER", "ODBC Driver 18 for SQL Server"),
        help="Installed ODBC driver (or SQL_DRIVER).",
    )
    parser.add_argument(
        "--truncate",
        action="store_true",
        help="Delete existing rows from each target table before loading.",
    )
    return parser.parse_args()


def build_engine(server: str, database: str, driver: str) -> Engine:
    connection_string = (
        f"DRIVER={{{driver}}};"
        f"SERVER={server};"
        f"DATABASE={database};"
        "Trusted_Connection=yes;"
        "TrustServerCertificate=yes;"
    )
    url = "mssql+pyodbc:///?odbc_connect=" + quote_plus(connection_string)
    return create_engine(url, fast_executemany=True)


def validate_files(data_dir: Path) -> None:
    if not data_dir.is_dir():
        raise FileNotFoundError(f"Dataset folder not found: {data_dir}")

    missing = [name for name in CSV_TO_TABLE if not (data_dir / name).is_file()]
    if missing:
        formatted = "\n  - ".join(missing)
        raise FileNotFoundError(f"Missing CSV files:\n  - {formatted}")


def load_csv(
    engine: Engine,
    csv_path: Path,
    table_name: str,
    truncate: bool,
) -> int:
    frame = pd.read_csv(csv_path, encoding="utf-8", low_memory=False)

    if truncate:
        with engine.begin() as connection:
            connection.execute(text(f"DELETE FROM dbo.[{table_name}]"))

    frame.to_sql(
        name=table_name,
        con=engine,
        schema="dbo",
        if_exists="append",
        index=False,
        chunksize=2_000,
    )

    with engine.connect() as connection:
        total_rows = connection.execute(
            text(f"SELECT COUNT_BIG(*) FROM dbo.[{table_name}]")
        ).scalar_one()

    print(
        f"Loaded {len(frame):>8,} rows from {csv_path.name} "
        f"into dbo.{table_name} ({total_rows:,} total rows)."
    )
    return len(frame)


def main() -> None:
    args = parse_args()
    if args.data_dir is None:
        raise SystemExit(
            "Provide --data-dir or set the OLIST_DATA_DIR environment variable."
        )

    data_dir = args.data_dir.expanduser().resolve()
    validate_files(data_dir)
    engine = build_engine(args.server, args.database, args.driver)

    with engine.connect() as connection:
        connection.execute(text("SELECT 1"))
    print(f"Connected to {args.server} / {args.database}.")

    loaded_rows = 0
    for csv_name, table_name in CSV_TO_TABLE.items():
        loaded_rows += load_csv(
            engine=engine,
            csv_path=data_dir / csv_name,
            table_name=table_name,
            truncate=args.truncate,
        )

    print(f"Load completed successfully: {loaded_rows:,} CSV rows processed.")


if __name__ == "__main__":
    main()
