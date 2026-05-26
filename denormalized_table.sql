-- touch me bro
USE student_submission;
CREATE TABLE denormalized_orders (
    order_id INT,
    order_quantity INT,
    seller_id INT,
    product_id INT, 
    product_price INT,
    product_name VARCHAR(255),
    buyer_id INT,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    email VARCHAR(255),
    address VARCHAR(255),
    city VARCHAR(100),
    country VARCHAR(100),
    cc_number VARCHAR(16),
    cc_exp VARCHAR(7),
    review TEXT,
    rating INT,
    seller_name VARCHAR(255),
    seller_country VARCHAR(100),
    order_date DATE
);

SET GLOBAL local_infile = 1;
LOAD DATA LOCAL INFILE 'C:/Users/darry/course-project-tanhalf/denormalized_orders.csv'
INTO TABLE denormalized_orders
FIELDS TERMINATED BY ',' 
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(order_id, order_quantity, seller_id, product_id, product_price, 
product_name, buyer_id, first_name, last_name, email, address, 
city, country, cc_number, cc_exp, review, rating, seller_name, 
seller_country, @order_date)
SET order_date = STR_TO_DATE(@order_date, '%m-%d-%Y');
