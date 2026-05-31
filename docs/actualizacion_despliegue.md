# Guía de Actualización: Configuración de Entorno, Esquema Operativo y ETL

Este documento resume los cambios realizados en el repositorio para desplegar la base de datos operativa, conectar la instancia de **Redis Cloud**, estructurar el ETL final y automatizar su ejecución.

---

## 1. Cambios en la Estructura del Proyecto

* **Bootstrap de datos:** El script [`etl/bootstrap.py`](../etl/bootstrap.py) carga los datos del Flujo A en un solo comando. Las migraciones se aplican aparte con `supabase db push` (enfoque CLI-native). El script ejecuta:
  1. La limpieza (`TRUNCATE`) completa de los esquemas `dwh` y `operativo` para garantizar idempotencia.
  2. La siembra de datos transaccionales con `supabase/seeds/operativo_seed.sql`.
  3. La siembra del diccionario de autocompletado y métricas NoSQL en **Redis Cloud**.
  4. La ejecución del ETL completo ([`etl/run_etl.py`](../etl/run_etl.py)).
* **Carpeta Redis:** La demo Redis vive en [`redis/`](../redis/) (instancia local en Docker, opcional). El motor productivo corre en **Redis Cloud**; el seed `redis/seed/seed.py` se sigue utilizando para poblar la nube.
* **Motor Vectorial (`search/`):**
  * Se desestimó el motor viejo (movido a `search/desestimado/motor_vectorial.py`).
  * [`search/motor.py`](../search/motor.py) interactúa con la tabla transaccional `operativo.documento` e inserta el autor principal en `operativo.documento_autor`.
  * [`search/main.py`](../search/main.py) usa el nuevo motor con la estructura relacional obligatoria (`id_uploader` y `visibilidad`).

---

## 2. Instrucciones para el Equipo

### A. Configuración de Dependencias
Las dependencias estan separadas por componente. Para el ETL:
```bash
# Activar su entorno virtual e instalar dependencias del ETL
pip install -r etl/requirements.txt
```
(El motor vectorial usa `search/requirements.txt` y la demo Redis `redis/seed/requirements.txt`.)

### B. Configuración de Variables de Entorno
Copien `.env.example` (en la raíz) a `.env` (gitignored, no se sube) y completen con las credenciales reales de Supabase y Redis Cloud.
```env
DATABASE_URL="postgresql://postgres.<project-ref>:<password>@aws-<n>-<region>.pooler.supabase.com:5432/postgres"
REDIS_URL="redis://default:<password>@<host>:<port>"
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
