"""
Build inventory.db (SQLite) from sql/01_schema.sql and the CSV files in data/.

Run from the project root:
    python scripts/build_db.py
"""
import csv
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "inventory.db"

TABLES = ["suppliers", "products", "stores", "sales", "purchase_orders"]

if DB.exists():
    DB.unlink()

con = sqlite3.connect(DB)
con.executescript((ROOT / "sql" / "01_schema.sql").read_text(encoding="utf-8"))

for table in TABLES:
    with open(ROOT / "data" / f"{table}.csv", newline="", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        placeholders = ",".join("?" * len(header))
        con.executemany(
            f"INSERT INTO {table} ({','.join(header)}) VALUES ({placeholders})", reader
        )

con.commit()

print(f"Built {DB.name}:")
for table in TABLES:
    n = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    print(f"  {table:<16} {n:>7} rows")
con.close()
