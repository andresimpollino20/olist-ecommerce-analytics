/*
    Olist E-commerce Analytics
    File: 03_business_analysis_queries.sql

    Portfolio-ready business queries used to validate and reproduce the
    principal insights displayed in Power BI.

    Prerequisite: execute 01_database_schema.sql and
    02_build_analytics_model.sql first.

    Metric convention
    -----------------
    Sales = item price, excluding freight, to match the Power BI dashboard.
    The analytical facts already exclude September and October.
*/

USE [Olist_Portfolio];
GO

SET NOCOUNT ON;
GO

/* =====================================================================
   1. Executive KPIs by month
   ===================================================================== */

SELECT
    YEAR(fs.Order_Date) AS Order_Year,
    MONTH(fs.Order_Date) AS Order_Month,
    CAST(SUM(fs.Price) AS decimal(18,2)) AS Total_Sales,
    COUNT_BIG(*) AS Units_Sold,
    COUNT(DISTINCT fs.Order_ID) AS Total_Orders,
    COUNT(DISTINCT fs.Customer_Unique_ID) AS Unique_Customers,
    CAST(
        SUM(fs.Price) / NULLIF(COUNT(DISTINCT fs.Order_ID), 0)
        AS decimal(18,2)
    ) AS Average_Order_Value
FROM analytics.Fact_Sales AS fs
GROUP BY
    YEAR(fs.Order_Date),
    MONTH(fs.Order_Date)
ORDER BY
    Order_Year,
    Order_Month;
GO

/* =====================================================================
   2. Monthly sales and year-over-year comparison
   A self-join is used instead of LAG(12) because September and October
   are intentionally excluded from the analytical period.
   ===================================================================== */

;WITH MonthlySales AS
(
    SELECT
        YEAR(Order_Date) AS Order_Year,
        MONTH(Order_Date) AS Order_Month,
        SUM(Price) AS Total_Sales
    FROM analytics.Fact_Sales
    GROUP BY
        YEAR(Order_Date),
        MONTH(Order_Date)
)
SELECT
    current_period.Order_Year,
    current_period.Order_Month,
    CAST(current_period.Total_Sales AS decimal(18,2)) AS Current_Year_Sales,
    CAST(previous_period.Total_Sales AS decimal(18,2)) AS Previous_Year_Sales,
    CAST(
        100.0 * (current_period.Total_Sales - previous_period.Total_Sales)
        / NULLIF(previous_period.Total_Sales, 0)
        AS decimal(10,2)
    ) AS Sales_YoY_Percent
FROM MonthlySales AS current_period
LEFT JOIN MonthlySales AS previous_period
    ON previous_period.Order_Year = current_period.Order_Year - 1
   AND previous_period.Order_Month = current_period.Order_Month
ORDER BY
    current_period.Order_Year,
    current_period.Order_Month;
GO

/* =====================================================================
   3. Product-category performance
   ===================================================================== */

SELECT
    COALESCE(dp.Grupo_Categoria, 'UNCATEGORIZED') AS Product_Category,
    CAST(SUM(fs.Price) AS decimal(18,2)) AS Total_Sales,
    COUNT_BIG(*) AS Units_Sold,
    COUNT(DISTINCT fs.Order_ID) AS Total_Orders,
    CAST(AVG(fs.Price) AS decimal(18,2)) AS Average_Price,
    CAST(
        100.0 * SUM(fs.Price) / NULLIF(SUM(SUM(fs.Price)) OVER (), 0)
        AS decimal(10,2)
    ) AS Sales_Share_Percent
FROM analytics.Fact_Sales AS fs
LEFT JOIN analytics.Dim_Product AS dp
    ON fs.Product_ID = dp.Product_ID
GROUP BY
    COALESCE(dp.Grupo_Categoria, 'UNCATEGORIZED')
ORDER BY
    Total_Sales DESC;
GO

/* =====================================================================
   4. Customer distribution by purchase frequency
   ===================================================================== */

;WITH CustomerOrders AS
(
    SELECT
        fo.Customer_Unique_ID,
        COUNT(DISTINCT fo.Order_ID) AS Order_Count
    FROM analytics.Fact_Orders AS fo
    GROUP BY fo.Customer_Unique_ID
),
FrequencyGroups AS
(
    SELECT
        Customer_Unique_ID,
        Order_Count,
        CASE
            WHEN Order_Count = 1 THEN '1 order'
            WHEN Order_Count = 2 THEN '2 orders'
            WHEN Order_Count = 3 THEN '3 orders'
            ELSE '4+ orders'
        END AS Purchase_Frequency,
        CASE
            WHEN Order_Count = 1 THEN 1
            WHEN Order_Count = 2 THEN 2
            WHEN Order_Count = 3 THEN 3
            ELSE 4
        END AS Sort_Order
    FROM CustomerOrders
)
SELECT
    Purchase_Frequency,
    COUNT_BIG(*) AS Unique_Customers
