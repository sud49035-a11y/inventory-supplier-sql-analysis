"""
Generate a small, reproducible synthetic dataset for a retail grocery
inventory & supplier performance analysis.

Run from the project root:
    python scripts/generate_data.py

Outputs CSV files into data/.
All data is synthetic (random seed fixed) - no real company data is used.
"""
import csv
import random
from datetime import date, timedelta
from pathlib import Path

random.seed(42)

OUT = Path(__file__).resolve().parent.parent / "data"
OUT.mkdir(exist_ok=True)

START = date(2025, 1, 1)
END = date(2025, 12, 31)

# ---------- suppliers ----------
supplier_names = [
    ("Maple Valley Foods", "Canada"),
    ("Nordic Grain Co", "Germany"),
    ("Sunrise Beverages", "Canada"),
    ("Alpine Snacks GmbH", "Germany"),
    ("Pacific Pantry Ltd", "USA"),
    ("Golden Harvest", "Canada"),
    ("EuroBake Supply", "Netherlands"),
    ("FreshLine Distributors", "USA"),
]
# each supplier has a "reliability profile": (avg promised lead days, chance of delay, chance of short shipment)
profiles = {
    1: (5, 0.10, 0.05),
    2: (7, 0.25, 0.10),
    3: (4, 0.08, 0.04),
    4: (8, 0.35, 0.15),
    5: (10, 0.30, 0.12),
    6: (6, 0.15, 0.06),
    7: (9, 0.40, 0.20),
    8: (5, 0.12, 0.08),
}
suppliers = [
    (i + 1, n, c, profiles[i + 1][0]) for i, (n, c) in enumerate(supplier_names)
]

# ---------- products ----------
categories = {
    "Pasta & Grains": ["Spaghetti 500g", "Penne 500g", "Basmati Rice 2kg", "Rolled Oats 1kg", "Couscous 500g"],
    "Canned Goods": ["Diced Tomatoes 400g", "Chickpeas 400g", "Black Beans 400g", "Tuna Chunks 170g", "Sweet Corn 340g"],
    "Snacks": ["Salted Chips 200g", "Pretzels 250g", "Granola Bar 6pk", "Mixed Nuts 300g", "Rice Crackers 150g"],
    "Beverages": ["Orange Juice 1L", "Sparkling Water 6pk", "Green Tea 20bags", "Ground Coffee 500g", "Oat Drink 1L"],
    "Baking": ["Flour 2kg", "Sugar 1kg", "Baking Powder 100g", "Chocolate Chips 300g", "Vanilla Extract 50ml"],
}
products = []
pid = 1
for cat, names in categories.items():
    for n in names:
        cost = round(random.uniform(0.6, 6.0), 2)
        price = round(cost * random.uniform(1.25, 1.8), 2)
        supplier_id = random.randint(1, len(suppliers))
        products.append((pid, n, cat, supplier_id, cost, price, random.choice([60, 100, 150, 200])))
        pid += 1
# columns: product_id, product_name, category, supplier_id, unit_cost, unit_price, reorder_point

# ---------- stores ----------
stores = [
    (1, "Downtown", "Berlin"),
    (2, "Prenzlauer Berg", "Berlin"),
    (3, "Kreuzberg", "Berlin"),
    (4, "Charlottenburg", "Berlin"),
]

# ---------- sales (daily, per store per product) ----------
def seasonal(d, category):
    f = 1.0
    if category == "Beverages" and d.month in (6, 7, 8):
        f *= 1.4
    if category == "Baking" and d.month in (11, 12):
        f *= 1.6
    if category == "Snacks" and d.month in (11, 12):
        f *= 1.25
    if d.weekday() >= 5:
        f *= 1.2
    return f

sales = []
sale_id = 1
d = START
while d <= END:
    for s in stores:
        for p in products:
            base = {1: 14, 2: 11, 3: 9, 4: 7}[s[0]] * (1 + (p[0] % 5) * 0.15)
            qty = max(0, int(random.gauss(base * seasonal(d, p[2]), base * 0.35)))
            if qty == 0 or random.random() < 0.15:
                continue  # not every product sells every day at every store
            sales.append((sale_id, d.isoformat(), s[0], p[0], qty, p[5]))
            sale_id += 1
    d += timedelta(days=1)

# ---------- purchase orders ----------
pos = []
po_id = 1
for p in products:
    sup = p[3]
    lead, p_delay, p_short = profiles[sup]
    order_date = START + timedelta(days=random.randint(0, 10))
    while order_date <= END - timedelta(days=15):
        qty_ordered = random.choice([300, 500, 800, 1000])
        promised = order_date + timedelta(days=lead)
        delayed = random.random() < p_delay
        actual = promised + timedelta(days=random.randint(1, 8)) if delayed else promised - timedelta(days=random.choice([0, 0, 1]))
        short = random.random() < p_short
        qty_received = int(qty_ordered * random.uniform(0.75, 0.95)) if short else qty_ordered
        pos.append((po_id, order_date.isoformat(), p[0], sup, qty_ordered,
                    promised.isoformat(), actual.isoformat(), qty_received, p[4]))
        po_id += 1
        order_date += timedelta(days=random.randint(21, 35))

# ---------- write CSVs ----------
def write(name, header, rows):
    with open(OUT / name, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)

write("suppliers.csv", ["supplier_id", "supplier_name", "country", "standard_lead_time_days"], suppliers)
write("products.csv", ["product_id", "product_name", "category", "supplier_id", "unit_cost", "unit_price", "reorder_point"], products)
write("stores.csv", ["store_id", "store_name", "city"], stores)
write("sales.csv", ["sale_id", "sale_date", "store_id", "product_id", "quantity", "unit_price"], sales)
write("purchase_orders.csv", ["po_id", "order_date", "product_id", "supplier_id", "qty_ordered",
                              "promised_date", "received_date", "qty_received", "unit_cost"], pos)

print(f"suppliers={len(suppliers)} products={len(products)} stores={len(stores)} "
      f"sales={len(sales)} purchase_orders={len(pos)}")
