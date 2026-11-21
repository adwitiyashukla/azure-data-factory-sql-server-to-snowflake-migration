USE retail;
GO
CREATE OR ALTER FUNCTION sim.numbers (@n BIGINT)
RETURNS TABLE
AS
RETURN
WITH d AS (
    SELECT v FROM (VALUES (0), (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12), (13), (14), (15)) AS t (v)
)
SELECT TOP (@n) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
FROM d AS a
CROSS JOIN d AS b
CROSS JOIN d AS c
CROSS JOIN d AS e
CROSS JOIN d AS f
CROSS JOIN d AS g
CROSS JOIN d AS h;
GO
CREATE OR ALTER FUNCTION sim.hash3 (@x BIGINT)
RETURNS TABLE
AS
RETURN
WITH k AS (
    SELECT CAST(4294967296 AS BIGINT) AS m
),
s1 AS (
    SELECT (@x * 1597334677 + 1013904223) % m AS a,
           (@x * 2057022787 + 668265263) % m AS b,
           (@x * 1103515245 + 12345) % m AS c,
           m
    FROM k
),
s2 AS (
    SELECT ((a ^ (a / 65536)) * 73244475) % m AS a,
           ((b ^ (b / 65536)) * 73244475) % m AS b,
           ((c ^ (c / 65536)) * 73244475) % m AS c,
           m
    FROM s1
),
s3 AS (
    SELECT ((a ^ (a / 65536)) * 73244475) % m AS a,
           ((b ^ (b / 65536)) * 73244475) % m AS b,
           ((c ^ (c / 65536)) * 73244475) % m AS c
    FROM s2
)
SELECT a ^ (a / 65536) AS h1,
       b ^ (b / 65536) AS h2,
       c ^ (c / 65536) AS h3
FROM s3;
GO
CREATE OR ALTER FUNCTION sim.geo (@h BIGINT)
RETURNS TABLE
AS
RETURN
SELECT CHOOSE(x.i, 'Cincinnati', 'Columbus', 'Cleveland', 'Chicago', 'Indianapolis', 'Louisville', 'Detroit', 'Pittsburgh', 'Nashville', 'Atlanta', 'Dallas', 'Denver', 'Phoenix', 'Seattle', 'Boston') AS city,
       CHOOSE(x.i, 'OH', 'OH', 'OH', 'IL', 'IN', 'KY', 'MI', 'PA', 'TN', 'GA', 'TX', 'CO', 'AZ', 'WA', 'MA') AS state_code
FROM (SELECT CAST(1 + @h % 15 AS INT) AS i) AS x;
GO
CREATE OR ALTER FUNCTION sim.product_of (@product_id BIGINT)
RETURNS TABLE
AS
RETURN
SELECT CHOOSE(CAST(1 + h.h1 % 12 AS INT), 'Audio', 'Bags', 'Beauty', 'Books', 'Garden', 'Grocery', 'Kitchen', 'Pets', 'Shoes', 'Sports', 'Toys', 'Wearables') AS category,
       CAST(1 + (h.h2 % 20000) / 100.0 AS DECIMAL(10, 2)) AS unit_price,
       CAST(CASE WHEN h.h3 % 50 = 0 THEN 0 ELSE 1 END AS BIT) AS active,
       DATEADD(SECOND, -CAST(h.h3 % 63072000 AS INT), CAST('2024-09-01' AS DATETIME2(3))) AS created_at