FROM FrequencyGroups
GROUP BY
    Purchase_Frequency,
    Sort_Order
ORDER BY
    Sort_Order;
GO

/* =====================================================================
   5. Customer segmentation
   Occasional = 1 order; Repeat = 2; Frequent = 3; Loyal = 4 or more.
   ===================================================================== */

;WITH CustomerOrders AS
(
    SELECT
        fo.Customer_Unique_ID,
        COUNT(DISTINCT fo.Order_ID) AS Order_Count
    FROM analytics.Fact_Orders AS fo
    GROUP BY fo.Customer_Unique_ID
),
Segments AS
(
    SELECT
        Customer_Unique_ID,
        CASE
            WHEN Order_Count <= 1 THEN 'Occasional'
            WHEN Order_Count = 2 THEN 'Repeat'
            WHEN Order_Count = 3 THEN 'Frequent'
            ELSE 'Loyal'
        END AS Customer_Segment
    FROM CustomerOrders
)
SELECT
    Customer_Segment,
    COUNT_BIG(*) AS Unique_Customers,
    CAST(
        100.0 * COUNT_BIG(*) / NULLIF(SUM(COUNT_BIG(*)) OVER (), 0)
        AS decimal(10,2)
    ) AS Customer_Share_Percent
FROM Segments
GROUP BY Customer_Segment
ORDER BY Unique_Customers DESC;
GO

/* =====================================================================
   6. Top 10 customers by sales
   Customer_Name is a reproducible pseudonymous label; the source dataset
   does not contain actual customer names.
   ===================================================================== */

SELECT TOP (10)
    MAX(dc.Customer_Name) AS Customer_Name,
    fs.Customer_Unique_ID,
    CAST(SUM(fs.Price) AS decimal(18,2)) AS Total_Sales,
    COUNT(DISTINCT fs.Order_ID) AS Total_Orders,
    COUNT_BIG(*) AS Units_Purchased,
    CAST(
        SUM(fs.Price) / NULLIF(COUNT(DISTINCT fs.Order_ID), 0)
        AS decimal(18,2)
    ) AS Average_Order_Value
FROM analytics.Fact_Sales AS fs
LEFT JOIN analytics.Dim_Customer AS dc
    ON fs.Customer_ID = dc.Customer_ID
GROUP BY fs.Customer_Unique_ID
ORDER BY
    Total_Sales DESC,
    fs.Customer_Unique_ID;
GO

/* =====================================================================
   7. Operations summary
   ===================================================================== */

SELECT
    COUNT(DISTINCT fo.Order_ID) AS Total_Orders,
    COUNT(DISTINCT CASE
        WHEN fo.Delivered_Customer_Date IS NOT NULL THEN fo.Order_ID
    END) AS Delivered_Orders,
    CAST(AVG(CASE
        WHEN fo.Delivered_Customer_Date IS NOT NULL
        THEN 1.0 * fo.Delivery_Days
    END) AS decimal(10,2)) AS Average_Delivery_Days,
    CAST(
        100.0 * COUNT(DISTINCT CASE
            WHEN fo.Delivered_Customer_Date IS NOT NULL
             AND fo.Is_Late_Delivery = 0 THEN fo.Order_ID
        END)
        / NULLIF(COUNT(DISTINCT CASE
            WHEN fo.Delivered_Customer_Date IS NOT NULL THEN fo.Order_ID
        END), 0)
        AS decimal(10,2)
    ) AS On_Time_Delivery_Percent,
    CAST(AVG(CASE
        WHEN fo.Delivery_Delay_Days > 0
        THEN 1.0 * fo.Delivery_Delay_Days
    END) AS decimal(10,2)) AS Average_Delay_Days
FROM analytics.Fact_Orders AS fo;
GO

/* =====================================================================
   8. Top 5 states by number of on-time deliveries
   ===================================================================== */

