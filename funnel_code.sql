#Database creation
CREATE DATABASE funnel_project;
USE funnel_project;

CREATE TABLE events (
    event_id INT PRIMARY KEY,
    session_id INT NOT NULL,
    timestamp DATETIME NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    product_id INT,
    qty INT,
    cart_size INT,
    payment VARCHAR(50),
    discount_pct FLOAT,
    amount_usd FLOAT
);

CREATE TABLE sessions (
    session_id INT PRIMARY KEY,
    customer_id INT NOT NULL,
    start_time DATETIME NOT NULL,
    device VARCHAR(50),
    source VARCHAR(50),
    country VARCHAR(10)
);

CREATE TABLE customers (
    customer_id INT PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100),
    country VARCHAR(10),
    age INT,
    signup_date VARCHAR(20),
    marketing_opt_in BOOLEAN
);

CREATE TABLE orders (
    order_id INT PRIMARY KEY,
    customer_id INT NOT NULL,
    order_time VARCHAR(30),
    payment_method VARCHAR(50),
    discount_pct FLOAT,
    amount FLOAT,
    final_amount FLOAT,
    country VARCHAR(10),
    device VARCHAR(50),
    source VARCHAR(50)
);

SHOW VARIABLES LIKE 'local_infile';
#Enabling local file import
SET GLOBAL local_infile = 1;

#importing events data
LOAD DATA LOCAL INFILE 'C:/dataf/events.csv'
INTO TABLE events
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(event_id, session_id, timestamp, event_type, product_id, qty, cart_size, payment, discount_pct, amount_usd);

#importing sessions data
LOAD DATA LOCAL INFILE 'C:/dataf/sessions.csv'
INTO TABLE sessions
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(session_id, customer_id, start_time, device, source, country);

#importing customers data
LOAD DATA LOCAL INFILE 'C:/dataf/customers.csv'
INTO TABLE customers
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(customer_id, name, email, country, age, signup_date, marketing_opt_in);

UPDATE customers 
SET 
    signup_date = CASE
        WHEN signup_date LIKE '__-__-____' THEN STR_TO_DATE(signup_date, '%d-%m-%Y')
        WHEN signup_date LIKE '____-__-__' THEN STR_TO_DATE(signup_date, '%Y-%m-%d')
        ELSE NULL
    END;

ALTER TABLE customers
MODIFY signup_date DATE;

#importing orders data
LOAD DATA LOCAL INFILE 'C:/dataf/orders.csv'
INTO TABLE orders
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(order_id, customer_id, order_time, payment_method, discount_pct, amount, final_amount, country, device, source);

UPDATE orders 
SET 
    order_time = CASE
        WHEN order_time LIKE '____-__-__T%' THEN STR_TO_DATE(order_time, '%Y-%m-%dT%H:%i:%s')
        WHEN order_time LIKE '____-__-__ %' THEN STR_TO_DATE(order_time, '%Y-%m-%d %H:%i:%s')
        WHEN order_time LIKE '__-__-____ %' THEN STR_TO_DATE(order_time, '%d-%m-%Y %H:%i:%s')
        ELSE NULL
    END
WHERE
    order_id IS NOT NULL;

ALTER TABLE orders
MODIFY order_time DATETIME;


              ---#Conversion Rates---
              
WITH funnel AS (
    SELECT
        event_type,
        COUNT(DISTINCT session_id) AS users,
        CASE
            WHEN event_type = 'page_view'   THEN 1
            WHEN event_type = 'add_to_cart' THEN 2
            WHEN event_type = 'checkout'    THEN 3
            WHEN event_type = 'purchase'    THEN 4
        END AS funnel_order
    FROM events
    GROUP BY event_type
)
SELECT
    event_type,
    users,
    ROUND(
    users * 100.0 / NULLIF(LAG(users) OVER (ORDER BY funnel_order), 0),
2) AS conversion_rate
FROM funnel
ORDER BY funnel_order;
    

            ---#Drop-off Analysis---
            
