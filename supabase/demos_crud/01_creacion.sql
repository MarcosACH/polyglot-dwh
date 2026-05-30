-- =============================================================
-- DEMO 01 - Creacion
-- =============================================================
-- Crea un mini-esquema (1 dim + 1 fact) en un schema sandbox
-- (dwh_demo) para no tocar el dwh productivo. Todo va dentro
-- de BEGIN/ROLLBACK para que sea idempotente y re-ejecutable.
--
-- Refleja el modelo agregado: el fact tiene PK compuesta
-- (fecha, id_documento, id_tipo_interaccion) y FK al catalogo
-- de tipos de interaccion.
--
-- ETL (Creacion):
--   El script de inicializacion del ETL corre una unica vez al
--   desplegar el DWH: ejecuta CREATE SCHEMA y todos los CREATE
--   TABLE (idempotentes con IF NOT EXISTS), pre-puebla dim_tiempo
--   con un rango fijo de fechas y carga los catalogos fijos
--   (dim_tipo_documento con los 8 tipos, dim_tipo_interaccion con
--   publicacion / visualizacion / favorito_agregar). Luego hace la
--   carga inicial completa: dimensiones + fact_interaccion_documento
--   + fact_interaccion_autor desde el PostgreSQL operativo y
--   fact_query_popularity desde Redis. A partir de la segunda
--   corrida pasa a modo incremental (ver demo 03).
-- =============================================================

BEGIN;

CREATE SCHEMA IF NOT EXISTS dwh_demo;

CREATE TABLE dwh_demo.dim_tipo_interaccion (
    id_tipo_interaccion INTEGER PRIMARY KEY,
    nombre              VARCHAR(50) NOT NULL
);

CREATE TABLE dwh_demo.fact_interaccion_documento (
    fecha               DATE    NOT NULL,
    id_documento        INTEGER NOT NULL,
    id_tipo_interaccion INTEGER NOT NULL
        REFERENCES dwh_demo.dim_tipo_interaccion(id_tipo_interaccion),
    cant_interacciones  INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (fecha, id_documento, id_tipo_interaccion)
);

-- Verificar que las tablas quedaron creadas
SELECT table_schema, table_name
FROM   information_schema.tables
WHERE  table_schema = 'dwh_demo'
ORDER  BY table_name;

ROLLBACK;
