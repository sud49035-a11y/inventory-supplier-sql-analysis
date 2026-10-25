"""
Create the dashboard views in inventory.db and export them as CSV files
for Tableau / Power BI / Excel.

Run from the project root (after scripts/build_db.py):
    python scripts/export_dashboard_data.py

Outputs: dashboard/data/sales_enriched.csv
         dashboard/data/purchase_orders_enriched.csv
         dashboard/data/product_risk.csv
"""
import csv
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "inventory.db"
OUT = ROOT / "dashboard" / "data"
OUT.mkdir(parents=True, exist_ok=True)

if not DB.exists():
    raise SystemExit("inventory.db not found. Run: python scripts/build_db.py")

con = sqlite3.connect(DB)
con.executescript((ROOT / "sql" / "03_dashboard_views.sql").read_text(encoding="utf-8"))

EXPORTS = {
    "v_sales_enriched": "sales_enriched.csv",
    "v_po_enriched": "purchase_orders_enriched.csv",
    "v_product_risk": "product_risk.csv",
}

for view, filename in EXPORTS.items():
    cur = con.execute(f"SELECT * FROM {view}")
    columns = [d[0] for d in cur.description]
    with open(OUT / filename, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(columns)
        n = 0
        for row in cur:
            writer.writerow(row)
            n += 1
    print(f"{filename:<32} {n:>6} rows")

con.close()