FROM sim.hash3(@product_id + 100000000) AS h;
GO
CREATE OR ALTER FUNCTION sim.order_of (@order_id BIGINT, @customers BIGINT, @stores BIGINT)
RETURNS TABLE
AS
RETURN
SELECT CAST(1 + h.h1 % @customers AS INT) AS customer_id,
       CAST(1 + (h.h1 / 4194304) % @stores AS INT) AS store_id,
       DATEADD(SECOND, CAST(h.h3 % 63072000 AS INT), CAST('2024-09-01' AS DATETIME2(3))) AS order_ts,
       CASE
           WHEN h.h2 % 20 < 2 THEN 'placed'
           WHEN h.h2 % 20 < 4 THEN 'paid'
           WHEN h.h2 % 20 < 7 THEN 'shipped'
           WHEN h.h2 % 20 < 19 THEN 'delivered'
           ELSE 'cancelled'
       END AS status,
       m.subtotal,
       CAST(ROUND(m.subtotal * 0.0725, 2) AS DECIMAL(10, 2)) AS tax,
       CHOOSE(CAST(1 + (h.h2 / 32) % 3 AS INT), 'web', 'store', 'app') AS channel
FROM sim.hash3(@order_id + 400000000) AS h
CROSS APPLY (SELECT CAST(5 + ((h.h2 / 128) % 50000) / 100.0 AS DECIMAL(12, 2)) AS subtotal) AS m;
GO
CREATE OR ALTER PROCEDURE sim.load_initial @scale INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @customers BIGINT = 20000 * @scale;
    DECLARE @products BIGINT = 2000 * @scale;
    DECLARE @stores BIGINT = 200;
    DECLARE @orders BIGINT = 200000 * @scale;
    DECLARE @items BIGINT = 500000 * @scale;
    DECLARE @shipments BIGINT = 160000 * @scale;
    DECLARE @movements BIGINT = 300000 * @scale;
    DECLARE @batch BIGINT = 500000;
    DECLARE @t0 DATETIME2(3) = '2024-09-01';
    DECLARE @done BIGINT;
    DECLARE @take BIGINT;

    TRUNCATE TABLE catalog.products;
    TRUNCATE TABLE sales.customers;
    TRUNCATE TABLE ops.stores;
    TRUNCATE TABLE sales.orders;
    TRUNCATE TABLE sales.order_items;
    TRUNCATE TABLE sales.payments;
    TRUNCATE TABLE ops.shipments;
    TRUNCATE TABLE ops.inventory_movements;

    SET IDENTITY_INSERT catalog.products ON;
    INSERT INTO catalog.products (product_id, sku, product_name, category, unit_price, active, created_at, updated_at)
    SELECT s.n,
           CONCAT('SKU-', RIGHT(CONCAT('0000000', s.n), 7)),
           CONCAT(p.category, ' item ', s.n),
           p.category,
           p.unit_price,
           p.active,
           p.created_at,
           p.created_at
    FROM sim.numbers(@products) AS s
    CROSS APPLY sim.product_of(s.n) AS p;
    SET IDENTITY_INSERT catalog.products OFF;

    SET IDENTITY_INSERT ops.stores ON;
    INSERT INTO ops.stores (store_id, store_code, city, state_code, opened_date, sqft, created_at, updated_at)
    SELECT s.n,
           CONCAT('ST', RIGHT(CONCAT('000', s.n), 3)),
           g.city,
           g.state_code,
           CAST(DATEADD(DAY, -CAST(h.h3 % 4000 AS INT), @t0) AS DATE),
           5000 + CAST(h.h2 % 40000 AS INT),
           DATEADD(DAY, -CAST(h.h3 % 4000 AS INT), @t0),
           DATEADD(DAY, -CAST(h.h3 % 4000 AS INT), @t0)
    FROM sim.numbers(@stores) AS s
    CROSS APPLY sim.hash3(s.n + 300000000) AS h
    CROSS APPLY sim.geo(h.h1) AS g;
    SET IDENTITY_INSERT ops.stores OFF;

    SET IDENTITY_INSERT sales.customers ON;
    SET @done = 0;
    WHILE @done < @customers
    BEGIN
        SET @take = CASE WHEN @customers - @done < @batch THEN @customers - @done ELSE @batch END;
        INSERT INTO sales.customers (customer_id, email, first_name, last_name, city, state_code, signup_date, loyalty_tier, created_at, updated_at)
        SELECT s.n + @done,
               CONCAT('user', s.n + @done, '@example.com'),
               CHOOSE(CAST(1 + h.h1 % 20 AS INT), 'Aarav', 'Priya', 'Liam', 'Emma', 'Noah', 'Olivia', 'Rohan', 'Ava', 'Ethan', 'Mia', 'Isha', 'Lucas', 'Sofia', 'Arjun', 'Zoe', 'Kabir', 'Nora', 'Dev', 'Leah', 'Sam'),
               CHOOSE(CAST(1 + (h.h1 / 32) % 20 AS INT), 'Shukla', 'Patel', 'Smith', 'Johnson', 'Garcia', 'Nguyen', 'Kim', 'Brown', 'Singh', 'Lopez', 'Miller', 'Chen', 'Davis', 'Khan', 'Wilson', 'Mehta', 'Taylor', 'Rao', 'Moore', 'Ali'),
               g.city,
               g.state_code,
               CAST(c.created_at AS DATE),
               CAST(h.h2 % 4 AS TINYINT),
               c.created_at,
               c.created_at
        FROM sim.numbers(@take) AS s
        CROSS APPLY sim.hash3(s.n + @done + 200000000) AS h
        CROSS APPLY sim.geo(h.h2 / 4) AS g
        CROSS APPLY (SELECT DATEADD(SECOND, -CAST(h.h3 % 63072000 AS INT), @t0) AS created_at) AS c;
        SET @done = @done + @@ROWCOUNT;
    END
    SET IDENTITY_INSERT sales.customers OFF;

    SET IDENTITY_INSERT sales.orders ON;
    SET @done = 0;
    WHILE @done < @orders
    BEGIN
        SET @take = CASE WHEN @orders - @done < @batch THEN @orders - @done ELSE @batch END;
        INSERT INTO sales.orders (order_id, customer_id, store_id, order_ts, status, subtotal, tax, total, channel, created_at, updated_at)
        SELECT s.n + @done,
               o.customer_id,
               o.store_id,
               o.order_ts,
               o.status,
               o.subtotal,
               o.tax,
               o.subtotal + o.tax,
               o.channel,
               o.order_ts,
               o.order_ts
        FROM sim.numbers(@take) AS s
        CROSS APPLY sim.order_of(s.n + @done, @customers, @stores) AS o;
        SET @done = @done + @@ROWCOUNT;
    END
    SET IDENTITY_INSERT sales.orders OFF;

    SET IDENTITY_INSERT sales.order_items ON;
    SET @done = 0;
    WHILE @done < @items
    BEGIN
        SET @take = CASE WHEN @items - @done < @batch THEN @items - @done ELSE @batch END;
        INSERT INTO sales.order_items (order_item_id, order_id, product_id, quantity, unit_price, line_total, created_at, updated_at)
        SELECT s.n + @done,
               x.order_id,
               x.product_id,
               x.quantity,
               p.unit_price,
               x.quantity * p.unit_price,
               o.order_ts,
               o.order_ts
        FROM sim.numbers(@take) AS s
        CROSS APPLY sim.hash3(s.n + @done + 500000000) AS h
        CROSS APPLY (SELECT 1 + (s.n + @done - 1) * @orders / @items AS order_id,
                            CAST(1 + h.h1 % @products AS INT) AS product_id,
                            CAST(1 + h.h2 % 5 AS SMALLINT) AS quantity) AS x
        CROSS APPLY sim.product_of(x.product_id) AS p
        CROSS APPLY sim.order_of(x.order_id, @customers, @stores) AS o;
        SET @done = @done + @@ROWCOUNT;
    END
    SET IDENTITY_INSERT sales.order_items OFF;

    SET IDENTITY_INSERT sales.payments ON;
    SET @done = 0;
    WHILE @done < @orders
    BEGIN
        SET @take = CASE WHEN @orders - @done < @batch THEN @orders - @done ELSE @batch END;
        INSERT INTO sales.payments (payment_id, order_id, method, amount, paid_at, status, created_at, updated_at)
        SELECT s.n + @done,
               s.n + @done,
               CHOOSE(CAST(1 + h.h1 % 4 AS INT), 'card', 'paypal', 'gift_card', 'cash'),
               o.subtotal + o.tax,
               x.paid_at,
               CASE WHEN o.status = 'cancelled' THEN 'refunded' ELSE 'captured' END,
               x.paid_at,
               x.paid_at
        FROM sim.numbers(@take) AS s
        CROSS APPLY sim.hash3(s.n + @done + 600000000) AS h
        CROSS APPLY sim.order_of(s.n + @done, @customers, @stores) AS o
        CROSS APPLY (SELECT DATEADD(SECOND, CAST(h.h2 % 3600 AS INT), o.order_ts) AS paid_at) AS x;
        SET @done = @done + @@ROWCOUNT;
    END
    SET IDENTITY_INSERT sales.payments OFF;

    SET IDENTITY_INSERT ops.shipments ON;
    SET @done = 0;
    WHILE @done < @shipments
    BEGIN
        SET @take = CASE WHEN @shipments - @done < @batch THEN @shipments - @done ELSE @batch END;
        INSERT INTO ops.shipments (shipment_id, order_id, carrier, shipped_at, delivered_at, tracking_no, created_at, updated_at)
        SELECT s.n + @done,
               x.order_id,
               CHOOSE(CAST(1 + h.h1 % 4 AS INT), 'UPS', 'FedEx', 'USPS', 'DHL'),
               y.shipped_at,
               y.delivered_at,
               CONCAT('TRK', RIGHT(CONCAT('000000000000', s.n + @done), 12)),
               y.shipped_at,
               ISNULL(y.delivered_at, y.shipped_at)
        FROM sim.numbers(@take) AS s
        CROSS APPLY sim.hash3(s.n + @done + 700000000) AS h
        CROSS APPLY (SELECT 1 + (s.n + @done - 1) * @orders / @shipments AS order_id) AS x
        CROSS APPLY sim.order_of(x.order_id, @customers, @stores) AS o
        CROSS APPLY (SELECT DATEADD(DAY, 1 + CAST(h.h2 % 3 AS INT), o.order_ts) AS shipped_at) AS z
        CROSS APPLY (SELECT z.shipped_at,
                            CASE WHEN h.h3 % 10 = 0 THEN NULL ELSE DATEADD(DAY, 1 + CAST(h.h3 % 7 AS INT), z.shipped_at) END AS delivered_at) AS y;
        SET @done = @done + @@ROWCOUNT;
    END
    SET IDENTITY_INSERT ops.shipments OFF;

    SET IDENTITY_INSERT ops.inventory_movements ON;
    SET @done = 0;
    WHILE @done < @movements
    BEGIN
        SET @take = CASE WHEN @movements - @done < @batch THEN @movements - @done ELSE @batch END;
        INSERT INTO ops.inventory_movements (movement_id, product_id, store_id, movement_ts, qty_delta, reason, created_at, updated_at)
        SELECT s.n + @done,
               CAST(1 + h.h1 % @products AS INT),
               CAST(1 + h.h2 % @stores AS INT),
               x.movement_ts,
               CASE x.kind
                   WHEN 0 THEN 20 + CAST((h.h2 / 1024) % 200 AS INT)
                   WHEN 1 THEN 1 + CAST((h.h2 / 1024) % 3 AS INT)
                   WHEN 2 THEN CASE WHEN h.h1 % 2 = 0 THEN 1 ELSE -1 END * (1 + CAST((h.h2 / 1024) % 5 AS INT))
                   ELSE -(1 + CAST((h.h2 / 1024) % 5 AS INT))
               END,
               CASE x.kind WHEN 0 THEN 'restock' WHEN 1 THEN 'return' WHEN 2 THEN 'adjustment' ELSE 'sale' END,
               x.movement_ts,
               x.movement_ts
        FROM sim.numbers(@take) AS s
        CROSS APPLY sim.hash3(s.n + @done + 800000000) AS h
        CROSS APPLY (SELECT DATEADD(SECOND, CAST(h.h3 % 63072000 AS INT), @t0) AS movement_ts,
                            CASE WHEN (h.h2 / 256) % 10 < 3 THEN (h.h2 / 256) % 10 ELSE 3 END AS kind) AS x;
        SET @done = @done + @@ROWCOUNT;
    END
    SET IDENTITY_INSERT ops.inventory_movements OFF;

    SELECT 'catalog.products' AS table_name, COUNT_BIG(*) AS row_count FROM catalog.products
    UNION ALL SELECT 'sales.customers', COUNT_BIG(*) FROM sales.customers
    UNION ALL SELECT 'ops.stores', COUNT_BIG(*) FROM ops.stores
    UNION ALL SELECT 'sales.orders', COUNT_BIG(*) FROM sales.orders
    UNION ALL SELECT 'sales.order_items', COUNT_BIG(*) FROM sales.order_items
    UNION ALL SELECT 'sales.payments', COUNT_BIG(*) FROM sales.payments
    UNION ALL SELECT 'ops.shipments', COUNT_BIG(*) FROM ops.shipments
    UNION ALL SELECT 'ops.inventory_movements', COUNT_BIG(*) FROM ops.inventory_movements;
