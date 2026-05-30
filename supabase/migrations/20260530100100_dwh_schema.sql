-- =============================================================
-- BUSCASAM DWH - Schema en estrella desnormalizado (agregado)
-- Kimball Star Schema con jerarquia Escuela > Carrera > Materia aplanada.
-- =============================================================

CREATE SCHEMA IF NOT EXISTS dwh;

-- ---------- JERARQUIA ACADEMICA (dim_materia) ----------
CREATE TABLE IF NOT EXISTS dwh.dim_materia (
    id_materia      INTEGER PRIMARY KEY,
    nombre_materia  VARCHAR(200) NOT NULL,
    id_carrera      INTEGER NOT NULL,
    nombre_carrera  VARCHAR(200) NOT NULL,
    id_escuela      INTEGER NOT NULL,
    nombre_escuela  VARCHAR(200) NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_dim_materia_escuela ON dwh.dim_materia(id_escuela);
CREATE INDEX IF NOT EXISTS idx_dim_materia_carrera ON dwh.dim_materia(id_carrera);

-- ---------- TIEMPO ----------
CREATE TABLE IF NOT EXISTS dwh.dim_tiempo (
    fecha        DATE PRIMARY KEY,
    dia          SMALLINT NOT NULL,
    mes          SMALLINT NOT NULL,
    cuatrimestre SMALLINT NOT NULL,
    anio         SMALLINT NOT NULL
);

-- ---------- USUARIO (SCD1) ----------
CREATE TABLE IF NOT EXISTS dwh.dim_usuario (
    id_usuario     INTEGER PRIMARY KEY,
    id_carrera     INTEGER NOT NULL,
    nombre_carrera VARCHAR(200) NOT NULL,
    nombre_escuela VARCHAR(200) NOT NULL,
    nombre         VARCHAR(200)
);

-- ---------- TIPO DOCUMENTO ----------
CREATE TABLE IF NOT EXISTS dwh.dim_tipo_documento (
    id_tipo INTEGER PRIMARY KEY,
    nombre  VARCHAR(50) NOT NULL
);

-- ---------- DOCUMENTO (SCD1) ----------
CREATE TABLE IF NOT EXISTS dwh.dim_documento (
    id_documento INTEGER PRIMARY KEY,
    id_tipo      INTEGER NOT NULL REFERENCES dwh.dim_tipo_documento(id_tipo),
    id_materia   INTEGER NOT NULL REFERENCES dwh.dim_materia(id_materia),
    titulo       VARCHAR(500) NOT NULL,
    fecha_alta   DATE NOT NULL,
    visibilidad  VARCHAR(20) NOT NULL,
    is_deleted   BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at   DATE
);
CREATE INDEX IF NOT EXISTS idx_dim_documento_deleted ON dwh.dim_documento(is_deleted);

-- ---------- TIPO DE INTERACCION ----------
CREATE TABLE IF NOT EXISTS dwh.dim_tipo_interaccion (
    id_tipo_interaccion INTEGER PRIMARY KEY,
    nombre              VARCHAR(50) NOT NULL
);

-- ---------- HECHO: INTERACCION CON DOCUMENTO ----------
CREATE TABLE IF NOT EXISTS dwh.fact_interaccion_documento (
    fecha               DATE NOT NULL REFERENCES dwh.dim_tiempo(fecha),
    id_documento        INTEGER NOT NULL REFERENCES dwh.dim_documento(id_documento),
    id_tipo_interaccion INTEGER NOT NULL REFERENCES dwh.dim_tipo_interaccion(id_tipo_interaccion),
    cant_interacciones  INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (fecha, id_documento, id_tipo_interaccion)
);
CREATE INDEX IF NOT EXISTS idx_fact_interaccion_fecha ON dwh.fact_interaccion_documento(fecha);
CREATE INDEX IF NOT EXISTS idx_fact_interaccion_doc   ON dwh.fact_interaccion_documento(id_documento);
CREATE INDEX IF NOT EXISTS idx_fact_interaccion_tipo  ON dwh.fact_interaccion_documento(id_tipo_interaccion);

-- ---------- HECHO: INTERACCION POR AUTOR ----------
CREATE TABLE IF NOT EXISTS dwh.fact_interaccion_autor (
    fecha               DATE NOT NULL REFERENCES dwh.dim_tiempo(fecha),
    id_usuario          INTEGER NOT NULL REFERENCES dwh.dim_usuario(id_usuario),
    id_tipo_interaccion INTEGER NOT NULL REFERENCES dwh.dim_tipo_interaccion(id_tipo_interaccion),
    cant_interacciones  INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (fecha, id_usuario, id_tipo_interaccion)
);
CREATE INDEX IF NOT EXISTS idx_fact_interaccion_autor_fecha   ON dwh.fact_interaccion_autor(fecha);
CREATE INDEX IF NOT EXISTS idx_fact_interaccion_autor_usuario ON dwh.fact_interaccion_autor(id_usuario);

-- ---------- HECHO: POPULARIDAD DE QUERIES ----------
CREATE TABLE IF NOT EXISTS dwh.fact_query_popularity (
    fecha       DATE NOT NULL REFERENCES dwh.dim_tiempo(fecha),
    query_texto TEXT NOT NULL,
    score       INTEGER NOT NULL,
    ranking     SMALLINT NOT NULL,
    PRIMARY KEY (fecha, query_texto)
);
CREATE INDEX IF NOT EXISTS idx_fact_query_pop_ranking ON dwh.fact_query_popularity(fecha, ranking);

-- ---------- CONTROL ETL ----------
CREATE TABLE IF NOT EXISTS dwh.etl_watermark (
    tabla_origen     VARCHAR(100) PRIMARY KEY,
    ultimo_procesado TIMESTAMP NOT NULL,
    ultima_corrida   TIMESTAMP NOT NULL
);
