-- =============================================================
-- DEMO 01 - Creacion
-- =============================================================
-- Crea un mini-esquema (1 dim + 1 fact) en un schema sandbox
-- (dwh_demo) para no tocar el dwh productivo. Todo va dentro
-- de BEGIN/ROLLBACK para que sea idempotente y re-ejecutable.
--
-- ETL (Creacion):
--   El script de inicializacion del ETL corre una unica vez al
--   desplegar el DWH: ejecuta CREATE SCHEMA y todos los CREATE
--   TABLE (idempotentes con IF NOT EXISTS), arma dim_tiempo con
--   un rango fijo de fechas, inserta la fila sentinel
--   id_usuario_bk=0 (busquedas de invitados anonimos) y hace la
--   carga inicial completa desde el operativo. A partir de la
--   segunda corrida pasa a modo incremental (ver demo 03).
-- =============================================================

BEGIN;

CREATE SCHEMA IF NOT EXISTS dwh_demo;

CREATE TABLE dwh_demo.dim_carrera (
    id_carrera INTEGER PRIMARY KEY,
    id_escuela INTEGER NOT NULL,
    nombre     VARCHAR(200) NOT NULL
);

CREATE TABLE dwh_demo.fact_publicacion (
    id_publicacion  BIGSERIAL PRIMARY KEY,
    fecha           DATE    NOT NULL,
    id_usuario_sk   INTEGER NOT NULL,
    id_documento_sk INTEGER NOT NULL
);

-- Verificar que las tablas quedaron creadas
SELECT table_schema, table_name
FROM   information_schema.tables
WHERE  table_schema = 'dwh_demo'
ORDER  BY table_name;

ROLLBACK;