WITH funnel AS (
    SELECT
        event_type,
        COUNT(DISTINCT session_id) AS users,
        CASE
            WHEN event_type = 'page_view'   THEN 1
            WHEN event_type = 'add_to_cart' THEN 2
            WHEN event_type = 'checkout'    THEN 3
            WHEN event_type = 'purchase'    THEN 4
        END AS funnel_order
    FROM events
    GROUP BY event_type
),
funnel_lag AS (
    SELECT
        event_type,
        users,
        funnel_order,
        LAG(users) OVER (ORDER BY funnel_order) AS prev_users
    FROM funnel
)
SELECT
    event_type,
    users,
    prev_users,
    (prev_users - users) AS drop_off,
    ROUND((prev_users - users) * 100.0 / NULLIF(prev_users,0), 2)    AS drop_pct
FROM funnel_lag
ORDER BY funnel_order;

          ---#Device_Wise Funnel---

WITH device_funnel AS (
    SELECT 
        s.device,
        e.event_type,
        COUNT(DISTINCT e.session_id) AS users,
        CASE 
            WHEN e.event_type = 'page_view'   THEN 1
            WHEN e.event_type = 'add_to_cart' THEN 2
            WHEN e.event_type = 'checkout'    THEN 3
            WHEN e.event_type = 'purchase'    THEN 4
        END AS funnel_order
    FROM events e
    JOIN sessions s ON e.session_id = s.session_id
    GROUP BY s.device, e.event_type
)
SELECT device, event_type, users
FROM device_funnel
ORDER BY device, funnel_order;

      ---#Conversion rates per device---
SELECT 
    s.device,

    COUNT(DISTINCT CASE 
        WHEN e.event_type = 'page_view' THEN e.session_id 
    END) AS page_views,

    COUNT(DISTINCT CASE 
        WHEN e.event_type = 'purchase' THEN e.session_id 
    END) AS purchases,

    ROUND(
        COUNT(DISTINCT CASE 
            WHEN e.event_type = 'purchase' THEN e.session_id 
        END) * 100.0
        /
        NULLIF(COUNT(DISTINCT CASE 
            WHEN e.event_type = 'page_view' THEN e.session_id 
        END),0),
    2) AS conversion_rate

FROM events e
JOIN sessions s 
ON e.session_id = s.session_id

GROUP BY s.device
ORDER BY conversion_rate DESC;

      ---#source_wise funnel---
      
WITH funnel AS (
    SELECT 
        s.source,  
        e.event_type,
        COUNT(DISTINCT e.session_id) AS users,
        CASE 
            WHEN e.event_type = 'page_view' THEN 1
            WHEN e.event_type = 'add_to_cart' THEN 2
            WHEN e.event_type = 'checkout' THEN 3
            WHEN e.event_type = 'purchase' THEN 4
        END AS funnel_order
    FROM events e
    JOIN sessions s ON e.session_id = s.session_id
    GROUP BY s.source, e.event_type
)
SELECT source, event_type, users
FROM funnel
ORDER BY source, funnel_order;   
    
        ---#Conversion rates per source---
SELECT 
    s.source,
    COUNT(DISTINCT CASE WHEN e.event_type = 'page_view' THEN e.session_id END) AS page_views,
    COUNT(DISTINCT CASE WHEN e.event_type = 'purchase' THEN e.session_id END) AS purchases,
    
    ROUND(
        COUNT(DISTINCT CASE WHEN e.event_type = 'purchase' THEN e.session_id END) * 100.0 /
        NULLIF(COUNT(DISTINCT CASE WHEN e.event_type = 'page_view' THEN e.session_id END),0),
    2) AS conversion_rate

FROM events e
JOIN sessions s 
ON e.session_id = s.session_id

GROUP BY s.source
ORDER BY conversion_rate DESC;

                ---#overall vs organic dropoff analysis---
                
WITH funnel_steps AS (
    SELECT 'page_view' AS event_type, 1 AS step UNION ALL
    SELECT 'add_to_cart', 2 UNION ALL
    SELECT 'checkout', 3 UNION ALL
    SELECT 'purchase', 4
),

