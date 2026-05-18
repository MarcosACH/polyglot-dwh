-- =============================================================
-- BUSCASAM DWH - Schema en copo de nieve
-- Snowflake con jerarquia Escuela > Carrera > Materia normalizada.
-- =============================================================

CREATE SCHEMA IF NOT EXISTS dwh;

-- ---------- JERARQUIA ACADEMICA (snowflake) ----------

CREATE TABLE IF NOT EXISTS dwh.dim_escuela (
    id_escuela INTEGER PRIMARY KEY,
    nombre     VARCHAR(200) NOT NULL
);

CREATE TABLE IF NOT EXISTS dwh.dim_carrera (
    id_carrera INTEGER PRIMARY KEY,
    id_escuela INTEGER NOT NULL REFERENCES dwh.dim_escuela(id_escuela),
    nombre     VARCHAR(200) NOT NULL
);

CREATE TABLE IF NOT EXISTS dwh.dim_materia (
    id_materia INTEGER PRIMARY KEY,
    id_carrera INTEGER NOT NULL REFERENCES dwh.dim_carrera(id_carrera),
    nombre     VARCHAR(200) NOT NULL
);

-- ---------- TIEMPO ----------

CREATE TABLE IF NOT EXISTS dwh.dim_tiempo (
    fecha        DATE PRIMARY KEY,
    dia          SMALLINT NOT NULL,
    mes          SMALLINT NOT NULL,
    cuatrimestre SMALLINT NOT NULL,
    anio         SMALLINT NOT NULL
);

-- ---------- ROL Y USUARIO (SCD2) ----------

CREATE TABLE IF NOT EXISTS dwh.dim_rol (
    id_rol INTEGER PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL
);

