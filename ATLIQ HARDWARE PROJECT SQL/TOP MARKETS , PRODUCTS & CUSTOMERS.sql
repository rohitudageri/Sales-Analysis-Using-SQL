# PROBLEM 1
# Q1) To Generate report for individual product sale for croma india customer for FY = 2021 having fields
-- MONTH
-- PRODUCT NAME
-- VARIANT
-- SOLD QUANTITY
-- GROSS PRICE PER ITEM
-- GROSS PRICE TOTAL

SELECT fs.date,fs.product_code,
        dp.product , dp.variant,
        fg.gross_price,
        fg.gross_price * fs.sold_quantity as gross_price_total
FROM fact_sales_monthly fs
INNER JOIN dim_product dp
ON dp.product_code = fs.product_code
INNER JOIN 	fact_gross_price fg
ON fg.product_code = fs.product_code and
   fg.fiscal_year = get_fiscal_year(fs.date)
WHERE customer_code = "90002002" and 
      get_fiscal_year(date) = 2021 ;
      
      
# PROBLEM 2
# Q2) To Generate aggregated monthly gross sale report for croma india customer
-- MONTH
-- Total gross sale amount 

SELECT  fs.date,
         SUM(fg.gross_price * fs.sold_quantity )as total_gross_price
FROM fact_sales_monthly fs
INNER JOIN fact_gross_price fg
ON fg.product_code = fs.product_code and
    fg.fiscal_year = get_fiscal_year(fs.date)
WHERE customer_code = "90002002"
GROUP BY fs.date ;


# PROBLEM 3
-- Q3) Create a store procedure that can determine market badge based on 
-- if total_qty_sold > 5 million than it is GOLD else SILVER

CREATE  PROCEDURE `get_market_badge`(
IN enter_market CHAR(45),
IN enter_fiscal_year YEAR,
OUT badge CHAR(10)
)
BEGIN

DECLARE sold_qty INT DEFAULT 0;

CASE 
 WHEN enter_market = "" THEN 
  SET enter_market = "INDIA" ;
END CASE;

SELECT 
        SUM(fs.sold_quantity) into sold_qty
FROM fact_sales_monthly fs
INNER JOIN dim_customer dc
ON dc.customer_code = fs.customer_code
WHERE dc.market = enter_market and
      get_fiscal_year(fs.date) = enter_fiscal_year
GROUP BY  dc.market ; 

CASE 
  WHEN  sold_qty >5000000  THEN SET badge = "GOLD";
  ELSE SET badge = "SILVER";
END CASE;
END


# PROBLEM 4
-- Q4) Generate a report for top markets , top products and top customer by net sales

-- 1) to optimize the execution time we created new table as dim_date , because while execution date is being repeated for 1.4 million 

SELECT fs.date,
       (fg.gross_price * fs.sold_quantity ) total_gross_price,
       pre.pre_invoice_discount_pct
FROM fact_sales_monthly fs
INNER JOIN dim_date dt
      ON dt.calendar_date = fs.date
INNER JOIN fact_gross_price fg
      ON fs.product_code = fg.product_code and
         fg.fiscal_year = dt.fiscal_year
INNER JOIN fact_pre_invoice_deductions pre
      ON pre.customer_code = fs.customer_code and
		 pre.fiscal_year = dt.fiscal_year
WHERE dt.fiscal_year= 2021 ;
   
   
-- 2) we can also optimize this by directly creating a new column in fact_Sales_monthly table , yes it may increase the storage as for dim_date table we have only 74 rows i.e, = 74bytes but in facts_table we will have 1.4 million new row 
-- BUT STORAGE IS NOT AN ISSUE , By this we dont require to join the dim_date table


SELECT fs.date,
       (fg.gross_price * fs.sold_quantity ) total_gross_price,
       pre.pre_invoice_discount_pct
FROM fact_sales_monthly fs
INNER JOIN fact_gross_price fg
      ON fs.product_code = fg.product_code and
         fg.fiscal_year = fs.fiscal_year
INNER JOIN fact_pre_invoice_deductions pre
      ON pre.customer_code = fs.customer_code and
		 pre.fiscal_year = fs.fiscal_year
WHERE fs.fiscal_year= 2021 ;


-- CREATED view for till sales_pre_invocie

SELECT sales.date ,sales.fiscal_year,
        (1 - pre_invoice_discount_pct)*total_gross_price as net_invoice_sales,
         (post.discounts_pct + post.other_deductions_pct ) as total_post_discount
