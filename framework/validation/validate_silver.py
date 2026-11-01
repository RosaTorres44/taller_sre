import os
from databricks import sql
from datetime import datetime, timezone

HOST = os.environ["DATABRICKS_HOST"]
HTTP_PATH = os.environ["DATABRICKS_HTTP_PATH"]
TOKEN = os.environ["DATABRICKS_TOKEN"]

RUN_ID = os.environ.get("RUN_ID", "manual")
SILVER_TABLE = os.environ.get("SILVER_TABLE", "gameday.silver_customers_v2")

def fetch_one(cur, stmt: str):
    cur.execute(stmt)
    return cur.fetchall()[0][0]

def main():
    checked_at = datetime.now(timezone.utc).isoformat()
    print(f"✅ Validating table: {SILVER_TABLE}")
    print(f"✅ RUN_ID: {RUN_ID}")

    with sql.connect(server_hostname=HOST, http_path=HTTP_PATH, access_token=TOKEN) as conn:
        with conn.cursor() as cur:
            total = fetch_one(cur, f"SELECT COUNT(*) FROM {SILVER_TABLE}")
            name_null = fetch_one(cur, f"SELECT COUNT(*) FROM {SILVER_TABLE} WHERE dq_is_name_null = true")
            underage = fetch_one(cur, f"SELECT COUNT(*) FROM {SILVER_TABLE} WHERE dq_is_underage = true")

            # NUEVO CHECK: Detecta registros en Silver sin un mapeo de país válido (huérfanos de ref_paises)
            missing_country = fetch_one(cur, f"SELECT COUNT(*) FROM {SILVER_TABLE} WHERE country_name IS NULL")
            
            # Guarda resultados en ops_dq_results
            cur.execute(
                "INSERT INTO gameday.ops_dq_results VALUES (?, current_timestamp(), ?, 'total_rows', 'INFO', ?, ?)",
                (RUN_ID, SILVER_TABLE, float(total), f"checked_at={checked_at}")
            )

            cur.execute(
                "INSERT INTO gameday.ops_dq_results VALUES (?, current_timestamp(), ?, 'name_null_count', ?, ?, ?)",
                (RUN_ID, SILVER_TABLE, "FAIL" if name_null > 0 else "PASS", float(name_null), "name is null/empty")
            )

            cur.execute(
                "INSERT INTO gameday.ops_dq_results VALUES (?, current_timestamp(), ?, 'underage_count', ?, ?, ?)",
                (RUN_ID, SILVER_TABLE, "WARN" if underage > 0 else "PASS", float(underage), "age < 18")
            )

            # REGISTRO DEL NUEVO CHECK EN LA TABLA DE AUDITORÍA
            cur.execute(
                "INSERT INTO gameday.ops_dq_results VALUES (?, current_timestamp(), ?, 'missing_country_count', ?, ?, ?)",
                (RUN_ID, SILVER_TABLE, "FAIL" if missing_country > 0 else "PASS", float(missing_country), "country_name is null (ref_paises mapping error)")
            )
            # CONDICIÓN DE CORTE: Si hay registros sin país mapeado, se detiene la validación y el pipeline falla
            if missing_country > 0:
                raise ValueError(f"❌ Validación fallida: Se encontraron {missing_country} registros en Silver sin mapeo de país en ref_paises.")

    print(f"✅ Validation completed: total={total}, name_null={name_null}, underage={underage}")

if __name__ == "__main__":
    main()
