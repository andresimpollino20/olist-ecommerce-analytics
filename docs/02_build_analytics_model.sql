/*
    Olist E-commerce Analytics
    File: 02_build_analytics_model.sql

    Purpose
    -------
    1. Standardize the original dbo tables into the stg schema.
    2. Build the dimensions and fact tables used by Power BI.
    3. Calculate delivery duration, delay, and late-delivery flags.

    Prerequisite: run 01_database_schema.sql and load the original CSV files
    into the dbo tables before executing this script.

    Data scope: September and October are excluded from the analytical facts
    to keep the dashboard comparison period consistent.
*/

USE [Olist_Portfolio];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg');
IF SCHEMA_ID('analytics') IS NULL EXEC('CREATE SCHEMA analytics');
GO

BEGIN TRY
    BEGIN TRANSACTION;

    /* ================================================================
       1. Clear existing transformed data
       ================================================================ */

    DELETE FROM analytics.Fact_Sales;
    DELETE FROM analytics.Fact_Orders;
    DELETE FROM analytics.Dim_Seller;
    DELETE FROM analytics.Dim_Product;
    DELETE FROM analytics.Dim_Customer;
    DELETE FROM analytics.Dim_Real_Customer;

    DELETE FROM stg.Reviews;
    DELETE FROM stg.Payments;
    DELETE FROM stg.Order_Items;
    DELETE FROM stg.Orders;
    DELETE FROM stg.Products;
    DELETE FROM stg.Sellers;
    DELETE FROM stg.Customers;

    /* ================================================================
       2. Raw tables (dbo) -> standardized staging tables (stg)
       ================================================================ */

    INSERT INTO stg.Customers
    (
        Customer_ID,
        Customer_Unique_ID,
        Customer_Zip_Code,
        Customer_City,
        Customer_State
    )
    SELECT DISTINCT
        CONVERT(varchar(32), customer_id),
        CONVERT(varchar(32), customer_unique_id),
        TRY_CONVERT(int, customer_zip_code_prefix),
        CONVERT(varchar(100), LOWER(LTRIM(RTRIM(customer_city)))),
        CONVERT(varchar(2), UPPER(LTRIM(RTRIM(customer_state))))
    FROM dbo.olist_customers
    WHERE NULLIF(LTRIM(RTRIM(customer_id)), '') IS NOT NULL;

    INSERT INTO stg.Orders
    (
        Order_ID,
        Customer_ID,
        Order_Status,
        Order_Purchase_Date,
        Order_Approved_Date,
        Order_Delivered_Carrier_Date,
        Order_Delivered_Customer_Date,
        Order_Estimated_Delivery_Date
    )
    SELECT DISTINCT
        CONVERT(varchar(32), order_id),
        CONVERT(varchar(32), customer_id),
        CONVERT(varchar(30), LOWER(LTRIM(RTRIM(order_status)))),
        TRY_CONVERT(datetime2, order_purchase_timestamp),
        TRY_CONVERT(datetime2, order_approved_at),
        TRY_CONVERT(datetime2, order_delivered_carrier_date),
        TRY_CONVERT(datetime2, order_delivered_customer_date),
        TRY_CONVERT(datetime2, order_estimated_delivery_date)
    FROM dbo.olist_orders
    WHERE NULLIF(LTRIM(RTRIM(order_id)), '') IS NOT NULL;

    INSERT INTO stg.Order_Items
    (
        Order_ID,
        Order_Item_ID,
        Product_ID,
        Seller_ID,
        Shipping_Limit_Date,
        Price,
        Freight_Value
    )
    SELECT
        CONVERT(varchar(32), order_id),
        TRY_CONVERT(int, order_item_id),
        CONVERT(varchar(32), product_id),
        CONVERT(varchar(32), seller_id),
        TRY_CONVERT(datetime2, shipping_limit_date),
        TRY_CONVERT(decimal(18,2), price),
        TRY_CONVERT(decimal(18,2), freight_value)
    FROM dbo.olist_order_items
    WHERE NULLIF(LTRIM(RTRIM(order_id)), '') IS NOT NULL;

    INSERT INTO stg.Payments
    (
        Order_ID,
        Payment_Sequential,
        Payment_Type,
        Payment_Installments,
        Payment_Value
    )
    SELECT
        CONVERT(varchar(32), order_id),
        TRY_CONVERT(int, payment_sequential),
        CONVERT(varchar(30), LOWER(LTRIM(RTRIM(payment_type)))),
        TRY_CONVERT(int, payment_installments),
        TRY_CONVERT(decimal(18,2), payment_value)
    FROM dbo.olist_order_payments
    WHERE NULLIF(LTRIM(RTRIM(order_id)), '') IS NOT NULL;

    INSERT INTO stg.Products
    (
        Product_ID,
        Product_Category_PT,
        Product_Category,
        Product_Name_Length,
        Product_Description_Length,
        Product_Photos_Qty,
        Product_Weight_G,
        Product_Length_CM,
        Product_Height_CM,
        Product_Width_CM
    )
    SELECT
        CONVERT(varchar(32), p.product_id),
        CONVERT(varchar(100), p.product_category_name),
        CONVERT(varchar(100), COALESCE(t.product_category_name_english, 'uncategorized')),
        TRY_CONVERT(int, p.product_name_lenght),
        TRY_CONVERT(int, p.product_description_lenght),
        TRY_CONVERT(int, p.product_photos_qty),
        TRY_CONVERT(int, p.product_weight_g),
        TRY_CONVERT(int, p.product_length_cm),
        TRY_CONVERT(int, p.product_height_cm),
        TRY_CONVERT(int, p.product_width_cm)
    FROM dbo.olist_products AS p
    LEFT JOIN dbo.product_category_translation AS t
        ON p.product_category_name = t.product_category_name
    WHERE NULLIF(LTRIM(RTRIM(p.product_id)), '') IS NOT NULL;

    INSERT INTO stg.Sellers
    (
        Seller_ID,
        Seller_Zip_Code,
        Seller_City,
        Seller_State
    )
    SELECT DISTINCT
        CONVERT(varchar(32), seller_id),
        TRY_CONVERT(int, seller_zip_code_prefix),
        CONVERT(varchar(100), LOWER(LTRIM(RTRIM(seller_city)))),
        CONVERT(varchar(2), UPPER(LTRIM(RTRIM(seller_state))))
    FROM dbo.olist_sellers
    WHERE NULLIF(LTRIM(RTRIM(seller_id)), '') IS NOT NULL;

    INSERT INTO stg.Reviews
    (
        Review_ID,
        Order_ID,
        Review_Score,
        Review_Comment_Title,
        Review_Comment_Message,
        Review_Creation_Date,
        Review_Answer_Date
    )
    SELECT
        CONVERT(varchar(32), review_id),
        CONVERT(varchar(32), order_id),
        TRY_CONVERT(int, review_score),
        CONVERT(varchar(255), LEFT(review_comment_title, 255)),
        CONVERT(varchar(1000), LEFT(review_comment_message, 1000)),
        TRY_CONVERT(datetime2, review_creation_date),
        TRY_CONVERT(datetime2, review_answer_timestamp)
    FROM dbo.olist_order_reviews
    WHERE NULLIF(LTRIM(RTRIM(order_id)), '') IS NOT NULL;

    /* ================================================================
       3. Analytical dimensions
       ================================================================ */

    ;WITH RealCustomer AS
    (
        SELECT
            c.*,
            ROW_NUMBER() OVER
            (
                PARTITION BY c.Customer_Unique_ID
                ORDER BY c.Customer_ID
            ) AS RowNumber
        FROM stg.Customers AS c
    )
    INSERT INTO analytics.Dim_Real_Customer
    (
        Customer_Unique_ID,
        Customer_ID,
        Customer_Zip_Code,
        Customer_City,
        Customer_State
    )
    SELECT
        Customer_Unique_ID,
        Customer_ID,
        Customer_Zip_Code,
        Customer_City,
        Customer_State
    FROM RealCustomer
    WHERE RowNumber = 1;

    ;WITH CustomerOrders AS
    (
        SELECT
            c.Customer_Unique_ID,
            COUNT(DISTINCT o.Order_ID) AS Order_Count
        FROM stg.Customers AS c
        LEFT JOIN stg.Orders AS o
            ON c.Customer_ID = o.Customer_ID
           AND MONTH(o.Order_Purchase_Date) NOT IN (9, 10)
        GROUP BY c.Customer_Unique_ID
    )
    INSERT INTO analytics.Dim_Customer
    (
        Customer_ID,
        Customer_Unique_ID,
        Customer_Zip_Code,
        Customer_City,
        Customer_State,
        Customer_Name,
        Customer_Category
    )
    SELECT
        c.Customer_ID,
        c.Customer_Unique_ID,
        c.Customer_Zip_Code,
        c.Customer_City,
        c.Customer_State,
        CONCAT('Customer ', UPPER(LEFT(c.Customer_Unique_ID, 8))) AS Customer_Name,
        CASE
            WHEN COALESCE(co.Order_Count, 0) <= 1 THEN 'Occasional'
            WHEN co.Order_Count = 2 THEN 'Repeat'
            WHEN co.Order_Count = 3 THEN 'Frequent'
            ELSE 'Loyal'
        END AS Customer_Category
    FROM stg.Customers AS c
    LEFT JOIN CustomerOrders AS co
        ON c.Customer_Unique_ID = co.Customer_Unique_ID;

    INSERT INTO analytics.Dim_Product
    (
        Product_ID,
        Product_Category_PT,
        Product_Category,
        Product_Name_Length,
        Product_Description_Length,
        Product_Photos_Qty,
        Product_Weight_G,
        Product_Length_CM,
        Product_Height_CM,
        Product_Width_CM,
        Categoria_Castellano,
        Grupo_Categoria
    )
    SELECT
        Product_ID,
        Product_Category_PT,
        Product_Category,
        Product_Name_Length,
        Product_Description_Length,
        Product_Photos_Qty,
        Product_Weight_G,
        Product_Length_CM,
        Product_Height_CM,
        Product_Width_CM,
        NULL AS Categoria_Castellano,
        UPPER(REPLACE(COALESCE(Product_Category, 'uncategorized'), '_', ' '))
            AS Grupo_Categoria
    FROM stg.Products;

    INSERT INTO analytics.Dim_Seller
    (
        Seller_ID,
        Seller_Zip_Code,
        Seller_City,
        Seller_State
    )
    SELECT
        Seller_ID,
        Seller_Zip_Code,
        Seller_City,
        Seller_State
    FROM stg.Sellers;

    /* ================================================================
       4. Analytical facts
       ================================================================ */

    INSERT INTO analytics.Fact_Orders
    (
        Order_ID,
        Customer_ID,
        Customer_Unique_ID,
        Order_Date,
        Order_Status,
        Approved_Date,
        Delivered_Carrier_Date,
        Delivered_Customer_Date,
        Estimated_Delivery_Date,
        Delivery_Days,
        Delivery_Delay_Days,
        Is_Late_Delivery
    )
    SELECT
        o.Order_ID,
        o.Customer_ID,
        c.Customer_Unique_ID,
        CONVERT(date, o.Order_Purchase_Date),
        o.Order_Status,
        CONVERT(date, o.Order_Approved_Date),
        CONVERT(date, o.Order_Delivered_Carrier_Date),
        CONVERT(date, o.Order_Delivered_Customer_Date),
        CONVERT(date, o.Order_Estimated_Delivery_Date),
        CASE
            WHEN o.Order_Delivered_Customer_Date IS NOT NULL
            THEN DATEDIFF(day, o.Order_Purchase_Date, o.Order_Delivered_Customer_Date)
        END AS Delivery_Days,
        CASE
            WHEN o.Order_Delivered_Customer_Date > o.Order_Estimated_Delivery_Date
            THEN DATEDIFF(day, o.Order_Estimated_Delivery_Date, o.Order_Delivered_Customer_Date)
            ELSE 0
        END AS Delivery_Delay_Days,
        CASE
            WHEN o.Order_Delivered_Customer_Date > o.Order_Estimated_Delivery_Date THEN 1
            ELSE 0
        END AS Is_Late_Delivery
    FROM stg.Orders AS o
    LEFT JOIN stg.Customers AS c
        ON o.Customer_ID = c.Customer_ID
    WHERE MONTH(o.Order_Purchase_Date) NOT IN (9, 10);

    INSERT INTO analytics.Fact_Sales
    (
        Order_ID,
        Order_Item_ID,
        Customer_ID,
        Customer_Unique_ID,
        Product_ID,
        Seller_ID,
        Order_Date,
        Order_Status,
        Price,
        Freight_Value,
        Total_Order_Item_Value
    )
    SELECT
        oi.Order_ID,
        oi.Order_Item_ID,
        o.Customer_ID,
        c.Customer_Unique_ID,
        oi.Product_ID,
        oi.Seller_ID,
        CONVERT(date, o.Order_Purchase_Date),
        o.Order_Status,
        oi.Price,
        oi.Freight_Value,
        COALESCE(oi.Price, 0) + COALESCE(oi.Freight_Value, 0)
            AS Total_Order_Item_Value
    FROM stg.Order_Items AS oi
    INNER JOIN stg.Orders AS o
        ON oi.Order_ID = o.Order_ID
    LEFT JOIN stg.Customers AS c
        ON o.Customer_ID = c.Customer_ID
    WHERE MONTH(o.Order_Purchase_Date) NOT IN (9, 10);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* Final row-count validation */
SELECT 'analytics.Dim_Customer' AS Table_Name, COUNT_BIG(*) AS Row_Count
FROM analytics.Dim_Customer
UNION ALL
SELECT 'analytics.Dim_Product', COUNT_BIG(*) FROM analytics.Dim_Product
UNION ALL
SELECT 'analytics.Dim_Seller', COUNT_BIG(*) FROM analytics.Dim_Seller
UNION ALL
SELECT 'analytics.Fact_Orders', COUNT_BIG(*) FROM analytics.Fact_Orders
UNION ALL
SELECT 'analytics.Fact_Sales', COUNT_BIG(*) FROM analytics.Fact_Sales;
GO
