-- Carga incremental: solo inserta clientes nuevos (MERGE por customer_id)
MERGE INTO __SILVER_TABLE__ AS t
USING (
    SELECT
        ingest_ts,
        customer_id,
        customer_name,
        email,
        status,
        payload,
        dq_is_name_null,
        dq_is_underage,
        dq_status,
        b.country_code,
        p.country_name,
        p.region
    FROM (
        SELECT
            CAST(ingest_ts AS TIMESTAMP) AS ingest_ts,
            get_json_object (raw_payload, '$.customer_id') AS customer_id,
            NULLIF(TRIM(get_json_object (raw_payload, '$.name')), '') AS customer_name,
            NULLIF(TRIM(get_json_object (raw_payload, '$.email')), '') AS email,
            CASE
                WHEN NULLIF(TRIM(get_json_object (raw_payload, '$.name')), '') IS NULL THEN 'FAIL_NAME_NULL'
                WHEN CAST(get_json_object (raw_payload, '$.age') AS INT) < 18 THEN 'WARN_UNDERAGE'
                ELSE 'PASS'
            END AS status,
            raw_payload AS payload,
            NULLIF(TRIM(get_json_object (raw_payload, '$.name')), '') IS NULL AS dq_is_name_null,
            COALESCE(CAST(get_json_object (raw_payload, '$.age') AS INT) < 18, FALSE) AS dq_is_underage,
            CASE
                WHEN NULLIF(TRIM(get_json_object (raw_payload, '$.name')), '') IS NULL THEN 'FAIL_NAME_NULL'
                WHEN CAST(get_json_object (raw_payload, '$.age') AS INT) < 18 THEN 'WARN_UNDERAGE'
                ELSE 'PASS'
            END AS dq_status,
            UPPER(TRIM(get_json_object (raw_payload, '$.country'))) AS country_code,
            ROW_NUMBER() OVER (
                PARTITION BY get_json_object (raw_payload, '$.customer_id')
                ORDER BY ingest_ts ASC, raw_payload ASC
            ) AS rn
        FROM gameday.bronze_customers
    ) AS b
    LEFT JOIN gameday.ref_paises AS p
        ON b.country_code = p.country_code
    WHERE b.rn = 1
) AS s
ON t.customer_id = s.customer_id
-- 1. SI EL CLIENTE YA EXISTE, ACTUALIZA SUS DATOS (INCLUYENDO EL PAÍS CORREGIDO)
WHEN MATCHED THEN UPDATE SET
    t.country_code = s.country_code,
    t.country_name = s.country_name,
    t.region = s.region,
    t.status = s.status,
    t.dq_status = s.dq_status,
    t.email = s.email,
    t.customer_name = s.customer_name
-- 2. SI EL CLIENTE ES NUEVO, LO INSERTA
WHEN NOT MATCHED THEN INSERT (
    ingest_ts, customer_id, customer_name, email, status, payload,
    dq_is_name_null, dq_is_underage, dq_status, country_code, country_name, region
) VALUES (
    s.ingest_ts, s.customer_id, s.customer_name, s.email, s.status, s.payload,
    s.dq_is_name_null, s.dq_is_underage, s.dq_status, s.country_code, s.country_name, s.region
);
