# Setup Supabase - Guia operativa

Esta guia describe como **desplegar y correr** el DWH de BUSCASAM sobre Supabase:
migraciones, carga del seed, demos CRUD (punto 4) y funciones de mineria (punto 5).

Orden de despliegue: **migraciones -> seed -> demos / mineria**.

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

# Opcion C - binario directo
# Descargar desde https://github.com/supabase/cli/releases y agregar al PATH
```

**macOS / Linux**:

```bash
brew install supabase/tap/supabase            # macOS
# o
curl -fsSL https://supabase.com/install.sh | sh   # Linux
```

Verificar:

```powershell
supabase --version
```

### 1.2 Datos del proyecto Supabase

- **project-ref**: ultimo segmento de la URL del dashboard.
  `https://supabase.com/dashboard/project/<PROJECT-REF>`

---

## 2. Setup inicial (una sola vez por persona)

```powershell
# Posicionarse en la raiz del repo
cd "C:\ruta\al\repo\Bases de Datos"

# Autenticarse (abre navegador)
supabase login

# Vincular al proyecto remoto (te va a pedir la DB password)
supabase link --project-ref <PROJECT-REF>
```

Despues del `link`, la CLI guarda el estado en `supabase/.temp/` (ignorado por git).
Cada miembro del equipo corre `supabase link` una vez en su maquina.

---

## 3. Aplicar migrations al remoto

```powershell
# Ver migrations pendientes
supabase migration list

# Aplicar todas las pendientes
supabase db push
```

`db push` aplica solo las migrations que aun no estan en la tabla `supabase_migrations.schema_migrations` del remoto. Es seguro correrlo multiples veces.

### Migrations incluidas

| Archivo                                   | Contenido                                                                       |
|-------------------------------------------|---------------------------------------------------------------------------------|
| `supabase/migrations/0001_dwh_schema.sql` | Schema `dwh`: 10 tablas (6 dimensiones + 3 hechos + `etl_watermark`) + indices  |
| `supabase/migrations/0002_mineria.sql`    | Funciones de mineria: `segmentar_autores` y `predecir_interacciones_documento`  |

El modelo es una **estrella desnormalizada (Kimball, SCD1)** con la jerarquia Escuela > Carrera > Materia aplanada en `dim_materia`. Es el DER de [`design/agregado.dbml`](../design/agregado.dbml).

---

## 4. Cargar datos sinteticos (seed)

> **Importante**: `supabase db push` **NO** ejecuta `seed.sql`. La CLI solo lo corre automaticamente con `supabase db reset` (modo local, ver seccion 7). Para el remoto hay que cargarlo manualmente.

### Opcion A - SQL Editor del dashboard (la mas simple)

1. Abrir `supabase/seed.sql` en el editor local, copiar todo el contenido.
2. Dashboard -> SQL Editor -> New query -> pegar -> Run.
3. Esperar ~30-60s.

### Opcion B - psql (si esta instalado)

```powershell
# Connection string: Dashboard -> Project Settings -> Database -> Connection string (URI)
psql "postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres" `
    -f supabase/seed.sql
```

El seed usa `setseed(0.42)`, asi que es **reproducible**: cargarlo de nuevo (sobre una DB recien migrada) da siempre los mismos datos.

### Verificacion

```sql
SELECT
  (SELECT count(*) FROM dwh.dim_materia)                AS materias,
  (SELECT count(*) FROM dwh.dim_tiempo)                 AS dias,
  (SELECT count(*) FROM dwh.dim_usuario)                AS usuarios,
  (SELECT count(*) FROM dwh.dim_documento)              AS documentos,
  (SELECT count(*) FROM dwh.fact_interaccion_documento) AS interacciones_doc,
  (SELECT count(*) FROM dwh.fact_interaccion_autor)     AS interacciones_autor,
  (SELECT count(*) FROM dwh.fact_query_popularity)      AS query_popularity;
```

Volumenes esperados:

| Tabla                        | Filas    | Notas                                         |
|------------------------------|----------|-----------------------------------------------|
| dim_materia                  | 300      | jerarquia Escuela/Carrera/Materia aplanada    |
| dim_tiempo                   | 1096     | 2024-01-01 a 2026-12-31                       |
| dim_usuario                  | 2000     | SCD1                                          |
| dim_tipo_documento           | 8        |                                               |
| dim_documento                | 5000     | SCD1, ~3% con `is_deleted = true`             |
| dim_tipo_interaccion         | 3        | publicacion / visualizacion / favorito_agregar |
| fact_interaccion_documento   | ~41021   | agregado por (fecha, doc, tipo)               |
| fact_interaccion_autor       | ~56896   | agregado por (fecha, autor, tipo)             |
| fact_query_popularity        | 13152    | 12 queries x 1096 dias (snapshot diario)      |
| etl_watermark                | 7        |                                               |

> Las dimensiones son exactas (formulas deterministas). Los hechos agregados pueden variar ligeramente segun como colapsan los eventos aleatorios, por eso van con `~`.

---

## 5. Correr los demos CRUD (punto 4)

Seis scripts ejecutables en `supabase/demos/` (Creacion, Eliminacion, Insercion, Actualizacion, Busqueda 1 clave, Busqueda 2 claves). Los demos 01-04 corren dentro de `BEGIN; ... ROLLBACK;` (no persisten nada); 05-06 son solo lectura.

El detalle completo (configurar `.env`, cargar variables y ejecutar) esta en [`supabase/demos/README.md`](../supabase/demos/README.md).

### Conexion directa al remoto

`localhost:5432` **no** funciona salvo que tengas el stack local corriendo (seccion 7). Para correr contra el remoto hay que usar la pooler connection string (Dashboard -> Project Settings -> Database, o `supabase/.temp/pooler-url` tras el `link`), en modo **session** (puerto 5432, apto para scripts `.sql`):

```powershell
# Setea la DB password solo para esta sesion de PowerShell (no la expone en el comando)
$env:PGPASSWORD = "TU_PASSWORD"