SELECT TOP (5)
    dc.Customer_State,
    COUNT(DISTINCT fo.Order_ID) AS Delivered_Orders,
    COUNT(DISTINCT CASE
        WHEN fo.Is_Late_Delivery = 0 THEN fo.Order_ID
    END) AS On_Time_Deliveries,
    CAST(
        100.0 * COUNT(DISTINCT CASE
            WHEN fo.Is_Late_Delivery = 0 THEN fo.Order_ID
        END) / NULLIF(COUNT(DISTINCT fo.Order_ID), 0)
        AS decimal(10,2)
    ) AS On_Time_Delivery_Percent
FROM analytics.Fact_Orders AS fo
LEFT JOIN analytics.Dim_Customer AS dc
    ON fo.Customer_ID = dc.Customer_ID
WHERE fo.Delivered_Customer_Date IS NOT NULL
GROUP BY dc.Customer_State
ORDER BY
    On_Time_Deliveries DESC,
    dc.Customer_State;
GO

/* =====================================================================
   9. Monthly delivery-time evolution
   ===================================================================== */

SELECT
    YEAR(fo.Order_Date) AS Order_Year,
    MONTH(fo.Order_Date) AS Order_Month,
    COUNT(DISTINCT fo.Order_ID) AS Delivered_Orders,
    CAST(AVG(1.0 * fo.Delivery_Days) AS decimal(10,2))
        AS Average_Delivery_Days,
    CAST(
        100.0 * COUNT(DISTINCT CASE
            WHEN fo.Is_Late_Delivery = 0 THEN fo.Order_ID
        END) / NULLIF(COUNT(DISTINCT fo.Order_ID), 0)
        AS decimal(10,2)
    ) AS On_Time_Delivery_Percent
FROM analytics.Fact_Orders AS fo
WHERE fo.Delivered_Customer_Date IS NOT NULL
GROUP BY
    YEAR(fo.Order_Date),
    MONTH(fo.Order_Date)
ORDER BY
    Order_Year,
    Order_Month;
GO

/* =====================================================================
   10. Logistics performance by state
   ===================================================================== */

SELECT
    dc.Customer_State,
    COUNT(DISTINCT fo.Order_ID) AS Delivered_Orders,
    CAST(AVG(1.0 * fo.Delivery_Days) AS decimal(10,2))
        AS Average_Delivery_Days,
    CAST(
        100.0 * COUNT(DISTINCT CASE
            WHEN fo.Is_Late_Delivery = 0 THEN fo.Order_ID
        END) / NULLIF(COUNT(DISTINCT fo.Order_ID), 0)
        AS decimal(10,2)
    ) AS On_Time_Delivery_Percent,
    CAST(
        100.0 * COUNT(DISTINCT CASE
            WHEN fo.Is_Late_Delivery = 1 THEN fo.Order_ID
        END) / NULLIF(COUNT(DISTINCT fo.Order_ID), 0)
        AS decimal(10,2)
    ) AS Late_Delivery_Percent,
    CAST(AVG(CASE
        WHEN fo.Delivery_Delay_Days > 0
        THEN 1.0 * fo.Delivery_Delay_Days
    END) AS decimal(10,2)) AS Average_Delay_Days
FROM analytics.Fact_Orders AS fo
LEFT JOIN analytics.Dim_Customer AS dc
    ON fo.Customer_ID = dc.Customer_ID
WHERE fo.Delivered_Customer_Date IS NOT NULL
GROUP BY dc.Customer_State
ORDER BY Delivered_Orders DESC;
GO

/* =====================================================================
   11. Basic data-quality checks
   Each result should be zero after a successful model build.
   ===================================================================== */

SELECT
    'Duplicate order IDs in Fact_Orders' AS Check_Name,
    COUNT_BIG(*) AS Issue_Count
FROM
(
    SELECT Order_ID
    FROM analytics.Fact_Orders
    GROUP BY Order_ID
    HAVING COUNT_BIG(*) > 1
) AS duplicate_orders
UNION ALL
SELECT
    'Null order dates in Fact_Orders',
    COUNT_BIG(*)
FROM analytics.Fact_Orders
WHERE Order_Date IS NULL
UNION ALL
SELECT
    'Sales rows without a matching product',
    COUNT_BIG(*)
FROM analytics.Fact_Sales AS fs
LEFT JOIN analytics.Dim_Product AS dp
    ON fs.Product_ID = dp.Product_ID
WHERE dp.Product_ID IS NULL
UNION ALL
SELECT
    'Sales rows without a matching customer',
    COUNT_BIG(*)
FROM analytics.Fact_Sales AS fs
LEFT JOIN analytics.Dim_Customer AS dc
    ON fs.Customer_ID = dc.Customer_ID
WHERE dc.Customer_ID IS NULL;
GO
