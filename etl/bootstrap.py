"""Bootstrap de datos del Flujo A para BUSCASAM (no aplica migraciones).

Prerequisito: el esquema ya debe estar aplicado con la CLI de Supabase
(`supabase db push` contra el remoto, o `supabase db reset` en local).
Este script solo carga DATOS, de forma idempotente:

  1. TRUNCATE de los esquemas dwh y operativo.
  2. Seed transaccional en operativo (supabase/seeds/operativo_seed.sql).
  3. Seed de Redis Cloud (redis/seed/seed.py).
  4. Corrida del ETL completo (etl/run_etl.py): operativo -> dwh + Redis -> dwh.

Uso:
    supabase db push          # 1 vez / cuando cambian migraciones
    python etl/bootstrap.py   # cargar datos + correr ETL
"""
import os
import sys
import subprocess
import psycopg2
from pathlib import Path
from dotenv import load_dotenv

# Cargar variables de entorno desde el .env del root
ROOT_DIR = Path(__file__).resolve().parent.parent
load_dotenv(ROOT_DIR / ".env")

DATABASE_URL = os.environ.get("DATABASE_URL")
REDIS_URL = os.environ.get("REDIS_URL")

def check_env():
    if not DATABASE_URL:
        print("[error] DATABASE_URL no definida en el archivo .env")
        sys.exit(1)
    if not REDIS_URL:
        print("[error] REDIS_URL no definida en el archivo .env")
        sys.exit(1)

def run_sql_file(cursor, file_path):
    print(f"Ejecutando script SQL: {file_path.name}...")
    with open(file_path, "r", encoding="utf-8") as f:
        sql_content = f.read()
    cursor.execute(sql_content)

def seed_operativo():
    print("\n=== SEED OPERATIVO (Supabase) ===")
    print("Prerequisito: migraciones aplicadas con `supabase db push` / `supabase db reset`.")
    conn = psycopg2.connect(DATABASE_URL)
    conn.autocommit = False
    cursor = conn.cursor()

    try:
        # 1. Vaciar dwh y operativo para idempotencia (las tablas deben existir:
        #    si fallan acá, faltan las migraciones -> correr `supabase db push`).
        print("Vaciando tablas de los esquemas dwh y operativo...")
        truncate_query = """
            TRUNCATE TABLE
                dwh.fact_interaccion_documento,
                dwh.fact_interaccion_autor,
                dwh.fact_query_popularity,
                dwh.dim_documento,
                dwh.dim_usuario,
                dwh.dim_materia,
                dwh.dim_tipo_documento,
                dwh.dim_tiempo,
                dwh.dim_tipo_interaccion,
                dwh.etl_watermark,
                operativo.busqueda,
                operativo.comentario,
                operativo.descarga,
                operativo.evento_visualizacion,
                operativo.favorito,
                operativo.documento_autor,
                operativo.documento,
                operativo.usuario,
                operativo.materia,
                operativo.carrera,
                operativo.escuela,
                operativo.tipo_documento
            CASCADE;
        """
        cursor.execute(truncate_query)
        conn.commit()
        print("[ok] Esquemas dwh y operativo vaciados.")

        # 2. Seed transaccional del operativo
        run_sql_file(cursor, ROOT_DIR / "supabase" / "seeds" / "operativo_seed.sql")
        conn.commit()
        print("[ok] Seed de operativa cargado con exito en Supabase.")

    except Exception as e:
        conn.rollback()
        print(f"[error] Error sembrando el operativo: {e}")
        print("        Si el error es 'relation does not exist', faltan las migraciones:")
        print("        corre `supabase db push` antes de este script.")
        sys.exit(1)
    finally:
        cursor.close()
        conn.close()

def run_subprocess(script_path, descripcion):
    """Corre un script hijo heredando el entorno (DATABASE_URL/REDIS_URL ya estan
    en os.environ via load_dotenv) y dejando que su salida se muestre en vivo."""
    try:
        # CWD en la carpeta del script para que resuelva sus rutas relativas (ej: data.json)
        subprocess.run(
            [sys.executable, str(script_path)],
            cwd=str(script_path.parent),
            check=True,
        )
        print(f"[ok] {descripcion} ejecutado con exito.")
    except subprocess.CalledProcessError:
        print(f"[error] Fallo al ejecutar {descripcion} (ver salida arriba).")
        sys.exit(1)

def seed_redis():
    print("\n=== SEMBRANDO DATOS EN REDIS CLOUD ===")
    run_subprocess(ROOT_DIR / "redis" / "seed" / "seed.py", "Seed de Redis")

def run_etl():
    print("\n=== EJECUTANDO EL ETL COMPLETO ===")
    run_subprocess(Path(__file__).resolve().parent / "run_etl.py", "ETL")

def main():
    check_env()
    seed_operativo()
    seed_redis()
    run_etl()
    print("\n==============================================")
    print("BOOTSTRAP DE DATOS Y ETL COMPLETADO CON EXITO.")

if __name__ == "__main__":
    main()
