EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'max server memory (MB)', 2048;
RECONFIGURE;
GO
IF DB_ID('retail') IS NOT NULL
BEGIN
    ALTER DATABASE retail SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE retail;
END
GO
CREATE DATABASE retail;
GO
ALTER DATABASE retail SET RECOVERY SIMPLE;
GO
USE retail;
GO
CREATE SCHEMA sales;
GO
CREATE SCHEMA catalog;
GO
CREATE SCHEMA ops;
GO
CREATE SCHEMA sim;
GO
CREATE TABLE catalog.products (
    product_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    sku VARCHAR(20) NOT NULL,
    product_name VARCHAR(80) NOT NULL,
    category VARCHAR(40) NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    active BIT NOT NULL,
    created_at DATETIME2(3) NOT NULL,
    updated_at DATETIME2(3) NOT NULL
);
CREATE TABLE sales.customers (
    customer_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    email VARCHAR(120) NOT NULL,
    first_name VARCHAR(40) NOT NULL,
    last_name VARCHAR(40) NOT NULL,
    city VARCHAR(60) NOT NULL,
    state_code CHAR(2) NOT NULL,
    signup_date DATE NOT NULL,
    loyalty_tier TINYINT NOT NULL,
    created_at DATETIME2(3) NOT NULL,
    updated_at DATETIME2(3) NOT NULL
);
CREATE TABLE ops.stores (
    store_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    store_code VARCHAR(10) NOT NULL,
    city VARCHAR(60) NOT NULL,
    state_code CHAR(2) NOT NULL,
    opened_date DATE NOT NULL,
    sqft INT NOT NULL,
    created_at DATETIME2(3) NOT NULL,
    updated_at DATETIME2(3) NOT NULL
);
CREATE TABLE sales.orders (
    order_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    customer_id INT NOT NULL,
    store_id INT NOT NULL,
    order_ts DATETIME2(3) NOT NULL,
    status VARCHAR(12) NOT NULL,
    subtotal DECIMAL(12,2) NOT NULL,
    tax DECIMAL(10,2) NOT NULL,
    total DECIMAL(12,2) NOT NULL,
    channel VARCHAR(10) NOT NULL,
    created_at DATETIME2(3) NOT NULL,
    updated_at DATETIME2(3) NOT NULL
);
CREATE TABLE sales.order_items (
    order_item_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    order_id BIGINT NOT NULL,
    product_id INT NOT NULL,
    quantity SMALLINT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    line_total DECIMAL(12,2) NOT NULL,
    created_at DATETIME2(3) NOT NULL,
    updated_at DATETIME2(3) NOT NULL
);
CREATE TABLE sales.payments (
    payment_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    order_id BIGINT NOT NULL,
    method VARCHAR(12) NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    paid_at DATETIME2(3) NOT NULL,
    status VARCHAR(12) NOT NULL,
    created_at DATETIME2(3) NOT NULL,
    updated_at DATETIME2(3) NOT NULL
);
CREATE TABLE ops.shipments (
    shipment_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    order_id BIGINT NOT NULL,
    carrier VARCHAR(16) NOT NULL,
    shipped_at DATETIME2(3) NOT NULL,
    delivered_at DATETIME2(3) NULL,
    tracking_no VARCHAR(30) NOT NULL,
    created_at DATETIME2(3) NOT NULL,
    updated_at DATETIME2(3) NOT NULL
);
CREATE TABLE ops.inventory_movements (
    movement_id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    product_id INT NOT NULL,
    store_id INT NOT NULL,
    movement_ts DATETIME2(3) NOT NULL,
    qty_delta INT NOT NULL,
    reason VARCHAR(16) NOT NULL,
    created_at DATETIME2(3) NOT NULL,
    updated_at DATETIME2(3) NOT NULL
);
GO
CREATE INDEX ix_products_updated_at ON catalog.products (updated_at);
CREATE INDEX ix_customers_updated_at ON sales.customers (updated_at);
CREATE INDEX ix_stores_updated_at ON ops.stores (updated_at);
CREATE INDEX ix_orders_updated_at ON sales.orders (updated_at);
CREATE INDEX ix_order_items_updated_at ON sales.order_items (updated_at);
CREATE INDEX ix_payments_updated_at ON sales.payments (updated_at);
CREATE INDEX ix_shipments_updated_at ON ops.shipments (updated_at);
CREATE INDEX ix_inventory_movements_updated_at ON ops.inventory_movements (updated_at);
GO
DROP LOGIN IF EXISTS adfmig_reader;
GO
CREATE LOGIN adfmig_reader WITH PASSWORD = '$(reader_password)';
GO
CREATE USER adfmig_reader FOR LOGIN adfmig_reader;
ALTER ROLE db_datareader ADD MEMBER adfmig_reader;
GO
