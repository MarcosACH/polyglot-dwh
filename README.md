# BUSCASAM DWH

Datawarehouse analitico de **BUSCASAM**, plataforma de busqueda academica de la Universidad Nacional de San Martin (UNSAM).
Trabajo practico integrador de la materia Base de Datos.

## Contenido

- **Base operativa (PostgreSQL / Supabase, schema `operativo`)** — OLTP normalizada (3NF) que es la fuente de verdad transaccional: usuarios, documentos, interacciones, busquedas. Incluye `pgvector` (embeddings) y `tsvector` (busqueda lexica).
- **DWH (PostgreSQL / Supabase, schema `dwh`)** — modelo dimensional en **estrella desnormalizada (Kimball, SCD1)** con la jerarquia Escuela > Carrera > Materia aplanada en `dim_materia`. Se alimenta del operativo via ETL.
- **ETL (`etl/`)** — pipeline que carga el DWH: `dwh.run_etl()` (operativo -> dwh, incremental por watermark) + Fase Redis (popularidad de queries -> `dwh.fact_query_popularity`). Orquestado por GitHub Actions todos los dias.
- **Mineria de datos** — funciones dinamicas de segmentacion de autores y prediccion de visualizaciones sobre el DWH.
- **Busqueda vectorial (`search/`)** — indexacion semantica con embeddings locales (`sentence-transformers`, `all-MiniLM-L6-v2`) + extraccion de PDF. Demo de la mitad semantica del buscador de la app.
- **NoSQL (`redis/`)** — Redis (autocompletado con RediSearch, blacklist de JWT, rate limiting). Productivo en **Redis Cloud**; instancia local en Docker opcional para la demo.

## Stack

| Capa            | Tecnologia                                          |
|-----------------|-----------------------------------------------------|
| OLTP + DWH      | PostgreSQL (Supabase, schemas `operativo` y `dwh`)  |
| NoSQL           | Redis Cloud (con RediSearch) / Redis Stack local    |
| ETL / scheduler | Python (psycopg2 + redis) + GitHub Actions          |
| Migraciones     | Supabase CLI                                        |
| Visualizacion   | Power BI                                            |
| Diagramas       | DBML ([dbdiagram.io](https://dbdiagram.io))         |

## Flujo de datos (Flujo A)

```
                          Supabase (1 proyecto)
  app / seed ──► schema operativo ──[ dwh.run_etl() ]──► schema dwh ──► Power BI
                  (OLTP 3NF)            incremental        (estrella)
                                                               ▲
  Redis Cloud (ZSET queries:popularity) ──[ etl/run_etl.py ]──┘

  Bootstrap (1 vez):   supabase db push   →   python etl/bootstrap.py
  Diario (CI 00:00 UTC): etl/run_etl.py  (Fase1 PG→PG + Fase2 Redis→PG, incremental)
```

## Estructura del repo

```
.
|-- README.md                  Este archivo
|-- .env.example               Plantilla de variables de entorno (copiar a .env)
|-- .github/workflows/etl.yml  CI: corre el ETL diariamente (00:00 UTC)
|-- docs/
|   |-- spec.md                Especificacion funcional de BUSCASAM
|   |-- entrega.md             Monografia (documento de entrega)
|   |-- mineria.md             Mineria: segmentacion y prediccion
|   |-- dashboard_bi.md        Dashboard BI: las 4 consultas del punto 6
|   `-- ...
|-- design/
|   |-- operativo.dbml         DER de la base operativa (OLTP)
|   |-- dwh.dbml               DER del DWH (estrella desnormalizada)
|   `-- decisiones.md          Decisiones de diseno del modelo
|-- supabase/
|   |-- config.toml            Config del proyecto Supabase (db.seed -> operativo)
|   |-- migrations/            Migraciones versionadas (timestamp, orden por dependencia)
|   |   |-- 20260530100000_operativo_schema.sql
|   |   |-- 20260530100100_dwh_schema.sql
|   |   |-- 20260530100200_dwh_etl.sql
|   |   `-- 20260530100300_dwh_mineria.sql
|   |-- seeds/
|   |   |-- operativo_seed.sql Seed transaccional reproducible (Flujo A, canonico)
|   |   `-- dwh_directo.sql    Atajo: pobla el DWH directo, sin ETL (Flujo B)
|   `-- demos_crud/            Scripts CRUD ejecutables (punto 4)
|-- etl/
|   |-- bootstrap.py           Carga datos (operativo + Redis) y corre el ETL
|   |-- run_etl.py             ETL: operativo -> dwh + Redis -> dwh
|   `-- requirements.txt
|-- search/                    Busqueda semantica (pgvector + embeddings)
`-- redis/                     Redis: seed, demos y docker-compose local
```

## Quick start (Flujo A)

Requisitos: [Supabase CLI](https://supabase.com/docs/guides/cli) instalada y el proyecto linkeado (`supabase login` + `supabase link`), Python 3.12+, y un `.env` en la raiz (copiar de `.env.example` y completar `DATABASE_URL` y `REDIS_URL`).

```powershell
pip install -r etl/requirements.txt

# 1. Aplicar migraciones (operativo + dwh + etl + mineria) al remoto
supabase db push

# 2. Cargar datos y correr el ETL: seed operativo + seed Redis + ETL -> pobla el DWH
python etl/bootstrap.py
```

Alternativa 100% local (requiere Docker): `supabase db reset` aplica migraciones y corre el seed del operativo automaticamente; despues `python etl/bootstrap.py` siembra Redis y corre el ETL.

Verificacion rapida (SQL Editor):

```sql
SELECT
  (SELECT count(*) FROM dwh.dim_materia)                AS materias,    -- 300
  (SELECT count(*) FROM dwh.dim_usuario)                AS usuarios,    -- 2001 (2000 + sentinel id 0)
  (SELECT count(*) FROM dwh.dim_documento)              AS documentos,  -- 5000
  (SELECT count(*) FROM dwh.fact_interaccion_documento) AS f_doc;       -- > 0

-- La demo de prediccion debe dar tendencia = creciente
SELECT * FROM dwh.predecir_interacciones_documento(1, 3);
```

## Redis (instancia local opcional)

El motor productivo corre en **Redis Cloud** (el ETL y `bootstrap.py` lo usan via `REDIS_URL`). Para correr la demo NoSQL en local con Docker:

```bash
cd redis
docker compose up -d
```

Guia completa (RedisInsight, seed y los tres casos de uso) en **[redis/README.md](redis/README.md)**.

## Documentacion

- Monografia / entrega: **[docs/entrega.md](docs/entrega.md)**
- Despliegue del DWH: **[supabase/README.md](supabase/README.md)**
- Mineria de datos: **[docs/mineria.md](docs/mineria.md)**
- Dashboard BI: **[docs/dashboard_bi.md](docs/dashboard_bi.md)**
- Modelo y decisiones: **[design/decisiones.md](design/decisiones.md)** · DER en `design/dwh.dbml` y `design/operativo.dbml`
```
