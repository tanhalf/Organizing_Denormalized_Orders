DROP VIEW IF EXISTS 
    seller_sales_tiers,
    top_five_buyer_cities,
    top_rated_products;

DROP TABLE IF EXISTS 
    review,
    orders,
    product,
    buyer,
    address,
    seller,
    country,
    credit_card,
    order_item;

DROP PROCEDURE IF EXISTS seller_running_totals;
DROP PROCEDURE IF EXISTS top_products_for_seller;
DROP PROCEDURE IF EXISTS sales_for_month;
DROP PROCEDURE IF EXISTS buyer_for_date;
DROP PROCEDURE IF EXISTS top_ten_for_country;

CREATE TABLE country(
    country_id INT AUTO_INCREMENT PRIMARY KEY,
    country VARCHAR(255) UNIQUE NOT NULL
);

CREATE TABLE address(
    address_id INT AUTO_INCREMENT PRIMARY KEY,
    address VARCHAR(255),
    city VARCHAR(255),
    country_id INT,
    FOREIGN KEY (country_id) REFERENCES country(country_id),
    UNIQUE(address, city, country_id)
);

CREATE TABLE seller(
    seller_id INT PRIMARY KEY,
    seller_name VARCHAR(255),
    country_id INT,
    FOREIGN KEY (country_id) REFERENCES country(country_id)
);

CREATE TABLE buyer(
    buyer_id INT PRIMARY KEY,
    first_name VARCHAR(255),
    last_name VARCHAR(255),
    email VARCHAR(255) UNIQUE,
    address_id INT,
    FOREIGN KEY (address_id) REFERENCES address(address_id)
);

CREATE TABLE credit_card(
    cc_id INT AUTO_INCREMENT PRIMARY KEY,
    buyer_id INT,
    cc_number VARCHAR(25) UNIQUE,
    cc_exp VARCHAR(7),
    FOREIGN KEY (buyer_id) REFERENCES buyer(buyer_id)
);

CREATE TABLE product(
    product_id INT PRIMARY KEY,
    product_name VARCHAR(255),
    product_price DECIMAL(10,2),
    seller_id INT,
    FOREIGN KEY (seller_id) REFERENCES seller(seller_id)
);

CREATE TABLE orders(
    order_id INT PRIMARY KEY,
    buyer_id INT,
    order_date DATE,
    FOREIGN KEY (buyer_id) REFERENCES buyer(buyer_id)
);

CREATE TABLE order_item(
    order_id INT,
    product_id INT,
    order_quantity INT,
    PRIMARY KEY(order_id, product_id),
    FOREIGN KEY(order_id) REFERENCES orders(order_id),
    FOREIGN KEY(product_id) REFERENCES product(product_id)
);

CREATE TABLE review(
    review_id INT AUTO_INCREMENT PRIMARY KEY,
    rating DECIMAL(2,1),
    review VARCHAR(255),
    buyer_id INT,
    product_id INT,
    FOREIGN KEY (buyer_id) REFERENCES buyer(buyer_id),
    FOREIGN KEY (product_id) REFERENCES product(product_id)
);

INSERT INTO country(country)
SELECT DISTINCT country
FROM denormalized_orders
UNION
SELECT DISTINCT seller_country
FROM denormalized_orders;

INSERT INTO address(address, city, country_id)
SELECT DISTINCT
    d.address,
    d.city,
    c.country_id
FROM denormalized_orders d
JOIN country c
    ON c.country = d.country;

INSERT INTO seller(seller_id, seller_name, country_id)
SELECT DISTINCT
    d.seller_id,
    d.seller_name,
    c.country_id
FROM denormalized_orders d
JOIN country c
    ON c.country = d.seller_country;

INSERT INTO buyer(buyer_id, first_name, last_name, email, address_id)
SELECT DISTINCT
    d.buyer_id,
    d.first_name,
    d.last_name,
    d.email,
    a.address_id
FROM denormalized_orders d
JOIN country c
    ON c.country = d.country
JOIN address a
    ON a.address = d.address
    AND a.city = d.city
    AND a.country_id = c.country_id;

