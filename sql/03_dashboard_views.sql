-- 03_dashboard_views.sql
-- Flat, dashboard-ready views built on top of the base tables.
-- BI tools such as Tableau work best with one wide table per subject area,
-- so the joins and calculated metrics are done here in SQL once.

DROP VIEW IF EXISTS v_sales_enriched;
DROP VIEW IF EXISTS v_po_enriched;
DROP VIEW IF EXISTS v_product_risk;

------------------------------------------------------------------------
-- v_sales_enriched: one row per sales line, with product, store and
-- supplier attributes plus revenue, cost and margin.
------------------------------------------------------------------------
CREATE VIEW v_sales_enriched AS
SELECT
    s.sale_id,
    s.sale_date,
    strftime('%Y-%m', s.sale_date)                       AS sale_month,
    CASE WHEN strftime('%w', s.sale_date) IN ('0', '6')
         THEN 'Weekend' ELSE 'Weekday' END               AS day_type,
    st.store_name,
    p.category,
    p.product_name,
    su.supplier_name,
    s.quantity,
    ROUND(s.quantity * s.unit_price, 2)                  AS revenue,
    ROUND(s.quantity * p.unit_cost, 2)                   AS cost,
    ROUND(s.quantity * (s.unit_price - p.unit_cost), 2)  AS gross_margin
FROM sales s
JOIN products  p  ON p.product_id  = s.product_id
JOIN stores    st ON st.store_id   = s.store_id
JOIN suppliers su ON su.supplier_id = p.supplier_id;

------------------------------------------------------------------------
-- v_po_enriched: one row per purchase order, with delivery KPIs.
------------------------------------------------------------------------
CREATE VIEW v_po_enriched AS
SELECT
    po.po_id,
    po.order_date,
    po.promised_date,
    po.received_date,
    su.supplier_name,
    su.country                                           AS supplier_country,
    p.product_name,
    p.category,
    po.qty_ordered,
    po.qty_received,
    po.qty_ordered - po.qty_received                     AS qty_short,
    ROUND((po.qty_ordered - po.qty_received) * po.unit_cost, 2) AS short_value,
    CAST(julianday(po.received_date) - julianday(po.promised_date) AS INTEGER) AS days_late,
    CASE WHEN po.received_date <= po.promised_date THEN 1 ELSE 0 END AS on_time_flag,
    CAST(julianday(po.received_date) - julianday(po.order_date) AS INTEGER)    AS actual_lead_days
FROM purchase_orders po
JOIN suppliers su ON su.supplier_id = po.supplier_id
JOIN products  p  ON p.product_id   = po.product_id;

------------------------------------------------------------------------
-- v_product_risk: one row per product, comparing lead-time demand with
-- the reorder point (same logic as Q9 in 02_analysis_queries.sql).
------------------------------------------------------------------------
CREATE VIEW v_product_risk AS
WITH demand AS (
    SELECT
        product_id,
        1.0 * SUM(quantity) / (365 * (SELECT COUNT(*) FROM stores)) AS daily_demand_per_store
    FROM sales
    GROUP BY product_id
),
lead AS (
    SELECT
        product_id,
        AVG(julianday(received_date) - julianday(order_date)) AS avg_lead_days
    FROM purchase_orders
    GROUP BY product_id
)
SELECT
    p.product_name,
    p.category,
    su.supplier_name,
    p.reorder_point,
    ROUND(d.daily_demand_per_store, 1)                       AS daily_demand_per_store,
    ROUND(l.avg_lead_days, 1)                                AS avg_lead_days,
    ROUND(d.daily_demand_per_store * l.avg_lead_days, 0)     AS lead_time_demand,
    ROUND(d.daily_demand_per_store * l.avg_lead_days - p.reorder_point, 0) AS shortfall_vs_reorder_point,
    CASE WHEN d.daily_demand_per_store * l.avg_lead_days > p.reorder_point
         THEN 'At risk' ELSE 'OK' END                        AS risk_status
FROM products p
JOIN demand d     ON d.product_id = p.product_id
JOIN lead l       ON l.product_id = p.product_id
JOIN suppliers su ON su.supplier_id = p.supplier_id;
