SELECT l.batch_id,
       s.schema_name + '.' + s.table_name AS source_table,
       l.rows_copied,
       CAST(l.bytes_read / 1048576.0 AS DECIMAL(10, 1)) AS mb_read,
       l.copy_seconds,
       CAST(l.throughput_kbps / 1024.0 AS DECIMAL(10, 2)) AS mb_per_second,
       l.parallel_copies,
       l.watermark_from,
       l.watermark_to,
       l.logged_at
FROM meta.load_log AS l
JOIN meta.source_table AS s ON s.id = l.control_id
ORDER BY l.logged_at, s.id;

SELECT l.batch_id,
       COUNT(*) AS tables_loaded,
       SUM(l.rows_copied) AS rows_copied,
       CAST(SUM(l.bytes_read) / 1073741824.0 AS DECIMAL(10, 2)) AS gb_read,
       SUM(l.copy_seconds) AS copy_seconds_total,
       DATEDIFF(SECOND, MIN(DATEADD(SECOND, -l.copy_seconds, l.logged_at)), MAX(l.logged_at)) AS wall_seconds,
       CAST(SUM(l.bytes_read) / 1048576.0 / NULLIF(DATEDIFF(SECOND, MIN(DATEADD(SECOND, -l.copy_seconds, l.logged_at)), MAX(l.logged_at)), 0) AS DECIMAL(10, 2)) AS mb_per_second_wall
FROM meta.load_log AS l
GROUP BY l.batch_id
ORDER BY MIN(l.logged_at);
