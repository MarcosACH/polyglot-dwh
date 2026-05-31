# Demos CRUD - DWH BUSCASAM

Ejemplos ejecutables de las operaciones del punto 4 de la consigna (Creacion, Eliminacion, Insercion, Actualizacion, Busqueda 1 clave, Busqueda 2 claves) sobre el DWH de BUSCASAM.

Cada demo se corre con `psql` contra la misma DB de Supabase donde estan aplicadas las migrations y el seed.

---

## 1. Pre-requisitos

- Esquema aplicado (`supabase db push`) y DWH poblado vía Flujo A (`python etl/bootstrap.py`). Ver [`supabase/README.md`](../README.md).
- `psql` instalado y la connection string del proyecto (Dashboard -> Project Settings -> Database -> Connection string URI).
- Archivo `.env` completado con las credenciales del DWH (ver paso 3).

---

## 2. Demos

| #  | Operacion          | Archivo                                            | Sobre que esquema corre |
|----|--------------------|----------------------------------------------------|-------------------------|
| 01 | Creacion (DDL)     | [`01_creacion.sql`](01_creacion.sql)               | `dwh_demo` (sandbox)    |
| 02 | Eliminacion        | [`02_eliminacion.sql`](02_eliminacion.sql)         | `dwh` (productivo)      |
| 03 | Insercion          | [`03_insercion.sql`](03_insercion.sql)             | `dwh` (productivo)      |
| 04 | Actualizacion      | [`04_actualizacion.sql`](04_actualizacion.sql)     | `dwh` (productivo)      |
| 05 | Busqueda 1 clave   | [`05_busqueda_1clave.sql`](05_busqueda_1clave.sql) | `dwh` (productivo)      |
| 06 | Busqueda 2 claves  | [`06_busqueda_2claves.sql`](06_busqueda_2claves.sql) | `dwh` (productivo)    |

**Demos 01 a 04** estan envueltos en `BEGIN; ... ROLLBACK;`: la operacion corre, los `SELECT` antes/despues muestran el efecto, y al final la transaccion se revierte. Nada queda persistido. Se pueden re-ejecutar las veces que haga falta sin ensuciar la DB.

**Demos 05 y 06** son solo lectura (`SELECT`), no necesitan transaccion.

---

## 3. Como correrlos

### 3.1 Completar el `.env`

`supabase/demos_crud/.env` ya esta creado con los campos vacios (esta gitignored). Editarlo y completar con los datos de la connection string del proyecto (Dashboard -> Project Settings -> Database):

```
PGHOST=aws-0-<region>.pooler.supabase.com
PGPORT=5432
PGUSER=postgres.<project-ref>
PGPASSWORD=<password>
PGDATABASE=postgres
```

`psql` usa estas variables `PG*` automaticamente — no hace falta pasar `-h/-U/-d` en cada comando.

### 3.2 Cargar el `.env` en la sesion

**PowerShell** (Windows):

```powershell
Get-Content supabase/demos_crud/.env | ForEach-Object {
    if ($_ -match '^\s*([^#=]+)=(.*)$') {
        Set-Item "Env:$($matches[1].Trim())" $matches[2].Trim()
    }
}
```

**Bash** (macOS / Linux):

```bash
set -a; source supabase/demos_crud/.env; set +a
```

### 3.3 Ejecutar los demos

```bash
psql -f supabase/demos_crud/01_creacion.sql
psql -f supabase/demos_crud/02_eliminacion.sql
psql -f supabase/demos_crud/03_insercion.sql
psql -f supabase/demos_crud/04_actualizacion.sql
psql -f supabase/demos_crud/05_busqueda_1clave.sql
psql -f supabase/demos_crud/06_busqueda_2claves.sql
```

Cada `psql -f` imprime los resultados de los `SELECT` directamente en la terminal.

---

## 4. Que muestra cada demo

| Demo | Antes/Despues comparable                              | ETL relacionado                                          |
|------|--------------------------------------------------------|----------------------------------------------------------|
| 01   | Tablas en `information_schema` del schema sandbox      | Inicializacion (corre 1 sola vez al desplegar el DWH)    |
| 02   | `is_deleted` + `count(*)` de hechos del documento `4521` | Baja logica + purga fisica (moderacion / derecho al olvido) |
| 03   | `SUM(cant_interacciones)` del `2026-05-04`             | Carga incremental diaria agregada (`created_at > watermark`, upsert) |
| 04   | Carrera del usuario y visibilidad del documento (SCD1) | Deteccion de cambios via `updated_at`, sobreescritura SCD1 |
| 05   | Total de interacciones en el primer cuatrimestre 2026  | -                                                        |
| 06   | Visualizaciones por tipo de documento x anio           | -                                                        |
