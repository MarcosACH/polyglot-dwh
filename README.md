# BUSCASAM DWH

Datawarehouse analitico de **BUSCASAM**, plataforma de busqueda academica de la Universidad Nacional de San Martin (UNSAM).
Trabajo practico integrador de la materia Base de Datos.

## Contenido

Este repositorio agrupa el diseno y el codigo de las dos demos del TP:

- **DWH relacional (PostgreSQL / Supabase)** — diseno dimensional en copo de nieve con jerarquia Escuela > Carrera > Materia, schema desplegable via migrations, seed sintetico reproducible, y funciones de mineria de datos (prediccion de descargas, segmentacion de usuarios).
- **Demo NoSQL (Redis)** — instancia local en Docker con autocompletado del buscador (RediSearch), blacklist de JWT y rate limiting por usuario.
- **Documentacion** academica y operativa.

## Stack

| Capa            | Tecnologia                                |
|-----------------|-------------------------------------------|
| DWH             | PostgreSQL (Supabase, schema `dwh`)       |
| NoSQL           | Redis Stack (Docker, con RediSearch)      |
| Migrations / CI | Supabase CLI                              |
| Visualizacion   | Power BI + RedisInsight                   |
| Diagramas       | DBML ([dbdiagram.io](https://dbdiagram.io)) |

## Estructura del repo

```
.
|-- README.md                  Este archivo
|-- .gitignore
|-- docs/
|   |-- consigna.md            Consigna oficial del TP
|   |-- spec.md                Especificacion funcional de BUSCASAM
|   |-- entrega.md             Documento de entrega
|   `-- setup-supabase.md      Guia operativa: Supabase + migrations + seed
|-- design/
|   |-- der_dwh.dbml           DER vigente (copiar/pegar en dbdiagram.io)
|   `-- der_dwh_v1.dbml        DER inicial (legacy, referencia historica)
|-- supabase/
|   |-- config.toml            Config del proyecto Supabase
|   |-- migrations/            Migrations versionadas (orden lexicografico)
|   |   |-- 0001_dwh_schema.sql
|   |   `-- 0002_dwh_functions.sql
|   |-- seed.sql               Carga de datos sinteticos reproducible
|   `-- optional/
|       `-- segmentar_usuarios_plpython.sql   Requiere plpython3u (self-hosted)
`-- redis/
    |-- README.md              Guia operativa: Docker + seed + demos
    |-- docker-compose.yml     Redis Stack + RedisInsight
    |-- seed/                  Datos sinteticos y script de carga
    |   |-- data.json
    |   |-- seed.py
    |   `-- requirements.txt
    `-- demo/                  Paso a paso de cada caso de uso
        |-- 01_autocomplete.md
        |-- 02_jwt_blacklist.md
        `-- 03_rate_limit.md
```

## Quick start

### DWH PostgreSQL (Supabase)

Ver **[docs/setup-supabase.md](docs/setup-supabase.md)** para la guia paso a paso.

Resumen para alguien que ya tiene la CLI instalada y el proyecto linkeado:

```powershell
supabase db push          # aplica migrations/ al remoto
# Cargar datos: copiar supabase/seed.sql en el SQL Editor del dashboard y ejecutar.
```

Verificacion rapida (SQL Editor):

```sql
SELECT
  (SELECT count(*) FROM dwh.dim_usuario)    AS usuarios,
  (SELECT count(*) FROM dwh.dim_documento)  AS documentos,
  (SELECT count(*) FROM dwh.fact_busqueda)  AS busquedas;
-- Esperado: 2051 | 5100 | 50000
```

### Redis (Docker)

Ver **[redis/README.md](redis/README.md)** para la guia completa (incluye RedisInsight, troubleshooting y los tres pasos a paso de las demos).

Resumen para alguien que ya tiene Docker:

```bash
cd redis
docker compose up -d
cd seed && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python seed.py
```

Abrir RedisInsight en <http://localhost:8001> y agregar la base en `127.0.0.1:6379`.

Verificacion rapida:

```bash
docker compose exec redis redis-cli FT.SUGGET autocomplete:queries "rede" MAX 5
# Esperado: 5 sugerencias empezando por "redes neuronales"
```