CREATE TABLE IF NOT EXISTS dwh.dim_usuario (
    id_usuario_sk INTEGER PRIMARY KEY,
    id_usuario_bk INTEGER NOT NULL,
    id_rol        INTEGER NOT NULL REFERENCES dwh.dim_rol(id_rol),
    id_carrera    INTEGER REFERENCES dwh.dim_carrera(id_carrera),
    nombre        VARCHAR(200),
    email_hash    VARCHAR(64),
    valid_from    DATE NOT NULL,
    valid_to      DATE,
    is_current    BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE INDEX IF NOT EXISTS idx_dim_usuario_bk_current
    ON dwh.dim_usuario(id_usuario_bk, is_current);

-- ---------- DOCUMENTO (SCD2, soft-delete) ----------

CREATE TABLE IF NOT EXISTS dwh.dim_tipo_documento (
    id_tipo INTEGER PRIMARY KEY,
    nombre  VARCHAR(50) NOT NULL
);

CREATE TABLE IF NOT EXISTS dwh.dim_documento (
    id_documento_sk INTEGER PRIMARY KEY,
    id_documento_bk INTEGER NOT NULL,
    id_tipo         INTEGER NOT NULL REFERENCES dwh.dim_tipo_documento(id_tipo),
    id_materia      INTEGER NOT NULL REFERENCES dwh.dim_materia(id_materia),
    titulo          VARCHAR(500) NOT NULL,
    fecha_alta      DATE NOT NULL,
    visibilidad     VARCHAR(20) NOT NULL,
    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at      DATE,
    valid_from      DATE NOT NULL,
    valid_to        DATE,
    is_current      BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE INDEX IF NOT EXISTS idx_dim_documento_bk_current
    ON dwh.dim_documento(id_documento_bk, is_current);
CREATE INDEX IF NOT EXISTS idx_dim_documento_deleted_current
    ON dwh.dim_documento(is_deleted, is_current);

-- ---------- BRIDGE CO-AUTORIA (peso = 1/N) ----------

CREATE TABLE IF NOT EXISTS dwh.bridge_documento_autor (
    id_documento_sk INTEGER NOT NULL REFERENCES dwh.dim_documento(id_documento_sk),
    id_usuario_sk   INTEGER NOT NULL REFERENCES dwh.dim_usuario(id_usuario_sk),
    orden           SMALLINT NOT NULL,
    peso            NUMERIC(5,4) NOT NULL,
    PRIMARY KEY (id_documento_sk, id_usuario_sk)
);

-- ---------- HECHOS ----------

CREATE TABLE IF NOT EXISTS dwh.fact_busqueda (
    id_busqueda              BIGSERIAL PRIMARY KEY,
    fecha                    DATE    NOT NULL REFERENCES dwh.dim_tiempo(fecha),
    id_usuario_sk            INTEGER NOT NULL REFERENCES dwh.dim_usuario(id_usuario_sk),
    id_escuela_filtro        INTEGER REFERENCES dwh.dim_escuela(id_escuela),
    id_carrera_filtro        INTEGER REFERENCES dwh.dim_carrera(id_carrera),
    id_materia_filtro        INTEGER REFERENCES dwh.dim_materia(id_materia),
    id_tipo_documento_filtro INTEGER REFERENCES dwh.dim_tipo_documento(id_tipo),
    fecha_desde_filtro       DATE,
    fecha_hasta_filtro       DATE,
    query_texto              TEXT    NOT NULL,
    cant_resultados          INTEGER NOT NULL,
    hizo_click               BOOLEAN NOT NULL,
    session_hash             VARCHAR(64)
);
CREATE INDEX IF NOT EXISTS idx_fact_busqueda_fecha   ON dwh.fact_busqueda(fecha);
CREATE INDEX IF NOT EXISTS idx_fact_busqueda_materia ON dwh.fact_busqueda(id_materia_filtro);

CREATE TABLE IF NOT EXISTS dwh.fact_visualizacion (
    id_visualizacion BIGSERIAL PRIMARY KEY,
    fecha            DATE    NOT NULL REFERENCES dwh.dim_tiempo(fecha),
    id_usuario_sk    INTEGER NOT NULL REFERENCES dwh.dim_usuario(id_usuario_sk),
    id_documento_sk  INTEGER NOT NULL REFERENCES dwh.dim_documento(id_documento_sk)
);
CREATE INDEX IF NOT EXISTS idx_fact_visualizacion_fecha ON dwh.fact_visualizacion(fecha);
CREATE INDEX IF NOT EXISTS idx_fact_visualizacion_doc   ON dwh.fact_visualizacion(id_documento_sk);

CREATE TABLE IF NOT EXISTS dwh.fact_publicacion (
    id_publicacion  BIGSERIAL PRIMARY KEY,
    fecha           DATE    NOT NULL REFERENCES dwh.dim_tiempo(fecha),
    id_usuario_sk   INTEGER NOT NULL REFERENCES dwh.dim_usuario(id_usuario_sk),
    id_documento_sk INTEGER NOT NULL REFERENCES dwh.dim_documento(id_documento_sk)
);
CREATE INDEX IF NOT EXISTS idx_fact_publicacion_fecha ON dwh.fact_publicacion(fecha);

CREATE TABLE IF NOT EXISTS dwh.fact_descarga (
    id_descarga     BIGSERIAL PRIMARY KEY,
    fecha           DATE    NOT NULL REFERENCES dwh.dim_tiempo(fecha),
    id_usuario_sk   INTEGER NOT NULL REFERENCES dwh.dim_usuario(id_usuario_sk),
    id_documento_sk INTEGER NOT NULL REFERENCES dwh.dim_documento(id_documento_sk)
);
CREATE INDEX IF NOT EXISTS idx_fact_descarga_fecha ON dwh.fact_descarga(fecha);
CREATE INDEX IF NOT EXISTS idx_fact_descarga_doc   ON dwh.fact_descarga(id_documento_sk);

CREATE TABLE IF NOT EXISTS dwh.fact_favorito (
    id_favorito     BIGSERIAL PRIMARY KEY,
    fecha           DATE    NOT NULL REFERENCES dwh.dim_tiempo(fecha),
    id_usuario_sk   INTEGER NOT NULL REFERENCES dwh.dim_usuario(id_usuario_sk),
    id_documento_sk INTEGER NOT NULL REFERENCES dwh.dim_documento(id_documento_sk),
    accion          VARCHAR(10) NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_fact_favorito_fecha    ON dwh.fact_favorito(fecha);
CREATE INDEX IF NOT EXISTS idx_fact_favorito_doc      ON dwh.fact_favorito(id_documento_sk);
CREATE INDEX IF NOT EXISTS idx_fact_favorito_user_doc ON dwh.fact_favorito(id_usuario_sk, id_documento_sk);

CREATE TABLE IF NOT EXISTS dwh.fact_comentario (
    id_comentario       BIGINT PRIMARY KEY,
    fecha               DATE    NOT NULL REFERENCES dwh.dim_tiempo(fecha),
    id_usuario_sk       INTEGER NOT NULL REFERENCES dwh.dim_usuario(id_usuario_sk),
    id_documento_sk     INTEGER NOT NULL REFERENCES dwh.dim_documento(id_documento_sk),
    id_comentario_padre BIGINT  REFERENCES dwh.fact_comentario(id_comentario),
    esta_oculto         BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_oculto        DATE
);
CREATE INDEX IF NOT EXISTS idx_fact_comentario_fecha ON dwh.fact_comentario(fecha);
CREATE INDEX IF NOT EXISTS idx_fact_comentario_doc   ON dwh.fact_comentario(id_documento_sk);
CREATE INDEX IF NOT EXISTS idx_fact_comentario_user  ON dwh.fact_comentario(id_usuario_sk);
CREATE INDEX IF NOT EXISTS idx_fact_comentario_padre ON dwh.fact_comentario(id_comentario_padre);

-- ---------- CONTROL ETL ----------

CREATE TABLE IF NOT EXISTS dwh.etl_watermark (
    tabla_origen     VARCHAR(100) PRIMARY KEY,
    ultimo_procesado TIMESTAMP NOT NULL,
    ultima_corrida   TIMESTAMP NOT NULL
);
