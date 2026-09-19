# Key DAX measures

This document records the main Power BI measures used in the Olist E-commerce Analytics dashboard. Keeping the logic in the repository makes the model easier to audit, reproduce, and explain during a portfolio presentation.

## Model assumptions

- `Dim_Date[Date]` has an active one-to-many relationship with `Fact_Sales[Order_Date]` and `Fact_Orders[Order_Date]`.
- `Dim_Customer`, `Dim_Product`, and `Dim_Seller` filter their respective fact tables through their keys.
- Sales represent item price and exclude freight, matching the dashboard.
- `Fact_Sales` has one row per order item; `Fact_Orders` has one row per order.
- September and October are excluded upstream by the SQL transformation script.

## Executive KPIs

```DAX
Total Sales =
SUM ( Fact_Sales[Price] )
```

```DAX
Units Sold =
COUNTROWS ( Fact_Sales )
```

```DAX
Total Orders =
DISTINCTCOUNT ( Fact_Orders[Order_ID] )
```

```DAX
Sales Orders =
DISTINCTCOUNT ( Fact_Sales[Order_ID] )
```

```DAX
Unique Customers =
DISTINCTCOUNT ( Fact_Orders[Customer_Unique_ID] )
```

```DAX
Average Order Value =
DIVIDE ( [Total Sales], [Sales Orders] )
```

```DAX
Sales per Customer =
DIVIDE ( [Total Sales], [Unique Customers] )
```

```DAX
Orders per Customer =
DIVIDE ( [Total Orders], [Unique Customers] )
```

```DAX
Average Price =
DIVIDE ( [Total Sales], [Units Sold] )
```

## Previous-year comparisons

These measures require a continuous date table marked as the model's date table.

```DAX
Sales Previous Year =
CALCULATE (
    [Total Sales],
    SAMEPERIODLASTYEAR ( Dim_Date[Date] )
)
```

```DAX
Sales YoY % =
DIVIDE (
    [Total Sales] - [Sales Previous Year],
    [Sales Previous Year]
)
```

```DAX
Sales YoY Indicator =
VAR ChangeValue = [Sales YoY %]
RETURN
    IF (
        ISBLANK ( ChangeValue ),
        BLANK (),
        IF ( ChangeValue >= 0, "▲ ", "▼ " )
            & FORMAT ( ABS ( ChangeValue ), "0.0%" )
    )
```

```DAX
Sales YoY Color =
VAR ChangeValue = [Sales YoY %]
RETURN
    SWITCH (
        TRUE (),
        ISBLANK ( ChangeValue ), "#6B7280",
        ChangeValue >= 0, "#16A34A",
        "#DC2626"
    )
```

```DAX
Units Previous Year =
CALCULATE (
    [Units Sold],
    SAMEPERIODLASTYEAR ( Dim_Date[Date] )
)
```

```DAX
Units YoY % =
DIVIDE (
    [Units Sold] - [Units Previous Year],
    [Units Previous Year]
)
```

```DAX
Units YoY Indicator =
VAR ChangeValue = [Units YoY %]
RETURN
    IF (
        ISBLANK ( ChangeValue ),
        BLANK (),
        IF ( ChangeValue >= 0, "▲ ", "▼ " )
            & FORMAT ( ABS ( ChangeValue ), "0.0%" )
    )
```

```DAX
Unique Customers Previous Year =
CALCULATE (
    [Unique Customers],
    SAMEPERIODLASTYEAR ( Dim_Date[Date] )
)
```

```DAX
Unique Customers YoY % =
DIVIDE (
    [Unique Customers] - [Unique Customers Previous Year],
    [Unique Customers Previous Year]
)
```

```DAX
Unique Customers YoY Indicator =
VAR ChangeValue = [Unique Customers YoY %]
RETURN
    IF (
        ISBLANK ( ChangeValue ),
        BLANK (),
        IF ( ChangeValue >= 0, "▲ ", "▼ " )
            & FORMAT ( ABS ( ChangeValue ), "0.0%" )
    )
```

```DAX
Average Order Value Previous Year =
CALCULATE (
    [Average Order Value],
    SAMEPERIODLASTYEAR ( Dim_Date[Date] )
)
```

```DAX
Average Order Value YoY % =
DIVIDE (
    [Average Order Value] - [Average Order Value Previous Year],
    [Average Order Value Previous Year]
)
```

```DAX
Average Order Value YoY Indicator =
VAR ChangeValue = [Average Order Value YoY %]
RETURN
    IF (
        ISBLANK ( ChangeValue ),
        BLANK (),
        IF ( ChangeValue >= 0, "▲ ", "▼ " )
            & FORMAT ( ABS ( ChangeValue ), "0.0%" )
    )
```

## Operations KPIs

```DAX
Delivered Orders =
CALCULATE (
    [Total Orders],
    NOT ISBLANK ( Fact_Orders[Delivered_Customer_Date] )
)
```

```DAX
Average Delivery Time =
CALCULATE (
    AVERAGE ( Fact_Orders[Delivery_Days] ),
    NOT ISBLANK ( Fact_Orders[Delivered_Customer_Date] )
)
```

```DAX
On-Time Deliveries =
CALCULATE (
    [Delivered Orders],
    Fact_Orders[Is_Late_Delivery] = 0
)
```

```DAX
On-Time Delivery Rate =
DIVIDE ( [On-Time Deliveries], [Delivered Orders] )
```

```DAX
Late Deliveries =
CALCULATE (
    [Delivered Orders],
    Fact_Orders[Is_Late_Delivery] = 1
)
```

```DAX
Late Delivery Rate =
DIVIDE ( [Late Deliveries], [Delivered Orders] )
```

```DAX
Average Delay =
CALCULATE (
    AVERAGE ( Fact_Orders[Delivery_Delay_Days] ),
    Fact_Orders[Delivery_Delay_Days] > 0
)
```

```DAX
Average Delivery Time Previous Year =
CALCULATE (
    [Average Delivery Time],
    SAMEPERIODLASTYEAR ( Dim_Date[Date] )
)
```

```DAX
On-Time Delivery Rate Previous Year =
CALCULATE (
    [On-Time Delivery Rate],
    SAMEPERIODLASTYEAR ( Dim_Date[Date] )
)
```

## Customer segmentation helper column

If the segmentation is not loaded from SQL, this calculated column can be created in `Dim_Customer`:

```DAX
Customer Segment EN =
SWITCH (
    Dim_Customer[Customer_Category],
    "Ocasional", "Occasional",
    "Recurrente", "Repeat",
    "Frecuente", "Frequent",
    "Leal", "Loyal",
    Dim_Customer[Customer_Category]
)
```

## Suggested formatting

| Measure | Format |
|---|---|
| Total Sales | Currency (BRL), display units in millions |
| Average Order Value, Sales per Customer, Average Price | Currency (BRL), 2 decimals |
| Units Sold, Total Orders, Delivered Orders, Unique Customers | Whole number |
| YoY measures and delivery rates | Percentage, 1 decimal |
| Average Delivery Time and Average Delay | Decimal number, 2 decimals |

For conditional formatting, use `#16A34A` for positive performance, `#DC2626` for negative performance, and `#6B7280` when no comparison is available.
