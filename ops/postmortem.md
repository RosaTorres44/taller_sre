# Postmortem: Campañas Erradas entre países Perú-Chile

> Sin culpables: buscamos qué falló en el proceso, no quién se equivocó.

**Equipo y roles:** Comandante: Renzo Huarcaya · Operador: Gianire Vasquez · Comunicador: José Ávalos

## Resumen

Se produjo un desfase en el mapeo de países entre Perú y Chile debido a un error en el archivo de referencia, el cual no se propagó correctamente a través de las capas Silver y Gold por falta de lógica de actualización (`UPDATE`) en el `MERGE`. Afectó directamente a las campañas de marketing dirigidas y se resolvió actualizando los scripts de transformación en GitHub y automatizando la gobernanza de tags FinOps.

## Impacto

- ¿Qué clientes, tablas o procesos se vieron afectados? ¿Cuántos?
- Se vieron afectados 4 clientes: Tomás, Isabel, Fernanda y Gabriel.
- Se vieron afectadas 3 tablas: gameday.gold_contactables_por_pais, gameday.silver_customers_v2 y gameday.ref_paises

## Línea de tiempo

| Hora | Qué pasó |
| --- | --- |
| 2026-11-01T19:12:14.997+00:00 | Entra el cambio en el repositorio |
| 2026-11-01T19:14:24.365+00:00 | Inicio del incidente (preparar-produccion) |
| 2026-11-01T19:24:24.365+00:00 | Detectamos la causa (desfase en `ref_paises` y falta de actualización en Silver/Gold) |
| 2026-11-01T19:34:24.365+00:00 | Contenemos (ajuste de scripts SQL con `MERGE UPDATE` y tags de FinOps) |
| 2026-11-01T21:07:33.510+00:00 | Primer verificar en verde |

**MTTR:** 113.15 minutos (desde el inicio del incidente a las 19:14:24 hasta el primer verificar en verde a las 21:07:33).

## Causa raíz

- ¿Qué cambio lo causó? ¿Por qué los checks no lo frenaron?
- El incidente fue causado por una alteración en el mapeo de países de referencia que dejó inconsistencias en los registros históricos. Los checks iniciales no lo frenaron porque el script de la capa Silver (`MERGE`) carecía de la cláusula de actualización (`WHEN MATCHED THEN UPDATE`), por lo que los registros existentes ignoraron las correcciones del catálogo maestro, y la capa Gold carecía de la validación de tags requerida por FinOps.

## Qué funcionó y qué no

* **Funcionó:** La capacidad de reacción del equipo, el aislamiento del problema mediante los workflows de verificación, y el uso de arquitecturas declarativas en Git para corregir de raíz la persistencia de datos y metadatos.
* **No funcionó:** La dependencia inicial de correcciones manuales en la consola de Databricks que no se integraban de forma idempotente al código fuente del pipeline.

## Acción preventiva

- Check nuevo en `framework/validation/validate_silver.py`: ** Valida que no existan registros en la tabla Silver cuyo country_name sea nulo, asegurando que el cruce con la tabla maestra de referencias (ref_paises) se haya realizado de manera exitosa y sin dejar clientes huérfanos.
- ¿Lo probaron? ¿Falla si vuelven a aplicar el cambio del viernes? ** Sí. Al activarse esta validación, si vuelven a introducir un error en el archivo de referencia o eliminan el mapeo, el script arrojará inmediatamente un ValueError y registrará el estado FAIL en ops_dq_results, frenando el avance hacia la capa Gold.
- Otras acciones (con dueño y fecha): ** Automatizar la inyección de tags de propietario en Unity Catalog directamente desde los scripts de despliegue Gold. *(Dueño: Data Engineering / Fecha: Noviembre 2026)*