psql -h aws-1-<region>.pooler.supabase.com -p 5432 -U postgres.<ref> -d postgres `
    -v ON_ERROR_STOP=1 -f supabase/demos/01_creacion.sql
```

- `$env:PGPASSWORD` lo lee `psql` automaticamente; vive solo en esa terminal. Limpiar al terminar con `$env:PGPASSWORD = $null`.
- `-v ON_ERROR_STOP=1` aborta ante el primer error en vez de seguir.
- Alternativa en una linea (la pass queda visible en el historial):
  `psql "postgresql://postgres.<ref>:<password>@aws-1-<region>.pooler.supabase.com:5432/postgres" -f supabase/demos/01_creacion.sql`

Los seis scripts:

```powershell
psql -f supabase/demos/01_creacion.sql
psql -f supabase/demos/02_eliminacion.sql
psql -f supabase/demos/03_insercion.sql
psql -f supabase/demos/04_actualizacion.sql
psql -f supabase/demos/05_busqueda_1clave.sql
psql -f supabase/demos/06_busqueda_2claves.sql
```

Requieren migraciones + seed ya cargados.

---

## 6. Mineria de datos (punto 5)

Las dos funciones se despliegan con la migration `0002_mineria.sql` (paso 3). Explicacion y salida esperada en [`docs/mineria.md`](mineria.md).

Las consultas (son solo lectura):

```sql
-- 5.1 Segmentacion: autores en matriz volumen x impacto
SELECT segmento, count(*)
FROM   dwh.segmentar_autores()           -- params: (desde, hasta, escuela)
GROUP  BY segmento ORDER BY 2 DESC;

-- 5.2 Prediccion: forecast de visualizaciones de un documento (regresion lineal)
SELECT * FROM dwh.predecir_interacciones_documento(1, 3);   -- doc 1, horizonte 3 meses
```

### Correr por psql desde tu maquina

Con la misma conexion al remoto de la seccion 5 (pooler en modo session, `$env:PGPASSWORD` ya seteado), pasalas inline con `-c`:

```powershell
$env:PGPASSWORD = "TU_PASSWORD"

# 5.1 Segmentacion
psql -h aws-1-<region>.pooler.supabase.com -p 5432 -U postgres.<ref> -d postgres `
    -c "SELECT segmento, count(*) FROM dwh.segmentar_autores() GROUP BY segmento ORDER BY 2 DESC;"

# 5.2 Prediccion (doc 1, horizonte 3 meses)
psql -h aws-1-<region>.pooler.supabase.com -p 5432 -U postgres.<ref> -d postgres `
    -c "SELECT * FROM dwh.predecir_interacciones_documento(1, 3);"
```

Los documentos 1 (creciente), 2 (decreciente) y 3 (estable) tienen una serie con tendencia inyectada en el seed para ilustrar la prediccion.

El **dashboard BI (punto 6)** y sus 4 consultas estan documentados en [`docs/dashboard_bi.md`](dashboard_bi.md).

---

## 7. Alternativa: stack local con Docker

Si preferis no tocar el remoto, la CLI levanta un Postgres local que **aplica migraciones y corre `seed.sql` automaticamente**:

```powershell
supabase start        # levanta el stack local (requiere Docker)
supabase db reset     # recrea la DB: migraciones + seed.sql de una
```

`db reset` es la forma mas rapida de tener todo (esquema + datos + funciones) corriendo desde cero. La connection string local la imprime `supabase start`.

---

## 8. Workflow: agregar una nueva migration

```powershell
# 1. Crear archivo vacio (genera supabase/migrations/<timestamp>_<nombre>.sql)
supabase migration new agregar_dim_X

# 2. Editar el archivo recien creado y escribir el SQL
code supabase/migrations/<timestamp>_agregar_dim_X.sql

# 3. (Opcional) Revisar pendientes
supabase migration list

# 4. Aplicar al remoto
supabase db push

# 5. Commit + push a GitHub
git add supabase/migrations/
git commit -m "agregar dim X"
git push
```

### Convenciones

- **Nombres descriptivos** en snake_case: `agregar_indice_visualizacion`, `corregir_fk_documento`.
- **Una migration = un cambio logico**. Mas chicas son mas faciles de revertir y revisar.
- **No editar migrations ya aplicadas en el remoto**. Si necesitas corregir algo, crea una nueva migration que arregle el problema.
- Si la migration falla, el push aborta y la migration **no** queda marcada como aplicada. Se corrige el archivo y se vuelve a correr `supabase db push`.

---

## Referencias

- Supabase CLI: <https://supabase.com/docs/guides/cli>
- Supabase migrations: <https://supabase.com/docs/guides/cli/local-development#database-migrations>
- DBML syntax: <https://dbml.dbdiagram.io/docs>
