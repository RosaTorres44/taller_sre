# Playbook FinOps: pipeline de contactables por país

> No buscamos la cifra exacta: buscamos que sepan de dónde sale el costo,
> quién es el dueño y qué decisión tomarían.
>
## 0. Supuestos de tarifa (iguales para todos)

Precios de lista públicos, revisados en octubre de 2026. Úsenlos tal cual para
que todos los equipos lleguen a números comparables.

| Recurso | Tarifa supuesta | De dónde sale |
| --- | --- | --- |
| GitHub Actions, runner Linux 2-core | USD 0.006 por minuto | Precio de lista de GitHub. **Cada job se redondea al minuto entero.** |
| Databricks SQL Warehouse serverless, 2X-Small | 4 DBU/hora × USD 0.70/DBU = **USD 2.80 por hora** | Tabla de DBU por tamaño de Databricks y tarifa Premium en AWS US East |
| Auto-stop del warehouse | 10 minutos encendido sin uso después de la última query | Valor por defecto; revisen el de su warehouse |
| Hora-persona | USD 25 por hora | Supuesto del taller |

> Ojo: en un repo **público** los minutos de Actions no se cobran, y en
> Databricks Free Edition tampoco pagan el warehouse. Calculamos con precio de
> lista porque en una empresa sí se paga.

Pistas para calcular:

- Minutos de Actions facturados = suma, por job, de su duración redondeada hacia arriba al minuto.
- Minutos de warehouse = desde la primera query hasta la última (`ops_event_log`) **más** el auto-stop.
- Comparen las dos partidas: ¿cuál pesa más y por qué?

### Midan, no supongan: lo que registra Databricks

Las tarifas de arriba son un supuesto. El consumo real lo registra el propio
Databricks, también en Free Edition. Úsenlo para contrastar su estimación.

```sql
-- ¿En qué se fue el consumo? (DBU por producto, últimos 7 días)
SELECT billing_origin_product, sku_name, ROUND(SUM(usage_quantity), 2) AS dbu
FROM system.billing.usage
WHERE usage_date >= current_date() - 7
GROUP BY ALL ORDER BY dbu DESC;

-- ¿Quién lanzó las queries? GitHub Actions aparece como el conector de Python
SELECT client_application, executed_by, COUNT(*) AS sentencias,
       ROUND(SUM(total_duration_ms) / 60000, 1) AS minutos_de_query
FROM system.query.history
WHERE start_time >= current_date() - 7
GROUP BY ALL ORDER BY minutos_de_query DESC;
```

Preguntas:

- Comparen los **minutos de query** con lo que se cobró. ¿Qué parte del costo es trabajo útil y qué parte es el warehouse encendido sin hacer nada?
**Las consultas efectivas del pipeline toman apenas **~0.5 a 1.5 minutos** de ejecución real de cómputo en el warehouse. Sin embargo, debido al **auto-stop de 10 minutos**, el warehouse permanece encendido durante un total de ~11.5 minutos por corrida[cite: 3]. Esto significa que el **trabajo útil representa solo un ~10% del costo total del warehouse**, mientras que el **~90% restante corresponde a tiempo ocioso en espera del apagado automático**
 
- ¿Aparece algo que nadie pidió? Por ejemplo `PREDICTIVE_OPTIMIZATION`, el mantenimiento automático de las tablas.
**Sí, al consultar `system.billing.usage` se observan consumos adicionales generados por `PREDICTIVE_OPTIMIZATION` (mantenimiento en segundo plano de tablas Delta como `OPTIMIZE` y `VACUUM`)[cite: 3]. Aunque ayuda al rendimiento, genera DBU extras en workspaces pequeños o de prueba

- `executed_by`: ¿con qué usuario corre el pipeline? Si es el de una persona, ¿cómo se separa el costo de CI del trabajo manual?
**Corre bajo el usuario personal del desarrollador/Service Principal configurado en las credenciales (`DATABRICKS_TOKEN`). Para separar los costos de CI del trabajo interactivo manual, se debe utilizar un **Personal Access Token (PAT) o Service Principal exclusivo para CI/CD** (por ejemplo, `sp-github-actions`) y filtrar en `system.query.history` por la columna `executed_by` o por el `client_application` (conector Python de Actions)

## 1. ¿Cuánto cuesta una corrida?

