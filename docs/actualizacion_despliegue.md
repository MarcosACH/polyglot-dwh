# Guía de Actualización: Configuración de Entorno, Esquema Operativo y ETL

Este documento resume los cambios realizados en el repositorio para desplegar la base de datos operativa, conectar la instancia de **Redis Cloud**, estructurar el ETL final y automatizar su ejecución.

---

## 1. Cambios en la Estructura del Proyecto

* **Nueva automatización local:** Se creó el script [supabase/setup_and_seed.py](file:///home/nicolas/UNSAM/Bases%20de%20datos/tpi-bases-de-datos/supabase/setup_and_seed.py). Este script ejecuta en un solo comando:
  1. La aplicación de las migraciones pendientes en Supabase (`0003` y `0004`).
  2. La limpieza (`TRUNCATE`) completa de los esquemas `dwh` y `operativo` para garantizar idempotencia.
  3. La siembra de datos transaccionales con `operativo_seed.sql` en Supabase.
  4. La siembra del diccionario de autocompletado y métricas NoSQL en **Redis Cloud**.
  5. La ejecución de prueba del ETL completo (`run_etl.py`).
* **Renombrado de carpeta Redis local:** Se renombró la carpeta `redis/` a [no_se_usa_local_redis/](file:///home/nicolas/UNSAM/Bases%20de%20datos/tpi-bases-de-datos/no_se_usa_local_redis/) para evitar confusiones, ya que el motor Redis productivo corre en **Redis Cloud**. El script de semillas interno `seed.py` se sigue utilizando para poblar la nube.
* **Migración en el Motor Vectorial:**
  * Se desestimó `motor_vectorial.py` (movido a `supabase_vectorial/desestimado/`).
  * Se creó [motor_vectorial_operativo.py](file:///home/nicolas/UNSAM/Bases%20de%20datos/tpi-bases-de-datos/supabase_vectorial/motor_vectorial_operativo.py), que interactúa con la tabla transaccional final `operativo.documento` e inserta los autores principales en la tabla relacional `operativo.documento_autor`.
  * Se actualizó `supabase_vectorial/main.py` para utilizar el nuevo motor con la estructura relacional obligatoria (`id_uploader` y `visibilidad`).

---

## 2. Instrucciones para el Equipo

### A. Configuración de Dependencias
Para correr los scripts en sus máquinas locales, deben instalar las librerías del proyecto usando el nuevo [requirements.txt](file:///home/nicolas/UNSAM/Bases%20de%20datos/tpi-bases-de-datos/requirements.txt) en la raíz:
```bash
# Activar su entorno virtual e instalar dependencias
pip install -r requirements.txt
```

### B. Configuración de Variables de Entorno
Creen un archivo `.env` en la raíz del proyecto (este archivo está excluido en git y no se subirá) con las siguientes credenciales de Supabase y Redis Cloud:
```env
DATABASE_URL="postgresql://postgres.btqloorotiyyputoervr:iMOC1gzHxwdkKMPl@aws-1-us-east-1.pooler.supabase.com:5432/postgres"
REDIS_URL="redis://default:Hehk2m1BSTKs2VRvTNKKJOSkM7o6vVMl@fast-hole-macrofast-11509.db.redis.io:13631"
```

---

## 3. Automatización en la Nube (GitHub Actions)

Se creó el archivo [.github/workflows/run_etl.yml](file:///home/nicolas/UNSAM/Bases%20de%20datos/tpi-bases-de-datos/.github/workflows/run_etl.yml). El pipeline está configurado para:
* Correr de manera automática **todos los días a las 00:00 UTC**.
* Correr manualmente desde la pestaña **Actions** en el repositorio de GitHub.

### Configuración obligatoria en GitHub:
Para que la Action no falle, deben agregar los siguientes secretos en la configuración del repositorio en GitHub (**Settings -> Secrets and variables -> Actions -> Repository secrets**):
1. `DATABASE_URL` (la connection string de Supabase).
2. `REDIS_URL` (la URL de conexión de Redis Cloud).