INSERT INTO credit_card(buyer_id, cc_number, cc_exp)
SELECT DISTINCT
    buyer_id,
    cc_number,
    cc_exp
FROM denormalized_orders;

INSERT INTO product(product_id, product_name, product_price, seller_id)
SELECT DISTINCT
    product_id,
    product_name,
    product_price,
    seller_id
FROM denormalized_orders;

INSERT INTO orders(order_id, buyer_id, order_date)
SELECT DISTINCT
    order_id,
    buyer_id,
    order_date
FROM denormalized_orders;

INSERT IGNORE INTO order_item(order_id, product_id, order_quantity)
SELECT DISTINCT
    order_id,
    product_id,
    order_quantity
FROM denormalized_orders;

INSERT INTO review(rating, review, buyer_id, product_id)
SELECT DISTINCT
    rating,
    review,
    buyer_id,
    product_id
FROM denormalized_orders;

CREATE INDEX idx_seller_country_id ON seller(country_id);
CREATE INDEX idx_buyer_address_id ON buyer(address_id);
CREATE INDEX idx_credit_card_buyer_id ON credit_card(buyer_id);
CREATE INDEX idx_product_seller_id ON product(seller_id);
CREATE INDEX idx_orders_buyer_id ON orders(buyer_id);
CREATE INDEX idx_order_item_product_id ON order_item(product_id);
CREATE INDEX idx_review_buyer_id ON review(buyer_id);
CREATE INDEX idx_review_product_id ON review(product_id);

DELIMITER //

CREATE PROCEDURE top_ten_for_country(IN p_country VARCHAR(255))
BEGIN
    SELECT 
        b.buyer_id, 
        b.first_name, 
        b.last_name, 
        CONCAT('$', FORMAT(SUM(oi.order_quantity * (p.product_price / 100.0)), 2)) AS total_amount_spent
    FROM buyer b
    JOIN address a ON b.address_id = a.address_id
    JOIN country c ON a.country_id = c.country_id
    JOIN orders o ON o.buyer_id = b.buyer_id
    JOIN order_item oi ON oi.order_id = o.order_id 
    JOIN product p ON p.product_id = oi.product_id
    WHERE c.country = p_country
    GROUP BY b.buyer_id, b.first_name, b.last_name
    ORDER BY SUM(oi.order_quantity * (p.product_price / 100.0)) DESC
    LIMIT 10;
END //

DELIMITER ;

CREATE VIEW top_rated_products AS
SELECT 
    p.product_id,
    p.product_name,
    CONCAT('$', FORMAT((p.product_price / 100.0), 2)) AS product_price,
    AVG(r.rating) AS avg_rating,
    COUNT(r.rating) AS rating_count
FROM product p
JOIN review r ON p.product_id = r.product_id
GROUP BY p.product_id, p.product_name, p.product_price
HAVING COUNT(r.rating) >= 20
ORDER BY avg_rating DESC, rating_count DESC
LIMIT 10;

DELIMITER //

CREATE PROCEDURE buyer_for_date(IN p_first_name VARCHAR(255), IN p_last_name VARCHAR(255), IN p_order_date DATE)
BEGIN
    SELECT 
        o.order_id,
        oi.order_quantity,
        p.product_name,
        o.order_date
    FROM orders o 
    JOIN buyer b ON b.buyer_id = o.buyer_id
    JOIN order_item oi ON o.order_id = oi.order_id
    JOIN product p ON p.product_id = oi.product_id
    WHERE b.first_name = p_first_name 
      AND b.last_name = p_last_name 
      AND o.order_date = p_order_date;
END //

DELIMITER ;

CREATE VIEW top_five_buyer_cities AS
SELECT 
    a.city,
    CONCAT('$', FORMAT(SUM(oi.order_quantity * (p.product_price / 100.0)), 2)) AS total_amount_spent
FROM address a
JOIN buyer b ON a.address_id = b.address_id
JOIN orders o ON b.buyer_id = o.buyer_id
JOIN order_item oi ON o.order_id = oi.order_id
JOIN product p ON oi.product_id = p.product_id
GROUP BY a.city
ORDER BY SUM(oi.order_quantity * (p.product_price / 100.0)) DESC
LIMIT 5;