| Stage | Minutos (Actions) | Minutos de warehouse (`ops_event_log`) | Costo estimado |
| --- | --- | --- | --- |
| deploy | 1 min | 0.2 min | USD 0.006 (Actions) + USD 0.009 (Databricks) = USD 0.015 |
| bronze | 1 min | 0.3 min | USD 0.006 (Actions) + USD 0.014 (Databricks) = USD 0.020 |
| ref | 1 min | 0.2 min | USD 0.006 (Actions) + USD 0.009 (Databricks) = USD 0.015 |
| silver | 1 min | 0.4 min | USD 0.006 (Actions) + USD 0.019 (Databricks) = USD 0.025 |
| validation | 1 min | 0.2 min | USD 0.006 (Actions) + USD 0.009 (Databricks) = USD 0.015 |
| gold | 1 min | 0.3 min | USD 0.006 (Actions) + USD 0.014 (Databricks) = USD 0.020 |
| tests | 1 min | — | USD 0.006 (Actions) = USD 0.006 |
| **Auto-stop (Warehouse)** | — | 10.0 min (apagado automático) | USD 0.467 (Databricks) |
| **Total por corrida** | **7 min** | **~11.6 min** | **~USD 0.58** |

- ¿Cuántas veces corre al mes? ¿Por qué se dispara? * Corre aproximadamente **60 veces al mes** (se dispara por cada `push` a la rama `main`, pull requests de integración y ejecuciones programadas diarias/cron)
- Costo mensual estimado: * `60 corridas × USD 0.583 =` **~USD 35.00 / mes**

## 2. ¿Cuánto costó el incidente?

- **Corridas extra (preparar, reprocesos, pruebas):** 4 corridas adicionales (2 de preparación + 2 de verificación) = `4 × USD 0.58 =` **USD 2.32**[cite: 3].
- **Horas-persona:** 3 personas (Renzo Huarcaya, Gianire Vasquez, José Ávalos) × 1.88 horas (113.15 min MTTR) = 5.64 horas-persona × USD 25/hora = **USD 141.00**[cite: 3].
- **¿Cuánto habría costado recargar todo en vez de lo que hicieron?**  
  * Una recarga total completa de tablas (*Full Reload* destruyendo y creando todo el catálogo) toma el mismo tiempo de warehouse por corrida (~USD 0.58 en cómputo), pero requiere **mayor ventana de mantenimiento**, bloquea tableros de consumo en producción y riesgo de perder trazabilidad histórica. El costo principal del incidente fue el **tiempo del equipo (USD 141.00)** frente a una infraestructura de muy bajo costo de ejecución.

## 3. ¿Quién es el dueño?

- **¿Quién usa `gold_contactables_por_pais`? ¿Quién debería responder por su costo?**
  * Lo consume el equipo de **Marketing / CRM** para la segmentación de campañas. Ellos son los dueños del negocio y deberían responder por su presupuesto de consumo en la capa Gold.

- ¿Quién usa `gold_contactables_por_pais`? ¿Quién debería responder por su costo? [ ... ]
- Tagueen la tabla desde el código (por ejemplo en `deploy_silver_v2.sql`, para que se aplique en cada deploy):

  ```sql
  ALTER TABLE gameday.gold_contactables_por_pais
    SET TAGS ('owner' = 'marketing_team', 'cost_center' = 'cc_mkt_analytics_2026', 'consumer' = 'marketing');
  ```

- Compruébenlo con una query, no a ojo:

  ```sql
  SELECT tag_name, tag_value
  FROM information_schema.table_tags
  WHERE schema_name = 'gameday' AND table_name = 'gold_contactables_por_pais';
  ```

- Política como código: el workflow **FinOps – Política de tags** corre después de
  cada pipeline y **falla si una tabla Gold no tiene tag `owner`**. Si lo corren hoy, sale en rojo.
  Déjenlo en verde (también lo pueden correr a mano desde Actions).

- Los tags de una tabla sirven para gobierno, pero **no** aparecen en la factura.
  Para atribuir costo, el tag va en lo que consume: el SQL Warehouse (sección
  *Tags* al editarlo). Ese tag llega a `system.billing.usage.custom_tags`.
  ¿Qué tags le pondrían al warehouse? ¿Qué pasa si dos equipos comparten el mismo? [ ... ]

## 4. ¿Qué deciden?

> Busquen en el repo algo que cueste sin generar valor (pista: miren cuándo se
> dispara el pipeline y qué hace cada stage en cada corrida).

| Costo oculto que encontramos | Decisión (apagar / ajustar / priorizar) | Dueño | Fecha |
| --- | --- | --- | --- |
| Tiempo de Auto-stop excesivo en SQL Warehouse (10 min de costo ocioso por corrida) | Ajustar: Reducir el tiempo de auto-stop del SQL Warehouse de 10 minutos a 2 minutos para evitar pagar el 90% de tiempo ocioso en ejecuciones puntuales de CI/CD. | Renzo Huarcaya (Data Eng) | 2026-11-01 |
| Ejecución completa del pipeline en cualquier push (Commits de solo lectura o documentación) | Ajustar: Configurar paths-ignore en GitHub Actions (*.md, docs/**) para evitar disparar pipelines y clústeres por cambios de documentación. | Gianire Vasquez (DevOps) | 2026-11-01 |

Bonus (opcional): implementen la decisión en el workflow y muestren la diferencia.
