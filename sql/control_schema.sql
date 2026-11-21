CREATE SCHEMA meta;
GO
CREATE TABLE meta.source_table (
    id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    schema_name SYSNAME NOT NULL,
    table_name SYSNAME NOT NULL,
    key_column SYSNAME NOT NULL,
    watermark_column SYSNAME NOT NULL,
    target_table SYSNAME NOT NULL,
    parallel_copies TINYINT NOT NULL DEFAULT 1,
    enabled BIT NOT NULL DEFAULT 1,
    watermark_value DATETIME2(3) NOT NULL DEFAULT '1900-01-01',
    last_run_id UNIQUEIDENTIFIER NULL,
    last_run_at DATETIME2(0) NULL,
    CONSTRAINT uq_source_table UNIQUE (schema_name, table_name)
);
CREATE TABLE meta.load_log (
    log_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    control_id INT NOT NULL,
    run_id UNIQUEIDENTIFIER NOT NULL,
    batch_id VARCHAR(64) NOT NULL,
    watermark_from DATETIME2(3) NOT NULL,
    watermark_to DATETIME2(3) NOT NULL,
    rows_read BIGINT NOT NULL,
    rows_copied BIGINT NOT NULL,
    bytes_read BIGINT NOT NULL,
    copy_seconds INT NOT NULL,
    throughput_kbps FLOAT NOT NULL,
    parallel_copies INT NOT NULL,
    folder_path VARCHAR(400) NOT NULL,
    logged_at DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME()
);
GO
CREATE PROCEDURE meta.usp_finish_load
    @control_id INT,
    @run_id UNIQUEIDENTIFIER,
    @batch_id VARCHAR(64),
    @watermark_from DATETIME2(3),
    @watermark_to DATETIME2(3),
    @rows_read BIGINT,
    @rows_copied BIGINT,
    @bytes_read BIGINT,
    @copy_seconds INT,
    @throughput_kbps FLOAT,
    @parallel_copies INT,
    @folder_path VARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO meta.load_log (control_id, run_id, batch_id, watermark_from, watermark_to, rows_read, rows_copied, bytes_read, copy_seconds, throughput_kbps, parallel_copies, folder_path)
    VALUES (@control_id, @run_id, @batch_id, @watermark_from, @watermark_to, @rows_read, @rows_copied, @bytes_read, @copy_seconds, @throughput_kbps, @parallel_copies, @folder_path);

    UPDATE meta.source_table
    SET watermark_value = @watermark_to,
        last_run_id = @run_id,
        last_run_at = SYSUTCDATETIME()
    WHERE id = @control_id;
END
GO
INSERT INTO meta.source_table (schema_name, table_name, key_column, watermark_column, target_table, parallel_copies)
VALUES ('catalog', 'products', 'product_id', 'updated_at', 'PRODUCTS', 1),
       ('sales', 'customers', 'customer_id', 'updated_at', 'CUSTOMERS', 2),
       ('ops', 'stores', 'store_id', 'updated_at', 'STORES', 1),
       ('sales', 'orders', 'order_id', 'updated_at', 'ORDERS', 4),
       ('sales', 'order_items', 'order_item_id', 'updated_at', 'ORDER_ITEMS', 4),
       ('sales', 'payments', 'payment_id', 'updated_at', 'PAYMENTS', 4),
       ('ops', 'shipments', 'shipment_id', 'updated_at', 'SHIPMENTS', 4),
       ('ops', 'inventory_movements', 'movement_id', 'updated_at', 'INVENTORY_MOVEMENTS', 4);
GO
DECLARE @sid VARBINARY(16) = CONVERT(VARBINARY(16), CAST('$(adf_client_id)' AS UNIQUEIDENTIFIER));
DECLARE @sql NVARCHAR(MAX) = N'CREATE USER [adf-adfmig-as] WITH SID = ' + CONVERT(NVARCHAR(34), @sid, 1) + N', TYPE = E;';
EXEC sys.sp_executesql @sql;
GO
ALTER ROLE db_datareader ADD MEMBER [adf-adfmig-as];
ALTER ROLE db_datawriter ADD MEMBER [adf-adfmig-as];
GRANT EXECUTE ON SCHEMA::meta TO [adf-adfmig-as];
GO
