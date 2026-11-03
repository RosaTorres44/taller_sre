-- Gold para Marketing: % de contactables por país (sin email)
-- Contactable = pasó la calidad (PASS) y tiene email
INSERT OVERWRITE gameday.gold_contactables_por_pais
SELECT
    country_name AS pais,
    region,
    COUNT(*) AS clientes,
    SUM(CASE WHEN dq_status = 'PASS' AND email IS NOT NULL THEN 1 ELSE 0 END) AS contactables,
    ROUND(100.0 * SUM(CASE WHEN dq_status = 'PASS' AND email IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_contactables,
    current_timestamp() AS updated_ts
FROM __SILVER_TABLE__
WHERE dq_status <> 'FAIL_NAME_NULL'
GROUP BY country_name, region;

--Asignación de Owner para cumplir con FinOps, para que cumpla con la gobernanza financiera y de costos de la compañía:
ALTER TABLE gameday.gold_contactables_por_pais SET TAGS ('owner' = 'marketing');