FROM sale_pre_inv_discount as sales
INNER JOIN fact_post_invoice_deductions as post
ON post.customer_code = sales.customer_code and
   post.product_code = sales.product_code and
   post.date = sales.date  ; 
   
   -- CREATED view for post_invoice_deduction

SELECT * ,
        (1-total_post_discount )* net_invoice_sales as Net_sales
FROM post_invoice_deduction ;
   
   
   -- CREATED Net_Sales View
   
   SELECT * FROM net_sales ;
   

-- 1) TOP MARKETS

   SELECT market,
          ROUND(sum(net_sales)/1000000,2) as Net_sales_million
   FROM net_sales
   WHERE fiscal_year = 2021
   GROUP BY market 
   ORDER BY Net_sales_million DESC
   LIMIT 5;

-- 2) TOP CUSTOMERS
SELECT customer,market,
       ROUND(sum(net_sales)/1000000,2) as Net_sales_million
FROM net_sales
WHERE fiscal_year = 2021 and market = "INDIA"
GROUP BY customer , market
ORDER BY Net_sales_million DESC
LIMIT 5 ;

-- 3) TOP PRODUCTS

SELECT product,market,
       ROUND(sum(net_sales)/1000000,2) as Net_sales_million
FROM net_sales ns
INNER JOIN dim_product dp
ON ns.product_code = dp.product_code
WHERE fiscal_year = 2021 and market = "INDIA"
GROUP BY product,market
ORDER BY Net_sales_million
LIMIT 5;


#  PROBLEM 5
-- Q5) Create a bar chart report for FY=2021 for TOP 10 markets by % net sales


WITH CTE AS (
SELECT  customer,
       ROUND(sum(net_sales)/1000000,2) as Net_sales_million
FROM net_sales 
WHERE fiscal_year = 2021
  GROUP BY customer
 )
SELECT *,
            Net_sales_million * 100/SUM(Net_sales_million) over() as net_sales_million_pct
 FROM CTE
ORDER BY Net_sales_million DESC ; 


#  PROBLEM 6
-- Q6) Company wants to see region wise(APAC,EU,LATAM) % Net sales breakdown by customer in respective region.
-- end of result should be bar chart for FY = 2021

WITH CTE AS (
SELECT  dc.customer,dc.region,
       ROUND(sum(net_sales)/1000000,2) as Net_sales_million
FROM net_sales ns
INNER JOIN dim_customer dc
ON dc.customer_code = ns.customer_code
WHERE fiscal_year = 2021
  GROUP BY dc.customer,dc.region
 )
SELECT *,
            Net_sales_million * 100/SUM(Net_sales_million) over(partition by region) as net_sales_share_pct
 FROM CTE
ORDER BY region,Net_sales_million DESC ; 



#  PROBLEM 7
-- Q7) Get top n products in each division by their quantity sold.alter

WITH CTE1 AS(
SELECT dp.division,
       dp.product,
      sum(fs.sold_quantity) as total_sold_qty
FROM fact_sales_monthly fs
INNER JOIN dim_product dp
ON dp.product_code = fs.product_code
WHERE fiscal_year = 2021 
GROUP BY dp.division,dp.product
),
CTE2 AS(
SELECT *,
        dense_rank() over(partition by division order by total_sold_qty DESC) as den_rnk
FROM  CTE1)
SELECT * FROM CTE2
WHERE den_rnk <=3 ;



#  PROBLEM 8
-- Q8) Retrieve the top 2 markets in every region by their gross sales amount in FY=2021. i.e. result should look something like this,

WITH CTE1 AS(
SELECT dc.region,
	 dc.market,
     ROUND(SUM(fg.gross_price * fs.sold_quantity)/1000000,2) as gross_price_million
FROM fact_sales_monthly fs
INNER JOIN dim_customer dc
ON fs.customer_code = dc.customer_code
INNER JOIN fact_gross_price fg
ON fs.product_code = fg.product_code and
   fs.fiscal_year = fg.fiscal_year
WHERE fs.fiscal_year = 2021
GROUP BY dc.market,dc.region ),
CTE2 AS (
SELECT *,
       dense_rank() over(partition by region order by gross_price_million DESC) as dn_rnk
FROM CTE1)
SELECT * FROM CTE2 
WHERE dn_rnk <= 2 ;
