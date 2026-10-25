-- 02_analysis_queries.sql
-- Business questions answered with SQL (SQLite dialect).
-- Run in DB Browser for SQLite / DBeaver (one query at a time), or:
--   sqlite3 -header -column inventory.db < sql/02_analysis_queries.sql


------------------------------------------------------------------------
-- Q1. Data sanity check: row counts, date range, and obvious data issues
------------------------------------------------------------------------
SELECT 'Q1 sanity check' AS query;

SELECT
    COUNT(*)                                        AS sales_rows,
    MIN(sale_date)                                  AS first_sale,
    MAX(sale_date)                                  AS last_sale,
    SUM(CASE WHEN quantity <= 0 THEN 1 ELSE 0 END)  AS non_positive_qty,
    SUM(CASE WHEN unit_price IS NULL THEN 1 ELSE 0 END) AS null_prices
FROM sales;

------------------------------------------------------------------------
-- Q2. Revenue, gross margin and margin % by product category
--     Skills: JOIN, GROUP BY, calculated columns
------------------------------------------------------------------------
SELECT 'Q2 revenue and margin by category' AS query;

SELECT
    p.category,
    SUM(s.quantity)                                          AS units_sold,
    ROUND(SUM(s.quantity * s.unit_price), 0)                 AS revenue,
    ROUND(SUM(s.quantity * (s.unit_price - p.unit_cost)), 0) AS gross_margin,
    ROUND(100.0 * SUM(s.quantity * (s.unit_price - p.unit_cost))
          / SUM(s.quantity * s.unit_price), 1)               AS margin_pct
FROM sales s
JOIN products p ON p.product_id = s.product_id
GROUP BY p.category
ORDER BY revenue DESC;

------------------------------------------------------------------------
-- Q3. Monthly revenue with month-over-month growth
--     Skills: CTE, LAG() window function, strftime
------------------------------------------------------------------------
SELECT 'Q3 monthly revenue and MoM growth' AS query;

WITH monthly AS (
    SELECT
        strftime('%Y-%m', sale_date)      AS month,
        SUM(quantity * unit_price)        AS revenue
    FROM sales
    GROUP BY 1
)
SELECT
    month,
    ROUND(revenue, 0) AS revenue,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
          / LAG(revenue) OVER (ORDER BY month), 1) AS mom_growth_pct
FROM monthly
ORDER BY month;

------------------------------------------------------------------------
-- Q4. Top 3 products by revenue within each category
--     Skills: RANK() with PARTITION BY, subquery filtering
------------------------------------------------------------------------
SELECT 'Q4 top 3 products per category' AS query;

SELECT category, product_name, revenue, rank_in_category
FROM (
    SELECT
        p.category,
        p.product_name,
        ROUND(SUM(s.quantity * s.unit_price), 0) AS revenue,
        RANK() OVER (PARTITION BY p.category
                     ORDER BY SUM(s.quantity * s.unit_price) DESC) AS rank_in_category
    FROM sales s
    JOIN products p ON p.product_id = s.product_id
    GROUP BY p.category, p.product_name
)
WHERE rank_in_category <= 3
ORDER BY category, rank_in_category;

------------------------------------------------------------------------
-- Q5. Store performance and share of total revenue
--     Skills: window aggregate over the whole result set
------------------------------------------------------------------------
SELECT 'Q5 store performance' AS query;

SELECT
    st.store_name,
    ROUND(SUM(s.quantity * s.unit_price), 0) AS revenue,
    ROUND(100.0 * SUM(s.quantity * s.unit_price)
          / SUM(SUM(s.quantity * s.unit_price)) OVER (), 1) AS revenue_share_pct
FROM sales s
JOIN stores st ON st.store_id = s.store_id
GROUP BY st.store_name
ORDER BY revenue DESC;

------------------------------------------------------------------------
-- Q6. ABC analysis: which products drive 80% of revenue?
--     A = first 80% of cumulative revenue, B = next 15%, C = last 5%
--     Skills: running total with SUM() OVER, CASE
------------------------------------------------------------------------
SELECT 'Q6 ABC classification' AS query;

