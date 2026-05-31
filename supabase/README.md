# Setup Supabase - Guia operativa

Como **desplegar y correr** el DWH de BUSCASAM sobre Supabase siguiendo el **Flujo A**
(operativo -> ETL -> dwh): migraciones, carga de datos, demos CRUD (punto 4) y mineria (punto 5).

Orden: **migraciones (`supabase db push`) -> datos + ETL (`etl/bootstrap.py`) -> demos / mineria**.

---

## 1. Pre-requisitos

### 1.1 Supabase CLI

**Windows** (PowerShell):

```powershell
# Opcion A - scoop (recomendado)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
irm get.scoop.sh | iex
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase

# Opcion B - winget
winget install Supabase.CLI
```

**macOS / Linux**:

```bash
brew install supabase/tap/supabase            # macOS
curl -fsSL https://supabase.com/install.sh | sh   # Linux
```

Verificar: `supabase --version`

### 1.2 Variables de entorno

Copiar `.env.example` (raiz del repo) a `.env` y completar `DATABASE_URL` y `REDIS_URL`.
El **project-ref** es el ultimo segmento de la URL del dashboard:
`https://supabase.com/dashboard/project/<PROJECT-REF>`.

### 1.3 Python (para el bootstrap y el ETL)

```powershell
pip install -r etl/requirements.txt
```

---

## 2. Setup inicial (una sola vez por persona)

```powershell
cd "C:\ruta\al\repo"
supabase login                            # abre navegador
supabase link --project-ref <PROJECT-REF> # pide la DB password
```

La CLI guarda el estado en `supabase/.temp/` (ignorado por git). Cada miembro corre `supabase link` una vez.

---

## 3. Aplicar migraciones al remoto

```powershell
supabase migration list   # ver pendientes
supabase db push          # aplica las que faltan
```

`db push` aplica solo lo que aun no esta en `supabase_migrations.schema_migrations` del remoto. Es seguro repetirlo.

### Migraciones incluidas

Estan ordenadas por dependencia (el sufijo timestamp define el orden de aplicacion):

| Archivo                                              | Contenido                                                                          |
|------------------------------------------------------|------------------------------------------------------------------------------------|
| `migrations/20260530100000_operativo_schema.sql`    | Schema `operativo` (OLTP 3NF): 12 tablas + triggers `updated_at` + pgvector/tsvector |
| `migrations/20260530100100_dwh_schema.sql`          | Schema `dwh`: 10 tablas (6 dimensiones + 3 hechos + `etl_watermark`) + indices     |
| `migrations/20260530100200_dwh_etl.sql`             | Funcion `dwh.run_etl()` (operativo -> dwh, incremental por watermark)              |
| `migrations/20260530100300_dwh_mineria.sql`         | Funciones de mineria: `segmentar_autores` y `predecir_interacciones_documento`     |

El DWH es una **estrella desnormalizada (Kimball, SCD1)** con la jerarquia Escuela > Carrera > Materia aplanada en `dim_materia`. Es el DER de [`design/dwh.dbml`](../design/dwh.dbml); el operativo, el de [`design/operativo.dbml`](../design/operativo.dbml).

---

## 4. Cargar datos y correr el ETL (Flujo A)

> **Importante**: `supabase db push` aplica el **esquema** pero **NO** carga datos. La carga la hace el bootstrap.

```powershell
python etl/bootstrap.py
```

`etl/bootstrap.py` hace, de forma idempotente (lee credenciales del `.env`):

1. `TRUNCATE` de los esquemas `dwh` y `operativo`.
2. Seed transaccional en `operativo` con [`seeds/operativo_seed.sql`](seeds/operativo_seed.sql).
3. Seed de Redis Cloud (`nosql/seed/seed.py`): autocompletado + `queries:popularity`.
4. Corrida del ETL completo ([`etl/run_etl.py`](../etl/run_etl.py)): `dwh.run_etl()` (operativo -> dwh) + Fase Redis (popularidad -> `dwh.fact_query_popularity`).

El seed usa `setseed(0.42)`, asi que es **reproducible**.

### Verificacion

```sql
SELECT
  (SELECT count(*) FROM dwh.dim_materia)                AS materias,    -- 300
  (SELECT count(*) FROM dwh.dim_usuario)                AS usuarios,    -- 2001 (2000 + sentinel id 0)
  (SELECT count(*) FROM dwh.dim_documento)              AS documentos,  -- 5000
  (SELECT count(*) FROM dwh.fact_interaccion_documento) AS f_doc,       -- > 0
  (SELECT count(*) FROM dwh.fact_interaccion_autor)     AS f_autor;     -- > 0
```

