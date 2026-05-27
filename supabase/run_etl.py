import os
import datetime
import redis
import psycopg2
from dotenv import load_dotenv

# Cargar variables de entorno
load_dotenv()

REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379")
DATABASE_URL = os.environ.get("DATABASE_URL")

def execute_postgres_etl():
    print("\n--- INICIANDO FASE 1: Postgres-to-Postgres (Stored Procedure) ---")
    if not DATABASE_URL:
        print("[error] DATABASE_URL no esta definida en las variables de entorno.")
        return False
        
    conn = None
    try:
        # Conectar a Supabase/Postgres
        conn = psycopg2.connect(DATABASE_URL)
        cursor = conn.cursor()
        
        print("Conectado a PostgreSQL. Ejecutando dwh.run_etl()...")
        cursor.execute("SELECT dwh.run_etl();")
        conn.commit()
        print("[ok] dwh.run_etl() ejecutado con exito.")
        return True
    except Exception as e:
        print(f"[error] Error ejecutando dwh.run_etl(): {e}")
        if conn:
            conn.rollback()
        return False
    finally:
        if conn:
            conn.close()

def execute_redis_etl():
    print("\n--- INICIANDO FASE 2: Redis-to-Postgres (Popularidad de Queries) ---")
    if not DATABASE_URL:
        print("[error] DATABASE_URL no esta definida en las variables de entorno.")
        return False
        
    zset_key = "queries:popularity"
    
    # 1. Conectar a Redis
    try:
        # Soporta TLS/SSL (rediss://) y passwords nativamente via URL
        r = redis.Redis.from_url(REDIS_URL, decode_responses=True)
        r.ping()
        
        # Ocultar contrasenas de la impresion en consola por seguridad
        clean_redis_url = REDIS_URL.split("@")[-1] if "@" in REDIS_URL else REDIS_URL
        print(f"Conectado a Redis: {clean_redis_url}")
    except Exception as e:
        print(f"[error] No se pudo conectar a Redis en '{REDIS_URL}': {e}")
        return False
        
    # Verificar si el Sorted Set existe
    if not r.exists(zset_key):
        print(f"[warn] La clave '{zset_key}' no existe en Redis. Se saltea el ETL de popularidad.")
        return True
        
    # Traer todos los elementos con sus scores, ordenados por score descendente
    data = r.zrevrange(zset_key, 0, -1, withscores=True)
    if not data:
        print("[warn] El Sorted Set de popularidad esta vacio.")
        return True
        
    print(f"Leidas {len(data)} queries desde el Sorted Set '{zset_key}' en Redis.")
    
    # Nos quedamos con el Top 20 de subqueries
    top_20 = data[:20]
    
    # 2. Conectar a PostgreSQL y escribir directamente
    conn = None
    try:
        conn = psycopg2.connect(DATABASE_URL)
        cursor = conn.cursor()
        
        today = datetime.date.today()
        print(f"Preparando carga de popularidad en DWH para la fecha: {today}")
        
        # Limpiar entradas previas del dia de hoy por idempotencia
        cursor.execute("DELETE FROM dwh.fact_query_popularity WHERE fecha = %s;", (today,))
        
        insert_query = """
            INSERT INTO dwh.fact_query_popularity (fecha, query_texto, score, ranking)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (fecha, query_texto) DO UPDATE SET
                score = EXCLUDED.score,
                ranking = EXCLUDED.ranking;
        """
        
        for idx, (query_text, score) in enumerate(top_20, start=1):
            cursor.execute(insert_query, (today, query_text, int(score), idx))
            print(f"  Ranking #{idx}: '{query_text}' (Score: {int(score)})")
            
        conn.commit()
        print(f"[ok] Cargados con exito {len(top_20)} registros en dwh.fact_query_popularity.")
        return True
    except Exception as e:
        print(f"[error] Error al insertar en dwh.fact_query_popularity: {e}")
        if conn:
            conn.rollback()
        return False
    finally:
        if conn:
            conn.close()

def main():
    print("=== ORQUESTADOR ETL BUSCASAM (CLOUD-READY) ===")
    
    # Ejecutar Fase 1
    pg_ok = execute_postgres_etl()
    
    # Ejecutar Fase 2
    redis_ok = execute_redis_etl()
    
    print("\n==============================================")
    if pg_ok and redis_ok:
        print("ETL COMPLETADO CON EXITO.")
    else:
        print("ETL COMPLETADO CON ERRORES.")

if __name__ == "__main__":
    main()
