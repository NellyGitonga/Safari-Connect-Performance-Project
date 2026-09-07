create schema safari_connect;

set search_path to safari_connect;

show search_path;


---- creating schema and staging table booking staging
create table if not exists safari_connect.bookings_staging(
CREATE SCHEMA IF NOT EXISTS safari_connect;
SET search_path TO safari_connect;

-- Staging table: ALL columns TEXT - accepts dirty data without failing
CREATE TABLE IF NOT EXISTS safari_connect.bookings_staging (
    booking_id       TEXT,
    passenger_name    TEXT, 
    passenger_phone  TEXT,
    passenger_gender TEXT, 
    passenger_city    TEXT, 
    route_code       TEXT,
    route_from       TEXT, 
    route_to          TEXT, 
    vehicle_plate    TEXT,
    vehicle_type     TEXT, 
    driver_name       TEXT, 
    driver_rating    TEXT,
    departure_date   TEXT, 
    departure_time    TEXT, 
    seat_class       TEXT,
    seats_booked     TEXT, 
    fare_per_seat     TEXT, 
    total_fare       TEXT,
    payment_method   TEXT, 
    booking_status    TEXT, 
    trip_rating      TEXT
);


	
----Step 2---
---Importing data(csv)
---verifying the actual count of data from the file
select count(*) from safari_connect.bookings_staging;


--First 10 rows
select * from safari_connect.bookings_staging limit 10;


---Step 3 ---Audit queries 
---1.Name casing problem
select distinct passenger_name
from safari_connect.bookings_staging 
order by passenger_name
limit 30;

---2. Gender variants
select distinct passenger_gender, count(*)
from safari_connect.bookings_staging
group by passenger_gender;

---3 seat_class variants
select distinct seat_class, count(*)
from safari_connect.bookings_staging
group by seat_class;

---4 payment method variants
select distinct payment_method 
from safari_connect.bookings_staging;

---5 booking status variants
select distinct booking_status from safari_connect.bookings_staging;

--- 6 Date format problems
select booking_id, departure_date
from safari_connect.bookings_staging
where departure_date not similar to '[0-9]{4}-[0-9]{2}-[0-9]{2}';

--- 7 Phone format problems
select booking_id,passenger_phone
from safari_connect.bookings_staging
where passenger_phone like '+254%' or passenger_phone like '%-%';


---8. Fares stored as text
select booking_id, total_fare,fare_per_seat
from safari_connect.bookings_staging 
where total_fare like 'KES%' or fare_per_seat like 'KES%';


---9. Invalid trip ratings
select booking_id, trip_rating
from safari_connect.bookings_staging
where trip_rating not in ('1','2','3','4','5','');

---10.Duplicate booking_ids
select booking_id, count(*)
from safari_connect.bookings_staging
group by booking_id having count(*) >1;

--- 11. Negative seats_booked
select booking_id, seats_booked
from safari_connect.bookings_staging 
where nullif(regexp_replace(seats_booked,'[^0-9-]','g'),'') :: integer < 1;




----Step 4: Complete Cleaning Script
--clean 1- Passenger name casing + white space
select booking_id, passenger_name 
from safari_connect.bookings_staging
where passenger_name !=initcap(trim(passenger_name));

update safari_connect.bookings_staging
set passenger_name = initcap(trim(passenger_name))
where passenger_name !=initcap(trim(passenger_name));

select booking_id, passenger_name from safari_connect.bookings_staging;


---Cean 2- passenger phone (dashes, +254, empty)
--Remove dashes
update safari_connect.bookings_staging 
set passenger_phone = regexp_replace(passenger_phone,'[^0-9]','','g')
where passenger_phone like '%-%';

---Fix +254 prefix
UPDATE safari_connect.bookings_staging
SET passenger_phone = '0' || SUBSTRING(REGEXP_REPLACE(passenger_phone,'[^0-9]','','g'),4)
WHERE passenger_phone LIKE '+254%';


-- set empty to null
update safari_connect.bookings_staging
set passenger_phone = null
where trim(passenger_phone) = '';

select passenger_phone from safari_connect.bookings_staging;



---clear 3- passenger gender (7 variants--->Male/Female)

update safari_connect.bookings_staging
set passenger_gender =case
	when upper(trim(passenger_gender)) in ('MALE','M') then 'Male'
	when upper(trim(passenger_gender)) in ('FEMALE','F') then 'Female'
	else passenger_gender
end;

select passenger_gender from safari_connect.bookings_staging;

----clean 4 - passenger city (casing and empty)
UPDATE safari_connect.bookings_staging
SET passenger_city = INITCAP(TRIM(passenger_city))
WHERE passenger_city != INITCAP(TRIM(passenger_city));

UPDATE safari_connect.bookings_staging SET passenger_city = 'Unknown'
WHERE TRIM(passenger_city) = '' OR passenger_city IS NULL;


select passenger_city from safari_connect.bookings_staging;

----Clean 5 - departure_date (3 formats)
----- Fix DD/MM/YYYY


UPDATE safari_connect.bookings_staging
SET departure_date = TO_DATE(departure_date,'DD/MM/YYYY')::TEXT
WHERE departure_date LIKE '%/%';

select departure_date from safari_connect.bookings_staging;

-- Fix DD-MM-YY (length = 8)
UPDATE safari_connect.bookings_staging
SET departure_date = TO_DATE(departure_date,'DD-MM-YY')::TEXT
WHERE departure_date LIKE '%-%' AND LENGTH(departure_date) = 8;

select departure_date from safari_connect.bookings_staging;


-- Fix MM-DD-YYYY (length=10, day part > 12 confirms it's MM-DD not DD-MM)
UPDATE safari_connect.bookings_staging
SET departure_date = TO_DATE(departure_date,'MM-DD-YYYY')::TEXT
WHERE departure_date LIKE '%-%'
  AND LENGTH(departure_date) = 10
  AND SPLIT_PART(departure_date,'-',2)::INTEGER > 12;

select departure_date from safari_connect.bookings_staging;



----Clean 6 - Seat class(abbreviations + casing)
UPDATE safari_connect.bookings_staging
SET seat_class = CASE
    WHEN UPPER(TRIM(seat_class)) IN ('ECONOMY','ECO','ECONOMY CLASS') THEN 'Economy'
    WHEN UPPER(TRIM(seat_class)) IN ('BUSINESS','BUS','BUSINESS CLASS') THEN 'Business'
    ELSE seat_class
END;


---Clean 7 -payment method and booking status
UPDATE safari_connect.bookings_staging
SET payment_method = CASE
    WHEN UPPER(TRIM(payment_method)) IN ('MPESA','M-PESA','M PESA') THEN 'M-Pesa'
    WHEN UPPER(TRIM(payment_method)) = 'CASH'                              THEN 'Cash'
    WHEN UPPER(TRIM(payment_method)) = 'CARD'                              THEN 'Card'
    ELSE payment_method
END;

UPDATE safari_connect.bookings_staging
SET booking_status = CASE
    WHEN UPPER(TRIM(booking_status)) = 'COMPLETED'  THEN 'Completed'
    WHEN UPPER(TRIM(booking_status)) = 'CANCELLED'  THEN 'Cancelled'
    WHEN UPPER(TRIM(booking_status)) = 'NO SHOW'     THEN 'No Show'
    ELSE booking_status
END;


----clean 9 Driver name casing
UPDATE safari_connect.bookings_staging
SET driver_name = INITCAP(TRIM(driver_name))
WHERE driver_name != INITCAP(TRIM(driver_name));


---Clean 10 - vehicle type casing
UPDATE safari_connect.bookings_staging
SET vehicle_type = INITCAP(TRIM(vehicle_type))
WHERE vehicle_type != INITCAP(TRIM(vehicle_type));

---Clean 11- Trip_rating (invalid values ---null)
UPDATE safari_connect.bookings_staging
SET trip_rating = NULL
WHERE TRIM(trip_rating) NOT IN ('1','2','3','4','5','');

---clean 12 - Remove negative seats and duplicates
---Delete row with negative seats
delete from safari_connect.bookings_staging 
where nullif (regexp_replace(seats_booked,'[^0-9-]','','g'),'') :: integer < 1;

----remove exact duplicates  (keep first child)
delete from safari_connect.bookings_staging 
where ctid not in
	(select min(ctid) from safari_connect.bookings_staging group by booking_id);

select * from safari_connect.bookings_staging;




---Step 5: Create Production table and load clean data
CREATE TABLE IF NOT EXISTS safari_connect.bookings (
    booking_id        VARCHAR(10) PRIMARY KEY,
    passenger_name    VARCHAR(100),  passenger_phone  VARCHAR(15),
    passenger_gender  VARCHAR(10),   passenger_city   VARCHAR(60),
    route_code        VARCHAR(10),   route_from       VARCHAR(60),
    route_to          VARCHAR(60),   vehicle_plate    VARCHAR(15),
    vehicle_type      VARCHAR(20),   driver_name      VARCHAR(100),
    driver_rating     NUMERIC(3,1),  departure_date   DATE,
    departure_time    VARCHAR(10),   seat_class       VARCHAR(20),
    seats_booked      INTEGER,       fare_per_seat    NUMERIC(10,2),
    total_fare        NUMERIC(12,2), payment_method   VARCHAR(20),
    booking_status    VARCHAR(20),   trip_rating      INTEGER
);
select * from safari_connect.bookings;


----Inserting data to bookings table
INSERT INTO safari_connect.bookings
SELECT
    booking_id, TRIM(passenger_name),
    NULLIF(TRIM(passenger_phone),''),
    passenger_gender, COALESCE(NULLIF(TRIM(passenger_city),''),'Unknown'),
    route_code, route_from, route_to, vehicle_plate,
INITCAP(TRIM(vehicle_type)),
    TRIM(driver_name),
    NULLIF(REGEXP_REPLACE(driver_rating,'[^0-9.]','','g'),'')::NUMERIC,
    departure_date::DATE,  departure_time, seat_class,
    NULLIF(REGEXP_REPLACE(seats_booked,'[^0-9]','','g'),'')::INTEGER,
    NULLIF(REGEXP_REPLACE(fare_per_seat,'[^0-9.]','','g'),'')::NUMERIC,
    NULLIF(REGEXP_REPLACE(total_fare,'[^0-9.]','','g'),'')::NUMERIC,
    payment_method, booking_status,
    NULLIF(trip_rating,'')::INTEGER
FROM safari_connect.bookings_staging
WHERE departure_date SIMILAR TO '[0-9]{4}-[0-9]{2}-[0-9]{2}'
  AND NULLIF(REGEXP_REPLACE(seats_booked,'[^0-9]','','g'),'')::INTEGER > 0;


----verifiying the data
select * from safari_connect.bookings;
select count(*) from safari_connect.bookings;
select distinct booking_status from safari_connect.bookings;


----step 6 - Create v clean trips view
CREATE OR REPLACE VIEW v_clean_trips AS
SELECT *,
    TO_CHAR(departure_date, 'YYYY-MM')    AS travel_month,
    TO_CHAR(departure_date, 'Month YYYY') AS month_label,
    TO_CHAR(departure_date, 'Day')        AS day_name,
    EXTRACT(MONTH FROM departure_date)    AS month_num,
    EXTRACT(DOW FROM departure_date)      AS day_of_week,
    (fare_per_seat * seats_booked)           AS calculated_fare,
    CASE
        WHEN trip_rating BETWEEN 4 AND 5 THEN 'Satisfied'
        WHEN trip_rating = 3 THEN 'Neutral'
        WHEN trip_rating BETWEEN 1 AND 2 THEN 'Unsatisfied'
        ELSE 'No Rating'
    END AS satisfaction
FROM safari_connect.bookings
WHERE booking_status = 'Completed';

---Test
select * from safari_connect.v_clean_trips limit 10;
select * from safari_connect.v_clean_trips;
select count(*) from safari_connect.v_clean_trips;



--=========================================================================
----------QUESTION 1 - ROUTE ANALYSIS-----------------------------------
--========================================================================


/*
 * PART 1A - Revenue and bookings by route
Show: route_code, route_from, route_to, total_bookings, total_seats, total_revenue, avg_fare, avg_trip_rating. Order by total_revenue descending.

 */
SELECT
    route_code,
    route_from || ' → ' || route_to      AS route,
    COUNT(*)                              AS total_bookings,
    SUM(seats_booked)                   AS total_seats,
    SUM(total_fare)                     AS total_revenue,
    ROUND(AVG(fare_per_seat), 2)     AS avg_fare,
    ROUND(AVG(trip_rating), 2)       AS avg_rating
FROM safari_connect.v_clean_trips
GROUP BY route_code, route_from, route_to
ORDER BY total_revenue DESC;



---------Question 2 - Driver Performance---------------------

/*
 * 2A - Driver summary
Show: driver_name, total_trips, total_seats_carried, total_revenue, avg_trip_rating, driver_rating. Order by total_revenue descending.

 */
select 
	driver_name,
	count(*) as total_trips,
	sum(seats_booked) as total_seats_carried,
	sum(total_fare) as total_revenue,
	round(avg(trip_rating),2) as avg_trip_rating,
	round(avg(driver_rating),2) as driver_rating
from safari_connect.v_clean_trips 
group by driver_name 
order by total_revenue desc;


/*
 * 2C - Does driver rating predict passenger satisfaction?
Group drivers into high-rated (≥ 4.5) and standard (< 4.5). Compare average passenger trip_rating for each group. Does a higher driver rating lead to happier passengers?

 */

select
    case
        when driver_rating >= 4.5 then 'high-rated'
        when driver_rating < 4.5 then 'standard'
        else 'no rating'
    end as driver_group,
    count(*) as total_trips,
    round(avg(trip_rating), 2) as avg_passenger_rating
from safari_connect.v_clean_trips
group by driver_group
order by avg_passenger_rating desc;


---------====QUESTION 3 Revenue Trends==================
---PART 1-----

/*
 * 3A - Monthly revenue with month-over-month change (CTE + LAG)
*/


WITH monthly AS (
    SELECT
        TO_CHAR(departure_date, 'FMMonth') AS month,
        EXTRACT(MONTH FROM departure_date) AS month_num,
        COUNT(*)                                AS bookings,
        SUM(total_fare)                       AS revenue
    FROM safari_connect.v_clean_trips
    GROUP BY TO_CHAR(departure_date, 'FMMonth'),
        EXTRACT(MONTH FROM departure_date)
)
SELECT
    month, bookings, revenue,
    LAG(revenue) OVER (ORDER BY month)                        AS prev_month,
    revenue - LAG(revenue) OVER (ORDER BY month)        AS change,
    ROUND((revenue - LAG(revenue) OVER (ORDER BY month))
        / NULLIF(LAG(revenue) OVER (ORDER BY month),0) * 100, 1)  AS change_pct
FROM monthly 
ORDER BY month_num;


-----PART 2-------
/*
 * 3B - Running total of revenue
Show each month with its revenue and a cumulative running total from January onwards.
---Step 1: Get monthly total revenue
---Step 2: A CTE function to calculate cumulative total
 */

SELECT
    TO_CHAR(departure_date, 'YYYY-MM') AS month,
    SUM(total_fare) AS revenue
FROM safari_connect.v_clean_trips
GROUP BY TO_CHAR(departure_date, 'YYYY-MM')
ORDER BY month;

with monthly as (
	SELECT
	    TO_CHAR(departure_date, 'YYYY-MM') AS month,
	    SUM(total_fare) AS revenue
	FROM safari_connect.v_clean_trips
	GROUP BY TO_CHAR(departure_date, 'YYYY-MM')
	ORDER BY month
)
select 
	month,
	revenue,
	sum(revenue) over(order by month) as cumulative_total
from monthly 
order by month;


-----PART C----------
/*
 * 3C - Best and worst 3 months
Using a CTE for monthly revenue, show the top 3 months and the bottom 3 months by revenue. Use RANK().
---Step 1: Build a CTE to calculate monthly revenue
---Step 2: Rank() as high rank and low rank orde revenue as desc
---Step 3: A case statement to label high rank as top 3 and low rank as bottom 3

 */
with monthly as (
	SELECT
		    TO_CHAR(departure_date, 'YYYY-MM') AS month,
		    SUM(total_fare) AS revenue
	FROM safari_connect.v_clean_trips
	GROUP BY TO_CHAR(departure_date, 'YYYY-MM')
	ORDER BY month
),
ranked as (
	SELECT
        month,
        revenue,
        RANK() OVER (ORDER BY revenue DESC) AS rank_high,
        RANK() OVER (ORDER BY revenue ASC) AS rank_low
   FROM monthly
)
SELECT
    month,
    revenue,
    CASE
        WHEN rank_high <= 3 THEN 'Top 3'
        WHEN rank_low <= 3 THEN 'Bottom 3'
    END AS category
FROM ranked
WHERE rank_high <= 3
   OR rank_low <= 3
ORDER BY revenue DESC;


----PART D --------------------
/*
 * 3D - Revenue by route per month (pivot)
Show one row per month with separate columns for the top 3 routes (RT001, RT002, RT003) using CASE WHEN + SUM.
---Step 1: Group by month
---Step 2: Create a column for RT001, RT002 and RT003 using a (case statement+sum)
 */
 
select 
	to_char(departure_date,'YYYY-MM') as month
from safari_connect.v_clean_trips 
group by to_char(departure_date,'YYYY-MM')
order by month;

select
    to_char(departure_date, 'yyyy-mm') as month,
sum(
        case
            when route_code = 'rt001' then total_fare
            else 0
        end
    ) as rt001_revenue,
sum(
        case
            when route_code = 'rt002' then total_fare
            else 0
        end
    ) as rt002_revenue,
sum(
        case
            when route_code = 'rt003' then total_fare
            else 0
        end
    ) as rt003_revenue
from safari_connect.v_clean_trips
group by to_char(departure_date, 'yyyy-mm')
order by month;



---==============QUESTION 4: PASSENGER INSIGHTS=================================
/*
 * PART 4A - Top passenger cities
Show: passenger_city, total_bookings, total_seats, total_revenue, avg_fare. Order by total_bookings descending. Only include cities with 3+ bookings

---Step 1: Group by city
---Step 2: Get the total number of counts
---Step 3: Order by total revenue from the highest
---Step 4: Get passenger_cities having count(*) >=3
 */
select 
	passenger_city,
	count(*) as total_bookings,
	sum(seats_booked) as total_seats,
	sum(total_fare) as total_revenue,
	round(avg(total_fare),2) as avg_fare
from safari_connect.v_clean_trips
group by passenger_city 
having count(*) >=3
order by total_bookings desc;



----PART 4B----------------------------------
/*
 * 4B - Gender split and seat class preference
Show bookings and revenue broken down by passenger_gender and seat_class. Use a CASE WHEN pivot to show Economy and Business as separate columns.

---Step 1: Get the gender, total_bookings and total_revenue
---Step 2: Case statement + sum for each seat class and create a new column that correspond to that seat class
---Step 3: Group by passenger_gender and orde by total_revenue from highest

 */
select 
	passenger_gender,
	count(*) as total_bookings,
	sum(total_fare) as total_revenue,
	sum(
	        case
	            when seat_class = 'economy' then 1
	            else 0
	        end
	    ) as economy_bookings,
	sum(
	        case
	            when seat_class = 'business' then 1
	            else 0
	        end
	    ) as business_bookings,
	sum(
	        case
	            when seat_class = 'economy' then total_fare
	            else 0
	        end
	    ) as economy_revenue,
	sum(
	        case
	            when seat_class = 'business' then total_fare
	            else 0
	        end
	    ) as business_revenue
from safari_connect.v_clean_trips
group by passenger_gender
order by total_revenue desc;

---================================================================
------PART 4C -SATISFACTION BREAKDOWN (CTE) 
---=================================================================
/*
 *
Using a CTE, count how many trips fall into each satisfaction category (Satisfied / Neutral / Unsatisfied / No Rating). Show count and percentage of total completed trips.

---Step 1: Build CTE that counts the number of satisfactions
---Step 2: Get the percentage from count/ sum count * 100
---Step 3: Group by satisfaction category to get total count that falls in each category.
 */

with sat_counts as (
    select satisfaction, count(*) as cnt
    from safari_connect.v_clean_trips
    group by satisfaction
)
select
    satisfaction,
    cnt,
    round(cnt * 100.0 / sum(cnt) over (), 1) as pct
from sat_counts order by cnt desc;



----==========================================================
----=======4D - PASSENGER QUARTILES BY SPEND (NTILE)==========
---===========================================================

/*
 * Using a CTE for total spend per passenger, divide passengers into 4 quartiles using NTILE(4). Show: passenger_name, total_spent, quartile. Label quartile 4 as 'Top Spender'.
 
 ---Step 1: Calculate the total spend per passenger
 ---Step 2: Build CTE passenger_spend
 ---Step 3: Divide them into 4 quartiles
 ---Step 4: Case statement to group each quatile as for example quartile 1: 'Top Spenders'
 ---Step 5: Order by total spend to see which passengers fall into which qaurtile

 */
select 
	passenger_name,
	sum(total_fare) as total_send
from safari_connect.v_clean_trips 
group by passenger_name;
	
with passenger_spend as (
	select 
		passenger_name,
		sum(total_fare) as total_spend
	from safari_connect.v_clean_trips 
	group by passenger_name
),
quartiles as (
	select 
		passenger_name,
		total_spend,
		ntile(4) over(order by total_spend desc) as quartile
	from passenger_spend 
)
select 
	passenger_name,
	total_spend,
	case
		when quartile=1 then 'Top_Spender'
		else quartile:: text
	end as qaurtiles
from quartiles
order by total_spend desc;
	


--=============================================================
--=========QUESTION 5 - CANCELLATIONS & LOST REVENUE===========
---============================================================


-----PART 5A--------------------------------------
/*
 * 5A - Overall status breakdown
 
 --- Step 1: Identify how many bookings fall into each booking status
 --- Step 2: Group by booking status
 --- Step 3: Count the total bookings 
 ----Step 4: Calculate total revenue
 

 */
select 
	booking_status,
	count(*) as total_bookings,
	sum(total_fare) as total_revenue
from safari_connect.bookings 
group by booking_status 
order by total_revenue desc;
	

----5B - Cancellation rate by route---------------------------
/*
 * Show: route_code, route, total_bookings, completed, cancelled, no_show, cancellation_rate_pct.
 */

select
    route_code,
    route_from || ' → ' || route_to                           as route,
    count(*)                                                              as total,
    sum(case when booking_status = 'completed' then 1 else 0 end) as completed,
    sum(case when booking_status = 'cancelled' then 1 else 0 end) as cancelled,
    sum(case when booking_status = 'no show'  then 1 else 0 end) as no_show,
    round(sum(case when booking_status in ('cancelled','no show')
             then 1 else 0 end) * 100.0 / count(*), 1) as cancel_rate_pct
from safari_connect.bookings
group by route_code, route_from, route_to
order by cancel_rate_pct desc;



------5C - Revenue lost from cancellations and no-shows

SELECT
    booking_status,
    COUNT(*) AS total_bookings,
    SUM(total_fare) AS lost_revenue
FROM safari_connect.bookings
WHERE booking_status IN ('Cancelled', 'No-Show')
GROUP BY booking_status
ORDER BY lost_revenue DESC;



----==============================================================
---====QUESTION 6 - OPERATIONAL PATTERNS==========================
---===============================================================

/*
 * 6A - Revenue by day of week
 */
SELECT
    EXTRACT(DOW FROM departure_date)          AS day_num,
    TO_CHAR(departure_date, 'Day')            AS day_name,
    COUNT(*)                                  AS total_bookings,
    SUM(total_fare)                         AS total_revenue,
    ROUND(AVG(total_fare), 2)          AS avg_booking_value
FROM safari_connect.v_clean_trips
GROUP BY EXTRACT(DOW FROM departure_date), TO_CHAR(departure_date, 'Day')
ORDER BY day_num;


/*
 * 6B - Busiest departure times
Group by departure_time. Show which time slots carry the most passengers and generate the most revenue.
---Step 1: Group by departure time
---Step 2: Get total number of passengers and total revenue
---Step 3: Find the busiest times
 */

SELECT
    departure_time,
    COUNT(*) AS total_bookings,
    SUM(seats_booked) AS total_passengers,
    SUM(total_fare) AS total_revenue
FROM safari_connect.v_clean_trips
GROUP BY departure_time
ORDER BY total_passengers DESC, total_revenue DESC;



/*
 * 6C - Seat utilisation by vehicle type
Compare how full each vehicle type typically runs. Show: vehicle_type, avg_seats_booked, and a label - 'High Load' if avg > 3, 'Medium Load' if 2-3, 'Low Load' if below 2.

---Step 1: Group by vehicle type
---Step 2: Calculate average seats booked
---Step 3: Case statement to assign labels 'High load', Medium load and Low load
 */
SELECT
    vehicle_type,
    ROUND(AVG(seats_booked), 2) AS avg_seats_booked,
    CASE
        WHEN AVG(seats_booked) > 3 THEN 'High Load'
        WHEN AVG(seats_booked) >= 2 THEN 'Medium Load'
        ELSE 'Low Load'
    END AS load_label
FROM safari_connect.v_clean_trips
GROUP BY vehicle_type
ORDER BY avg_seats_booked DESC;




-------------views
----Create Your Views - Hand Off to BI Developer

-- View 1: Route performance
CREATE OR REPLACE VIEW safari_connect.v_route_performance AS
SELECT
    route_code,
    route_from || ' → ' || route_to      AS route,
    COUNT(*)                              AS total_bookings,
    SUM(seats_booked)                   AS total_seats,
    SUM(total_fare)                     AS total_revenue,
    ROUND(AVG(fare_per_seat), 2)     AS avg_fare,
    ROUND(AVG(trip_rating), 2)       AS avg_rating
FROM safari_connect.v_clean_trips
GROUP BY route_code, route_from, route_to
ORDER BY total_revenue DESC;


-- View 2: Driver performance
CREATE OR REPLACE VIEW safari_connect.v_driver_performance AS
select 
	driver_name,
	count(*) as total_trips,
	sum(seats_booked) as total_seats_carried,
	sum(total_fare) as total_revenue,
	round(avg(trip_rating),2) as avg_trip_rating,
	round(avg(driver_rating),2) as driver_rating
from safari_connect.v_clean_trips 
group by driver_name 
order by total_revenue desc;


-- View 3: Monthly revenue trend
CREATE OR REPLACE VIEW safari_connect.v_monthly_revenue AS
WITH monthly AS (
    SELECT
        TO_CHAR(departure_date, 'FMMonth') AS month,
        EXTRACT(MONTH FROM departure_date) AS month_num,
        COUNT(*)                                AS bookings,
        SUM(total_fare)                       AS revenue
    FROM safari_connect.v_clean_trips
    GROUP BY TO_CHAR(departure_date, 'FMMonth'),
        EXTRACT(MONTH FROM departure_date)
)
SELECT
    month, bookings, revenue,
    LAG(revenue) OVER (ORDER BY month)                        AS prev_month,
    revenue - LAG(revenue) OVER (ORDER BY month)        AS change,
    ROUND((revenue - LAG(revenue) OVER (ORDER BY month))
        / NULLIF(LAG(revenue) OVER (ORDER BY month),0) * 100, 1)  AS change_pct
FROM monthly 
ORDER BY month_num;




-- View 4: Cancellation analysis
CREATE OR REPLACE VIEW safari_connect.v_cancellation_analysis AS
SELECT
    route_code,
    route_from || ' → ' || route_to                           AS route,
    COUNT(*)                                                              AS total,
    SUM(CASE WHEN booking_status = 'Completed' THEN 1 ELSE 0 END) AS completed,
    SUM(CASE WHEN booking_status = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled,
    SUM(CASE WHEN booking_status = 'No Show'  THEN 1 ELSE 0 END) AS no_show,
    ROUND(SUM(CASE WHEN booking_status IN ('Cancelled','No Show')
             THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS cancel_rate_pct
FROM safari_connect.bookings
GROUP BY route_code, route_from, route_to
ORDER BY cancel_rate_pct DESC;



-- View 5: Passenger city insights
CREATE OR REPLACE VIEW safari_connect.v_passenger_insights AS
select 
	passenger_city,
	count(*) as total_bookings,
	sum(seats_booked) as total_seats,
	sum(total_fare) as total_revenue,
	round(avg(total_fare),2) as avg_fare
from safari_connect.v_clean_trips
group by passenger_city 
having count(*) >=3
order by total_bookings desc;





------Add Indexes

CREATE INDEX idx_bookings_depdate     ON safari_connect.bookings (departure_date);
CREATE INDEX idx_bookings_route       ON safari_connect.bookings (route_code);
CREATE INDEX idx_bookings_driver      ON safari_connect.bookings (driver_name);
CREATE INDEX idx_bookings_status      ON safari_connect.bookings (booking_status);
CREATE INDEX idx_bookings_payment     ON safari_connect.bookings (payment_method);
CREATE INDEX idx_bookings_vehicle     ON safari_connect.bookings (vehicle_type);
CREATE INDEX idx_bookings_passcity    ON safari_connect.bookings (passenger_city);

SELECT tablename, indexname FROM pg_indexes
WHERE schemaname = 'safari_connect';
select * from pg_indexes;


select * from safari_connect.v_clean_trips;



