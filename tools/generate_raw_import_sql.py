#!/usr/bin/env python3
"""
Generate sql/02_import_raw_data.sql from data/raw/spotify_tracks.csv.

This utility is included for transparency. It is not required when running the
SQL project in MySQL Workbench, because the generated SQL import file is already
included in the repository.

The source CSV has a blank first header column, originally created by pandas as
an exported index. The SQL staging table stores that column as source_row_id.

Run from the project root, for example:

    python3 tools/generate_raw_import_sql.py
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path
from typing import Iterable, List, TextIO

SQL_COLUMNS = [
    "source_row_id",
    "track_id",
    "artists",
    "album_name",
    "track_name",
    "popularity",
    "duration_ms",
    "explicit",
    "danceability",
    "energy",
    "`key`",
    "loudness",
    "mode",
    "speechiness",
    "acousticness",
    "instrumentalness",
    "liveness",
    "valence",
    "tempo",
    "time_signature",
    "track_genre",
]

EXPECTED_CSV_COLUMNS = [
    "",
    "track_id",
    "artists",
    "album_name",
    "track_name",
    "popularity",
    "duration_ms",
    "explicit",
    "danceability",
    "energy",
    "key",
    "loudness",
    "mode",
    "speechiness",
    "acousticness",
    "instrumentalness",
    "liveness",
    "valence",
    "tempo",
    "time_signature",
    "track_genre",
]


def sql_literal(value: str | None) -> str:
    """Return a MySQL-safe SQL literal for a CSV cell."""
    if value is None or value == "":
        return "NULL"
    value = value.replace("\\", "\\\\").replace("'", "''")
    value = value.replace("\r", " ").replace("\n", " ")
    return f"'{value}'"


def source_row_literal(value: str) -> str:
    """Validate and return the source row index as an unquoted integer literal."""
    if value == "":
        raise ValueError("The first CSV column is empty for a data row; expected source row index.")
    try:
        return str(int(value))
    except ValueError as exc:
        raise ValueError(f"Invalid source row index: {value!r}") from exc


def row_to_values(row: List[str]) -> str:
    """Convert one CSV row into a parenthesised SQL VALUES tuple."""
    cells = [source_row_literal(row[0])] + [sql_literal(cell) for cell in row[1:]]
    return "(" + ", ".join(cells) + ")"


def chunks(items: Iterable[str], batch_size: int) -> Iterable[List[str]]:
    """Yield lists of at most batch_size items."""
    batch: List[str] = []
    for item in items:
        batch.append(item)
        if len(batch) == batch_size:
            yield batch
            batch = []
    if batch:
        yield batch


def write_header(out: TextIO) -> None:
    """Write the SQL import file header and setup statements."""
    out.write("-- ============================================================\n")
    out.write("-- 02_import_raw_data.sql\n")
    out.write("-- Spotify Track Positioning Analytics\n")
    out.write("-- MySQL 8.0 / MySQL Workbench\n")
    out.write("-- ============================================================\n")
    out.write("-- Purpose:\n")
    out.write("--   Load the raw Spotify source data into raw_spotify_tracks using\n")
    out.write("--   generated INSERT statements derived from data/raw/spotify_tracks.csv.\n")
    out.write("--   The first CSV column is mapped to source_row_id.\n")
    out.write("--\n")
    out.write("-- Run order:\n")
    out.write("--   1. sql/01_schema.sql\n")
    out.write("--   2. sql/02_import_raw_data.sql\n")
    out.write("--   3. sql/03_data.sql\n")
    out.write("--   4. sql/04_eda.sql\n")
    out.write("-- ============================================================\n\n")
    out.write("USE spotify_track_positioning;\n\n")
    out.write("SET NAMES utf8mb4;\n")
    out.write("SET FOREIGN_KEY_CHECKS = 0;\n\n")
    out.write("TRUNCATE TABLE raw_spotify_tracks;\n\n")
    out.write("START TRANSACTION;\n\n")


def write_insert_batch(out: TextIO, batch: List[str]) -> None:
    """Write one batched INSERT statement."""
    column_block = ",\n    ".join(SQL_COLUMNS)
    out.write("INSERT INTO raw_spotify_tracks (\n")
    out.write(f"    {column_block}\n")
    out.write(") VALUES\n")
    out.write(",\n".join(batch))
    out.write(";\n\n")


def write_footer(out: TextIO) -> None:
    """Write transaction close and final import-count check."""
    out.write("COMMIT;\n\n")
    out.write("SET FOREIGN_KEY_CHECKS = 1;\n\n")
    out.write("SELECT COUNT(*) AS raw_rows_after_insert FROM raw_spotify_tracks;\n")


def generate_sql(input_csv: Path, output_sql: Path, batch_size: int) -> int:
    """Generate a batched INSERT script and return the number of rows written."""
    if batch_size <= 0:
        raise ValueError("batch_size must be a positive integer.")

    row_count = 0
    output_sql.parent.mkdir(parents=True, exist_ok=True)

    with input_csv.open("r", encoding="utf-8", newline="") as f, output_sql.open(
        "w", encoding="utf-8", newline="\n"
    ) as out:
        reader = csv.reader(f)
        header = next(reader)
        if header != EXPECTED_CSV_COLUMNS:
            raise ValueError(
                "Unexpected CSV header.\n"
                f"Expected: {EXPECTED_CSV_COLUMNS}\n"
                f"Found:    {header}"
            )

        write_header(out)

        batch: List[str] = []
        for csv_line_number, row in enumerate(reader, start=2):
            if len(row) != len(EXPECTED_CSV_COLUMNS):
                raise ValueError(
                    f"Unexpected number of columns in CSV line {csv_line_number}: {len(row)}"
                )
            batch.append(row_to_values(row))
            row_count += 1
            if len(batch) == batch_size:
                write_insert_batch(out, batch)
                batch = []

        if batch:
            write_insert_batch(out, batch)

        write_footer(out)

    return row_count


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate MySQL INSERT import script from Spotify CSV.")
    parser.add_argument(
        "--input",
        type=Path,
        default=Path("data/raw/spotify_tracks.csv"),
        help="Path to the source CSV, relative to the project root by default.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("sql/02_import_raw_data.sql"),
        help="Path for the generated SQL import file, relative to the project root by default.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=500,
        help="Number of rows per INSERT statement.",
    )
    args = parser.parse_args()

    rows = generate_sql(args.input, args.output, args.batch_size)
    print(f"Generated {args.output} with {rows:,} rows from {args.input}.")


if __name__ == "__main__":
    main()