overall AS (
    SELECT 
        e.event_type,
        f.step,
        COUNT(DISTINCT e.session_id) AS users
    FROM events e
    JOIN funnel_steps f 
        ON e.event_type = f.event_type
    GROUP BY e.event_type, f.step
),

organic AS (
    SELECT 
        e.event_type,
        f.step,
        COUNT(DISTINCT e.session_id) AS users
    FROM events e
    JOIN sessions s 
        ON e.session_id = s.session_id
    JOIN funnel_steps f 
        ON e.event_type = f.event_type
    WHERE s.source = 'organic'
    GROUP BY e.event_type, f.step
),

overall_lag AS (
    SELECT 
        event_type,
        users,
        step,
        LAG(users) OVER (ORDER BY step) AS prev_users
    FROM overall
),

organic_lag AS (
    SELECT 
        event_type,
        users,
        step,
        LAG(users) OVER (ORDER BY step) AS prev_users
    FROM organic
)

SELECT 
    o.event_type,

    o.users AS overall_users,
    ROUND((o.prev_users - o.users) * 100.0 / NULLIF(o.prev_users,0), 2) AS overall_drop_pct,

    org.users AS organic_users,
    ROUND((org.prev_users - org.users) * 100.0 / NULLIF(org.prev_users,0), 2) AS organic_drop_pct

FROM overall_lag o
LEFT JOIN organic_lag org 
    ON o.event_type = org.event_type

ORDER BY o.step;

       -----#Revenue analysis------
       
         ---#Total Revenue---
 SELECT 
    ROUND(SUM(final_amount), 2) AS total_revenue,
    COUNT(*) AS total_orders,
    ROUND(AVG(final_amount), 2) AS avg_order_value
FROM orders; 

         ---#Revenue by country--- 
SELECT 
    country,
    ROUND(SUM(final_amount), 2) AS revenue,
    COUNT(*) AS orders,
    ROUND(AVG(final_amount), 2) AS avg_order_value
FROM orders
GROUP BY country
ORDER BY revenue DESC;

          ---#Revenue by Device---
SELECT 
    device,
    ROUND(SUM(final_amount), 2) AS revenue,
    COUNT(*) AS orders,
    ROUND(AVG(final_amount), 2) AS avg_order_value
FROM orders
GROUP BY device
ORDER BY revenue DESC;

          ---#Revenue by source---
SELECT 
    source,
    ROUND(SUM(final_amount), 2) AS revenue,
    COUNT(*) AS orders,
    ROUND(AVG(final_amount), 2) AS avg_order_value
FROM orders
GROUP BY source
ORDER BY revenue DESC;

             ---#Revenue contribution %---
SELECT 
    source,
    ROUND(SUM(final_amount), 2) AS revenue,
    ROUND(100 * SUM(final_amount) /NULLIF( SUM(SUM(final_amount)) OVER (),0), 2) AS revenue_pct
FROM orders
GROUP BY source
ORDER BY revenue DESC;

             ---#Discount Impact---
SELECT 
    CASE 
        WHEN discount_pct = 0 THEN 'No Discount'
        WHEN discount_pct <= 10 THEN 'Low Discount'
        WHEN discount_pct <= 20 THEN 'Medium Discount'
        ELSE 'High Discount'
    END AS discount_bucket,

    COUNT(*) AS orders,
    ROUND(SUM(final_amount), 2) AS revenue,
    ROUND(AVG(final_amount), 2) AS avg_order_value,

    ROUND(
        100 * SUM(final_amount) / NULLIF(SUM(SUM(final_amount)) OVER (),0),
    2) AS revenue_pct

FROM orders
GROUP BY discount_bucket
ORDER BY revenue DESC;

              ---#High Value Vs Low Value Orders---
