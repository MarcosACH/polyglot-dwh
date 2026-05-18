# BUSCASAM DWH

Datawarehouse analitico de **BUSCASAM**, plataforma de busqueda academica de la Universidad Nacional de San Martin (UNSAM).
Trabajo practico integrador de la materia Base de Datos.

## Contenido

Este repositorio agrupa el diseno y el codigo del datawarehouse (DWH) que alimenta los tableros de Power BI a partir del operativo de BUSCASAM:

- **Diseno dimensional** en copo de nieve con jerarquia Escuela > Carrera > Materia.
- **Schema PostgreSQL** desplegable en Supabase via migrations.
- **Datos sinteticos** reproducibles para desarrollo y demos.
- **Funciones de mineria de datos** (prediccion de descargas y segmentacion de usuarios).
- **Documentacion** academica y operativa.

## Stack

| Capa            | Tecnologia                                |
|-----------------|-------------------------------------------|
| DWH             | PostgreSQL (Supabase, schema `dwh`)       |
| Migrations / CI | Supabase CLI                              |
| Visualizacion   | Power BI                                  |
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
`-- supabase/
    |-- config.toml            Config del proyecto Supabase
    |-- migrations/            Migrations versionadas (orden lexicografico)
    |   |-- 0001_dwh_schema.sql
    |   `-- 0002_dwh_functions.sql
    |-- seed.sql               Carga de datos sinteticos reproducible
    `-- optional/
        `-- segmentar_usuarios_plpython.sql   Requiere plpython3u (self-hosted)
```

## Quick start

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
