-- 01_schema.sql
-- Creates the tables for the inventory & supplier performance database (SQLite).

DROP TABLE IF EXISTS sales;
DROP TABLE IF EXISTS purchase_orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS stores;
DROP TABLE IF EXISTS suppliers;

CREATE TABLE suppliers (
    supplier_id             INTEGER PRIMARY KEY,
    supplier_name           TEXT NOT NULL,
    country                 TEXT,
    standard_lead_time_days INTEGER
);

CREATE TABLE products (
    product_id    INTEGER PRIMARY KEY,
    product_name  TEXT NOT NULL,
    category      TEXT NOT NULL,
    supplier_id   INTEGER NOT NULL REFERENCES suppliers(supplier_id),
    unit_cost     REAL NOT NULL,
    unit_price    REAL NOT NULL,
    reorder_point INTEGER
);

CREATE TABLE stores (
    store_id   INTEGER PRIMARY KEY,
    store_name TEXT NOT NULL,
    city       TEXT
);

CREATE TABLE sales (
    sale_id    INTEGER PRIMARY KEY,
    sale_date  TEXT NOT NULL,              -- ISO format YYYY-MM-DD
    store_id   INTEGER NOT NULL REFERENCES stores(store_id),
    product_id INTEGER NOT NULL REFERENCES products(product_id),
    quantity   INTEGER NOT NULL,
    unit_price REAL NOT NULL
);

CREATE TABLE purchase_orders (
    po_id         INTEGER PRIMARY KEY,
    order_date    TEXT NOT NULL,
    product_id    INTEGER NOT NULL REFERENCES products(product_id),
    supplier_id   INTEGER NOT NULL REFERENCES suppliers(supplier_id),
    qty_ordered   INTEGER NOT NULL,
    promised_date TEXT NOT NULL,
    received_date TEXT NOT NULL,
    qty_received  INTEGER NOT NULL,
    unit_cost     REAL NOT NULL
);

CREATE INDEX idx_sales_date    ON sales(sale_date);
CREATE INDEX idx_sales_product ON sales(product_id);
CREATE INDEX idx_po_supplier   ON purchase_orders(supplier_id);