SELECT 
    CASE 
        WHEN final_amount < 100 THEN 'Low Value'
        WHEN final_amount < 200 THEN 'Medium Value'
        ELSE 'High Value'
    END AS order_type,

    COUNT(*) AS orders,
    ROUND(SUM(final_amount), 2) AS revenue,

    ROUND(
        100 * SUM(final_amount) / NULLIF(SUM(SUM(final_amount)) OVER (), 0),
    2) AS revenue_pct

FROM orders
GROUP BY order_type
ORDER BY revenue DESC;

                ---#Revenue Trend---
SELECT 
    DATE(order_time) AS order_date,
    ROUND(SUM(final_amount), 2) AS daily_revenue
FROM orders
GROUP BY order_date
ORDER BY order_date;

               ---#Revenue Efficiency per Stage--- 

WITH session_revenue AS (
    SELECT 
        s.session_id,
        SUM(o.final_amount) AS session_revenue
    FROM sessions s
    JOIN orders o ON s.customer_id = o.customer_id
    GROUP BY s.session_id
)
SELECT
    e.event_type,
    COUNT(DISTINCT e.session_id)              AS users,
    ROUND(SUM(sr.session_revenue), 2)         AS revenue,
    ROUND(
        SUM(sr.session_revenue) / 
        NULLIF(COUNT(DISTINCT e.session_id),0), 2
    )                                          AS revenue_per_user
FROM events e
JOIN session_revenue sr ON e.session_id = sr.session_id
GROUP BY e.event_type
ORDER BY revenue_per_user DESC;

              -----#Cohort Analysis and Retention----

                ---#Cohort Base---

CREATE VIEW cohort_base_view AS
SELECT 
    customer_id,
    DATE_FORMAT(MIN(order_time), '%Y-%m-01') AS cohort_month
FROM orders
GROUP BY customer_id;


			--- #Month Indexing---
	
CREATE VIEW cohort_index_view AS
SELECT 
    o.customer_id,
    cb.cohort_month,
    DATE_FORMAT(o.order_time, '%Y-%m-01') AS order_month,
    TIMESTAMPDIFF(MONTH, cb.cohort_month, DATE_FORMAT(o.order_time, '%Y-%m-01')) AS month_number
FROM orders o
JOIN cohort_base_view cb ON o.customer_id = cb.customer_id
WHERE DATE_FORMAT(o.order_time, '%Y-%m-01') >= cb.cohort_month;


          --- #Cohort Retention Table---

WITH cohort_size AS (
    SELECT 
        cohort_month,
        COUNT(DISTINCT customer_id) AS cohort_users
    FROM cohort_index_view
    WHERE month_number = 0
    GROUP BY cohort_month
)
SELECT 
    ci.cohort_month,
    ci.month_number,
    COUNT(DISTINCT ci.customer_id) AS users,
    ROUND(
        100 * COUNT(DISTINCT ci.customer_id) / NULLIF(cs.cohort_users, 0),
    2) AS retention_pct
FROM cohort_index_view ci
JOIN cohort_size cs ON ci.cohort_month = cs.cohort_month
GROUP BY ci.cohort_month, ci.month_number
ORDER BY ci.cohort_month, ci.month_number;
 
                    ---#Revenue Cohort---
WITH first_purchase AS (
    SELECT 
        customer_id,
        DATE_FORMAT(MIN(order_time), '%Y-%m-01') AS cohort_month
    FROM orders
    GROUP BY customer_id
),
cohort_index AS (
    SELECT 
        o.customer_id,
        fp.cohort_month,
        DATE_FORMAT(o.order_time, '%Y-%m-01') AS order_month,
        TIMESTAMPDIFF(MONTH, fp.cohort_month, DATE_FORMAT(o.order_time, '%Y-%m-01')) AS month_number,
        o.final_amount
    FROM orders o
    JOIN first_purchase fp ON o.customer_id = fp.customer_id
    WHERE DATE_FORMAT(o.order_time, '%Y-%m-01') >= fp.cohort_month
)
SELECT 
    cohort_month,
    month_number,
    ROUND(SUM(final_amount), 2) AS revenue
FROM cohort_index
GROUP BY cohort_month, month_number
ORDER BY cohort_month, month_number;
































