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

def setup_supabase():
    print("\n=== CONFIGURANDO SUPABASE ===")
    conn = psycopg2.connect(DATABASE_URL)
    conn.autocommit = False
    cursor = conn.cursor()
    
    try:
        # 1. Crear tabla de migrations si no existe
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations (
                version text PRIMARY KEY,
                statements text[],
                name text
            );
        """)
        conn.commit()

        # 2. Verificar qué migrations ya están aplicadas
        cursor.execute("SELECT version FROM supabase_migrations.schema_migrations;")
        applied_versions = {row[0] for row in cursor.fetchall()}
        print(f"Migraciones ya aplicadas en Supabase: {sorted(list(applied_versions))}")

        # 3. Aplicar 0003_operativo_schema.sql si es necesario
        mig_dir = ROOT_DIR / "supabase" / "migrations"
        
        if "0003" not in applied_versions:
            run_sql_file(cursor, mig_dir / "0003_operativo_schema.sql")
            cursor.execute(
                "INSERT INTO supabase_migrations.schema_migrations (version, name) VALUES (%s, %s);",
                ("0003", "operativo_schema")
            )
            conn.commit()
            print("[ok] Migracion 0003 aplicada con exito.")
        else:
            print("[info] Migracion 0003 ya estaba aplicada.")

        # 4. Aplicar 0004_etl.sql si es necesario
        if "0004" not in applied_versions:
            run_sql_file(cursor, mig_dir / "0004_etl.sql")
            cursor.execute(
                "INSERT INTO supabase_migrations.schema_migrations (version, name) VALUES (%s, %s);",
                ("0004", "etl")
            )
            conn.commit()
            print("[ok] Migracion 0004 aplicada con exito.")
        else:
            print("[info] Migracion 0004 ya estaba aplicada.")

        # 5. Vaciar el DWH y el esquema operativo (para permitir idempotencia)
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
        print("[ok] DWH vaciado con exito.")

        # 6. Correr el seed para la operativa
        run_sql_file(cursor, ROOT_DIR / "supabase" / "operativo_seed.sql")
        conn.commit()
        print("[ok] Seed de operativa cargado con exito en Supabase.")

    except Exception as e:
        conn.rollback()
        print(f"[error] Error configurando Supabase: {e}")
        sys.exit(1)
    finally:
        cursor.close()
        conn.close()

def seed_redis():
    print("\n=== SEMBRANDO DATOS EN REDIS CLOUD ===")
    env = os.environ.copy()
    if REDIS_URL is None:
        raise ValueError("REDIS_URL no está configurada")
    env["REDIS_URL"] = REDIS_URL
    
    # Ejecutamos el script de seed de Redis usando el Python del entorno virtual
    seed_script = ROOT_DIR / "no_se_usa_local_redis" / "seed" / "seed.py"
    
    try:
        # Cambiamos el CWD para que importe correctamente las cosas en no_se_usa_local_redis/seed
        result = subprocess.run(
            [sys.executable, str(seed_script)],
            env=env,
            cwd=str(seed_script.parent),
            capture_output=True,
            text=True,
            check=True
        )
        print(result.stdout)
        print("[ok] Seed de Redis ejecutado con exito.")
    except subprocess.CalledProcessError as e:
        print(f"[error] Error al ejecutar el seed de Redis:\n{e.stderr}")
        sys.exit(1)

def run_etl():
    print("\n=== EJECUTANDO EL ETL COMPLETO ===")
    env = os.environ.copy()
    if DATABASE_URL is None or REDIS_URL is None:
        raise ValueError("DATABASE_URL o REDIS_URL no están configuradas")
    env["DATABASE_URL"] = DATABASE_URL
    env["REDIS_URL"] = REDIS_URL
    
    etl_script = ROOT_DIR / "supabase" / "run_etl.py"
    
    try:
        result = subprocess.run(
            [sys.executable, str(etl_script)],
            env=env,
            cwd=str(etl_script.parent),
            capture_output=True,
            text=True,
            check=True
        )
        print(result.stdout)
        print("[ok] ETL ejecutado y validado con exito.")
    except subprocess.CalledProcessError as e:
        print(f"[error] Error al ejecutar el ETL:\n{e.stderr}")
        sys.exit(1)

def main():
    check_env()
    setup_supabase()
    seed_redis()
    run_etl()
    print("\n==============================================")
    print("PROCESO DE SETUP, SEED Y ETL COMPLETADO CON EXITO.")

if __name__ == "__main__":
    main()