WITH product_revenue AS (
    SELECT
        p.product_id,
        p.product_name,
        SUM(s.quantity * s.unit_price) AS revenue
    FROM sales s
    JOIN products p ON p.product_id = s.product_id
    GROUP BY p.product_id, p.product_name
),
cumulative AS (
    SELECT
        product_name,
        revenue,
        SUM(revenue) OVER (ORDER BY revenue DESC
                           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
            / SUM(revenue) OVER () AS cum_share
    FROM product_revenue
)
SELECT
    product_name,
    ROUND(revenue, 0)          AS revenue,
    ROUND(100 * cum_share, 1)  AS cumulative_pct,
    CASE
        WHEN cum_share <= 0.80 THEN 'A'
        WHEN cum_share <= 0.95 THEN 'B'
        ELSE 'C'
    END AS abc_class
FROM cumulative
ORDER BY revenue DESC;

------------------------------------------------------------------------
-- Q7. Supplier scorecard: on-time rate, fill rate, average delay
--     Skills: CASE inside aggregates, julianday() date math, RANK()
--     On-time = received on or before promised date.
--     Fill rate = units received / units ordered.
------------------------------------------------------------------------
SELECT 'Q7 supplier scorecard' AS query;

WITH po_flags AS (
    SELECT
        supplier_id,
        qty_ordered,
        qty_received,
        julianday(received_date) - julianday(promised_date) AS days_late,
        CASE WHEN received_date <= promised_date THEN 1 ELSE 0 END AS on_time
    FROM purchase_orders
)
SELECT
    su.supplier_name,
    su.country,
    COUNT(*)                                             AS po_count,
    ROUND(100.0 * AVG(f.on_time), 1)                     AS on_time_pct,
    ROUND(100.0 * SUM(f.qty_received) / SUM(f.qty_ordered), 1) AS fill_rate_pct,
    ROUND(AVG(CASE WHEN f.days_late > 0 THEN f.days_late END), 1) AS avg_days_late_when_late,
    RANK() OVER (ORDER BY AVG(f.on_time) DESC)           AS reliability_rank
FROM po_flags f
JOIN suppliers su ON su.supplier_id = f.supplier_id
GROUP BY su.supplier_id, su.supplier_name, su.country
ORDER BY reliability_rank;

------------------------------------------------------------------------
-- Q8. Purchase price variance and cost of short shipments by supplier
--     (value of units ordered but never received)
------------------------------------------------------------------------
SELECT 'Q8 unfilled order value by supplier' AS query;

SELECT
    su.supplier_name,
    SUM(po.qty_ordered - po.qty_received)                        AS units_short,
    ROUND(SUM((po.qty_ordered - po.qty_received) * po.unit_cost), 0) AS short_shipment_value,
    SUM(CASE WHEN po.qty_received < po.qty_ordered THEN 1 ELSE 0 END) AS short_po_count
FROM purchase_orders po
JOIN suppliers su ON su.supplier_id = po.supplier_id
GROUP BY su.supplier_name
ORDER BY short_shipment_value DESC;

------------------------------------------------------------------------
-- Q9. Reorder point check: is lead-time demand higher than the reorder point?
--     Average daily demand per store x average actual lead time.
--     Products where lead-time demand exceeds the reorder point are at
--     stock-out risk.
--     Skills: multiple CTEs, joining aggregates, derived metrics
------------------------------------------------------------------------
SELECT 'Q9 reorder point risk' AS query;

WITH demand AS (
    SELECT
        product_id,
        1.0 * SUM(quantity) / (365 * (SELECT COUNT(*) FROM stores)) AS avg_daily_demand_per_store
    FROM sales
    GROUP BY product_id
),
lead AS (
    SELECT
        product_id,
        AVG(julianday(received_date) - julianday(order_date)) AS avg_actual_lead_days
    FROM purchase_orders
    GROUP BY product_id
)
SELECT
    p.product_name,
    su.supplier_name,
    p.reorder_point,
    ROUND(d.avg_daily_demand_per_store, 1)                    AS daily_demand_per_store,
    ROUND(l.avg_actual_lead_days, 1)                          AS avg_lead_days,
    ROUND(d.avg_daily_demand_per_store * l.avg_actual_lead_days, 0) AS lead_time_demand,
    CASE
        WHEN d.avg_daily_demand_per_store * l.avg_actual_lead_days > p.reorder_point
        THEN 'AT RISK' ELSE 'OK'
    END AS status
FROM products p
JOIN demand d    ON d.product_id = p.product_id
JOIN lead l      ON l.product_id = p.product_id
JOIN suppliers su ON su.supplier_id = p.supplier_id
ORDER BY (d.avg_daily_demand_per_store * l.avg_actual_lead_days - p.reorder_point) DESC;

------------------------------------------------------------------------
-- Q10. Seasonality index by category: monthly units vs the category's
--      own monthly average (1.00 = average month)
--      Skills: CTE, AVG() OVER (PARTITION BY ...)
------------------------------------------------------------------------
SELECT 'Q10 seasonality index (peak month per category)' AS query;

WITH cat_month AS (
    SELECT
        p.category,
        strftime('%m', s.sale_date) AS month,
        SUM(s.quantity)             AS units
    FROM sales s
    JOIN products p ON p.product_id = s.product_id
    GROUP BY p.category, strftime('%m', s.sale_date)
),
indexed AS (
    SELECT
        category,
        month,
        units,
        ROUND(1.0 * units / AVG(units) OVER (PARTITION BY category), 2) AS seasonality_index,
        RANK() OVER (PARTITION BY category ORDER BY units DESC) AS rnk
    FROM cat_month
)
SELECT category, month AS peak_month, units, seasonality_index
FROM indexed
WHERE rnk = 1
ORDER BY seasonality_index DESC;

------------------------------------------------------------------------
-- Q11. Weekend vs weekday sales per day, by store
--      strftime('%w') returns 0 = Sunday ... 6 = Saturday
------------------------------------------------------------------------
SELECT 'Q11 weekend vs weekday' AS query;

WITH daily AS (
    SELECT
        store_id,
        sale_date,
        CASE WHEN strftime('%w', sale_date) IN ('0', '6') THEN 'Weekend' ELSE 'Weekday' END AS day_type,
        SUM(quantity * unit_price) AS revenue
    FROM sales
    GROUP BY store_id, sale_date
)
SELECT
    st.store_name,
    d.day_type,
    ROUND(AVG(d.revenue), 0) AS avg_daily_revenue
FROM daily d
JOIN stores st ON st.store_id = d.store_id
GROUP BY st.store_name, d.day_type
ORDER BY st.store_name, d.day_type;