> Las dimensiones son deterministas; los hechos agregados pueden variar levemente segun como colapsan los eventos aleatorios.

### Atajo Flujo B (DWH directo, sin operativo ni ETL)

[`seeds/dwh_directo.sql`](seeds/dwh_directo.sql) puebla `dwh.*` **directamente** con datos sinteticos, salteando el operativo y el ETL. Sirve para demostrar el DWH de forma aislada (pegar en el SQL Editor y ejecutar). **No** es parte del Flujo A; no mezclar ambos caminos sobre la misma DB.

---

## 5. Demos CRUD (punto 4)

Seis scripts en [`demos_crud/`](demos_crud/) (Creacion, Eliminacion, Insercion, Actualizacion, Busqueda 1 clave, Busqueda 2 claves). Los demos 01-04 corren dentro de `BEGIN; ... ROLLBACK;` (no persisten); 05-06 son solo lectura. Requieren migraciones + datos cargados.

Detalle completo (configurar `.env`, cargar variables, ejecutar) en [`demos_crud/README.md`](demos_crud/README.md).

### Conexion directa al remoto (psql)

`localhost:5432` no funciona salvo stack local (seccion 7). Para el remoto, usar la pooler connection string en modo **session** (puerto 5432):

```powershell
$env:PGPASSWORD = "TU_PASSWORD"   # vive solo en esta terminal; limpiar con $env:PGPASSWORD = $null
psql -h aws-1-<region>.pooler.supabase.com -p 5432 -U postgres.<ref> -d postgres `
    -v ON_ERROR_STOP=1 -f supabase/demos_crud/01_creacion.sql
```

Los seis:

```powershell
psql -f supabase/demos_crud/01_creacion.sql
psql -f supabase/demos_crud/02_eliminacion.sql
psql -f supabase/demos_crud/03_insercion.sql
psql -f supabase/demos_crud/04_actualizacion.sql
psql -f supabase/demos_crud/05_busqueda_1clave.sql
psql -f supabase/demos_crud/06_busqueda_2claves.sql
```

---

## 6. Mineria de datos (punto 5)

Las dos funciones se despliegan con `migrations/20260530100300_dwh_mineria.sql` (paso 3). Explicacion y salida esperada en [`docs/mineria.md`](../docs/mineria.md).

```sql
-- 5.1 Segmentacion: autores en matriz volumen x impacto
SELECT segmento, count(*)
FROM   dwh.segmentar_autores()           -- params: (desde, hasta, escuela)
GROUP  BY segmento ORDER BY 2 DESC;

-- 5.2 Prediccion: forecast de visualizaciones de un documento (regresion lineal)
SELECT * FROM dwh.predecir_interacciones_documento(1, 3);   -- doc 1, horizonte 3 meses
```

Los documentos 1 (creciente), 2 (decreciente) y 3 (estable) tienen una serie con tendencia inyectada en `seeds/operativo_seed.sql` para ilustrar la prediccion.

El **dashboard BI (punto 6)** y sus 4 consultas estan en [`docs/dashboard_bi.md`](../docs/dashboard_bi.md).

---

## 7. Alternativa: stack local con Docker

La CLI levanta un Postgres local que **aplica migraciones y corre el seed del operativo automaticamente** (segun `config.toml`, `db.seed` apunta a `seeds/operativo_seed.sql`):

```powershell
supabase start        # levanta el stack local (requiere Docker)
supabase db reset     # recrea la DB: migraciones + seed del operativo
python etl/bootstrap.py   # siembra Redis y corre el ETL -> pobla el dwh
```

`db reset` deja el **operativo** poblado; el **dwh** se llena al correr el ETL.

---

## 8. Workflow: agregar una nueva migration

```powershell
supabase migration new <nombre>            # genera supabase/migrations/<timestamp>_<nombre>.sql
# editar el archivo y escribir el SQL
supabase db push                           # aplicar al remoto
git add supabase/migrations/ && git commit -m "agregar <nombre>"
```

### Convenciones

- Nombres descriptivos en snake_case con prefijo timestamp (lo genera `migration new`).
- Una migration = un cambio logico. **Aditivas e idempotentes** (`CREATE ... IF NOT EXISTS`, `CREATE OR REPLACE`); nunca destructivas (`DROP SCHEMA`).
- **No editar migrations ya aplicadas en el remoto.** Si hay que corregir, crear una nueva.

---

## Referencias

- Supabase CLI: <https://supabase.com/docs/guides/cli>
- Migrations: <https://supabase.com/docs/guides/cli/local-development#database-migrations>
- DBML: <https://dbml.dbdiagram.io/docs>
