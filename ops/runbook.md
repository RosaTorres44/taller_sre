# Runbook: <nombre del incidente>

> Un runbook es lo que haría cualquier persona del equipo si esto vuelve a
> pasar a las 3 a. m. Escríbanlo para alguien que no estuvo hoy.

## Cómo me doy cuenta

- ¿Qué señal o alerta lo muestra? ¿Qué query o tabla revisan primero?
* La alerta se evidencia en el workflow de verificación de GitHub Actions cuando el criterio **"Recuperar"** falla (muestra 0/25 puntos o el conteo de clientes con país mal es mayor a 0).
* **Query/Tabla a revisar primero:** Consultar la tabla de auditoría de calidad y la capa Silver para detectar registros huérfanos con país nulo:
    `SELECT COUNT(*) FROM gameday.silver_customers_v2 WHERE country_name IS NULL;`

## Contener (que no empeore)

- ¿Qué apagan o retienen para no publicar más datos malos? ¿Cómo lo hacen?
* Se detiene la ejecución automática o se pausa el pipeline principal de despliegue (`Game day – Preparar producción`) para evitar que se sigan propagando datos con errores de mapeo hacia la capa Gold de consumo de negocio.
* **Cómo lo hacen:** Pausando el flujo en GitHub Actions o revirtiendo temporalmente el último commit erróneo en la rama principal.

## Recuperar

1. Código: ** `git revert <commit_hash>` o actualizar directamente los scripts de transformación en GitHub agregando la cláusula de actualización `WHEN MATCHED THEN UPDATE` en el `MERGE` de Silver y el cruce correcto en Gold.
2. Datos: ** Volver a la versión corregida del archivo de referencia de países (`ref_paises.csv`) y asegurar que los registros afectados se actualicen mediante la recarga de la tabla o la ejecución del `MERGE`.
3. Reproceso: ** Ejecutar el workflow `Game day – Preparar producción` para refrescar de extremo a extremo las capas (Bronze ➔ Silver ➔ Gold). Se garantiza que no se duplica gracias a la clave de partición y las llaves primarias en el `MERGE` por `customer_id`.
4. Pendientes: ** Ningún lote retenido; al correr el flujo completo con el código corregido, se liberan y publican automáticamente los datos limpios en la capa Gold con sus tags de FinOps correspondientes.

## Cómo confirmo que volvimos a un estado bueno

* Se ejecuta el workflow de verificación (`Game day – Verificación`).
* **Qué número debe cuadrar:** El puntaje técnico debe alcanzar el 100% y el criterio **"Recuperar"** debe mostrar `25/25` puntos, indicando que cero clientes tienen el país mal y que la capa Gold cuadra perfectamente con los 26/26 registros de Silver.

## A quién aviso

| Momento | A quién | Qué le digo |
| --- | --- | --- |
| Al detectar | Comandante de Incidente / Líder Técnico (Renzo Huarcaya)| "Alerta roja: Se detectó una discrepancia de mapeo de países en la capa Silver/Gold afectando las métricas de campañas." |
| Al recuperar | Equipo de Operaciones y Stakeholders de Marketing | "Incidente resuelto: Pipeline reprocesado exitosamente, validaciones de calidad en verde y tablero Gold sincronizado." |