END
GO
CREATE OR ALTER PROCEDURE sim.add_day @orders INT = 20000
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIME2(3) = SYSUTCDATETIME();
    DECLARE @customers BIGINT = (SELECT COUNT_BIG(*) FROM sales.customers);
    DECLARE @products BIGINT = (SELECT COUNT_BIG(*) FROM catalog.products);
    DECLARE @stores BIGINT = (SELECT COUNT_BIG(*) FROM ops.stores);
    DECLARE @first_order BIGINT = (SELECT ISNULL(MAX(order_id), 0) + 1 FROM sales.orders);
    DECLARE @salt BIGINT = @first_order + 900000000;
    DECLARE @day INT = DATEPART(DAYOFYEAR, @now);

    INSERT INTO sales.orders (customer_id, store_id, order_ts, status, subtotal, tax, total, channel, created_at, updated_at)
    SELECT CAST(1 + h.h1 % @customers AS INT),
           CAST(1 + (h.h1 / 4194304) % @stores AS INT),
           x.order_ts,
           CASE WHEN h.h2 % 10 < 3 THEN 'placed' WHEN h.h2 % 10 < 8 THEN 'paid' ELSE 'shipped' END,
           x.subtotal,
           CAST(ROUND(x.subtotal * 0.0725, 2) AS DECIMAL(10, 2)),
           x.subtotal + CAST(ROUND(x.subtotal * 0.0725, 2) AS DECIMAL(10, 2)),
           CHOOSE(CAST(1 + (h.h2 / 32) % 3 AS INT), 'web', 'store', 'app'),
           @now,
           @now
    FROM sim.numbers(@orders) AS s
    CROSS APPLY sim.hash3(s.n + @salt) AS h
    CROSS APPLY (SELECT DATEADD(SECOND, -CAST(h.h3 % 86400 AS INT), @now) AS order_ts,
                        CAST(5 + ((h.h2 / 128) % 50000) / 100.0 AS DECIMAL(12, 2)) AS subtotal) AS x;

    INSERT INTO sales.order_items (order_id, product_id, quantity, unit_price, line_total, created_at, updated_at)
    SELECT o.order_id,
           p.product_id,
           q.quantity,
           p.unit_price,
           q.quantity * p.unit_price,
           @now,
           @now
    FROM sales.orders AS o
    CROSS APPLY sim.numbers(1 + o.order_id % 4) AS s
    CROSS APPLY sim.hash3(o.order_id * 8 + s.n + @salt) AS h
    CROSS APPLY (SELECT CAST(1 + h.h2 % 5 AS SMALLINT) AS quantity) AS q
    JOIN catalog.products AS p ON p.product_id = 1 + h.h1 % @products
    WHERE o.order_id >= @first_order;

    INSERT INTO sales.payments (order_id, method, amount, paid_at, status, created_at, updated_at)
    SELECT o.order_id,
           CHOOSE(CAST(1 + h.h1 % 4 AS INT), 'card', 'paypal', 'gift_card', 'cash'),
           o.total,
           DATEADD(SECOND, CAST(h.h2 % 3600 AS INT), o.order_ts),
           'captured',
           @now,
           @now
    FROM sales.orders AS o
    CROSS APPLY sim.hash3(o.order_id + @salt + 1) AS h
    WHERE o.order_id >= @first_order AND o.status <> 'placed';

    INSERT INTO ops.shipments (order_id, carrier, shipped_at, delivered_at, tracking_no, created_at, updated_at)
    SELECT o.order_id,
           CHOOSE(CAST(1 + h.h1 % 4 AS INT), 'UPS', 'FedEx', 'USPS', 'DHL'),
           @now,
           NULL,
           CONCAT('TRK', RIGHT(CONCAT('000000000000', o.order_id), 12)),
           @now,
           @now
    FROM sales.orders AS o
    CROSS APPLY sim.hash3(o.order_id + @salt + 2) AS h
    WHERE o.order_id >= @first_order AND o.status = 'shipped';

    INSERT INTO ops.inventory_movements (product_id, store_id, movement_ts, qty_delta, reason, created_at, updated_at)
    SELECT i.product_id,
           o.store_id,
           o.order_ts,
           -i.quantity,
           'sale',
           @now,
           @now
    FROM sales.order_items AS i
    JOIN sales.orders AS o ON o.order_id = i.order_id
    WHERE o.order_id >= @first_order;

    UPDATE c
    SET loyalty_tier = (loyalty_tier + 1) % 4,
        updated_at = @now
    FROM sales.customers AS c
    WHERE c.customer_id % 100 = @day % 100;

    UPDATE s
    SET delivered_at = @now,
        updated_at = @now
    FROM ops.shipments AS s
    WHERE s.delivered_at IS NULL
      AND s.shipped_at < DATEADD(DAY, -2, @now)
      AND s.shipment_id % 3 = @day % 3;

    UPDATE o
    SET status = 'delivered',
        updated_at = @now
    FROM sales.orders AS o
    JOIN ops.shipments AS s ON s.order_id = o.order_id
    WHERE s.delivered_at = @now
      AND o.status <> 'delivered';

    SELECT 'catalog.products' AS table_name, COUNT_BIG(*) AS changed_rows FROM catalog.products WHERE updated_at = @now
    UNION ALL SELECT 'sales.customers', COUNT_BIG(*) FROM sales.customers WHERE updated_at = @now
    UNION ALL SELECT 'ops.stores', COUNT_BIG(*) FROM ops.stores WHERE updated_at = @now
    UNION ALL SELECT 'sales.orders', COUNT_BIG(*) FROM sales.orders WHERE updated_at = @now
    UNION ALL SELECT 'sales.order_items', COUNT_BIG(*) FROM sales.order_items WHERE updated_at = @now
    UNION ALL SELECT 'sales.payments', COUNT_BIG(*) FROM sales.payments WHERE updated_at = @now
    UNION ALL SELECT 'ops.shipments', COUNT_BIG(*) FROM ops.shipments WHERE updated_at = @now
    UNION ALL SELECT 'ops.inventory_movements', COUNT_BIG(*) FROM ops.inventory_movements WHERE updated_at = @now;
END
GO