DELIMITER //

CREATE PROCEDURE sales_for_month(IN p_month_year VARCHAR(255))
BEGIN
    SELECT 
        p_month_year AS month_and_year,
        CONCAT('$', FORMAT(SUM(oi.order_quantity * p.product_price), 2)) AS total_sales
    FROM orders o
    JOIN order_item oi ON o.order_id = oi.order_id
    JOIN product p ON oi.product_id = p.product_id
    WHERE DATE_FORMAT(o.order_date, '%m-%Y') = p_month_year
       OR DATE_FORMAT(o.order_date, '%Y-%m') = p_month_year
       OR DATE_FORMAT(o.order_date, '%b-%Y') = p_month_year
    GROUP BY month_and_year;
END //

DELIMITER ;

CREATE VIEW seller_sales_tiers AS
SELECT 
    s.seller_id,
    s.seller_name,
    CONCAT('$', FORMAT(SUM(oi.order_quantity * (p.product_price / 100.0)), 2)) AS total_sales,
    CASE
        WHEN SUM(oi.order_quantity * (p.product_price / 100.0)) >= 100000.00 THEN 'High'
        WHEN SUM(oi.order_quantity * (p.product_price / 100.0)) >= 10000.00 THEN 'Medium'
        ELSE 'Low'
    END AS sales_tier
FROM seller s 
JOIN product p ON p.seller_id = s.seller_id
JOIN order_item oi ON p.product_id = oi.product_id
GROUP BY s.seller_id, s.seller_name
ORDER BY SUM(oi.order_quantity * (p.product_price / 100.0)) DESC;

DELIMITER //

CREATE PROCEDURE top_products_for_seller(IN p_seller_name VARCHAR(255))
BEGIN
    SELECT 
        s.seller_id, 
        p.product_id, 
        p.product_name, 
        CONCAT('$', FORMAT(SUM(oi.order_quantity * (p.product_price / 100.0)), 2)) AS total_sales
    FROM seller s 
    JOIN product p ON p.seller_id = s.seller_id
    JOIN order_item oi ON p.product_id = oi.product_id
    WHERE s.seller_name = p_seller_name
    GROUP BY s.seller_id, p.product_id, p.product_name
    ORDER BY SUM(oi.order_quantity * (p.product_price / 100.0)) DESC;
END //

DELIMITER ;

DELIMITER //

CREATE PROCEDURE seller_running_totals(IN p_seller_name VARCHAR(255))
BEGIN
    SELECT 
        t.seller_id,
        t.order_id,
        t.order_date,
        CONCAT('$', FORMAT(t.order_total_raw, 2)) AS order_total,
        CONCAT('$', FORMAT(SUM(t.order_total_raw) OVER (
            PARTITION BY t.seller_id 
            ORDER BY t.order_date, t.order_id
        ), 2)) AS running_total
    FROM (
        SELECT 
            s.seller_id,
            o.order_id,
            o.order_date,
            SUM(oi.order_quantity * (p.product_price / 100.0)) AS order_total_raw
        FROM seller s
        JOIN product p ON p.seller_id = s.seller_id
        JOIN order_item oi ON p.product_id = oi.product_id
        JOIN orders o ON oi.order_id = o.order_id
        WHERE s.seller_name = p_seller_name
        GROUP BY s.seller_id, o.order_id, o.order_date
    ) t
    ORDER BY t.order_date, t.order_id;
END //

DELIMITER ;

-- Final Test Visual Data Outputs
-- ==========================================

-- 1. Display your working Views
SELECT * FROM top_rated_products;
SELECT * FROM top_five_buyer_cities;
SELECT * FROM seller_sales_tiers;

CALL top_ten_for_country('New Zealand');

CALL buyer_for_date('Marley', 'Bode', '2025-07-23');
CALL buyer_for_date('Wendy', 'Cremin', '2023-07-16');
CALL sales_for_month('07-2025');
CALL sales_for_month('10-2023');

-- Testing ranking and metrics on standard sample production partners
CALL top_products_for_seller('Hartmann, Mann and Jones');
CALL seller_running_totals('Hartmann, Mann and Jones');