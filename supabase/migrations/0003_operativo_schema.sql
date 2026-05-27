-- =============================================================
-- BUSCASAM - Schema Operativo (OLTP)
-- =============================================================
-- Este script define el schema 'operativo' que sirve como
-- fuente de verdad transaccional para la aplicacion y del cual
-- se alimenta el Data Warehouse (DWH) mediante procesos ETL.
-- =============================================================

CREATE SCHEMA IF NOT EXISTS operativo;

-- Habilitar extension pgvector para busqueda semantica
CREATE EXTENSION IF NOT EXISTS vector SCHEMA public;

-- =============================================================
-- FUNCION AUXILIAR PARA TRIGGER DE ACTUALIZACION (updated_at)
-- =============================================================
CREATE OR REPLACE FUNCTION operativo.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =============================================================
-- JERARQUIA ACADEMICA
-- =============================================================

-- 1. escuela
CREATE TABLE IF NOT EXISTS operativo.escuela (
    id         SERIAL PRIMARY KEY,
    nombre     VARCHAR(200) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER update_escuela_updated_at
    BEFORE UPDATE ON operativo.escuela
    FOR EACH ROW
    EXECUTE FUNCTION operativo.update_updated_at_column();

-- 2. carrera
CREATE TABLE IF NOT EXISTS operativo.carrera (
    id         SERIAL PRIMARY KEY,
    id_escuela INTEGER NOT NULL REFERENCES operativo.escuela(id) ON DELETE RESTRICT,
    nombre     VARCHAR(200) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_carrera_escuela ON operativo.carrera(id_escuela);

CREATE TRIGGER update_carrera_updated_at
    BEFORE UPDATE ON operativo.carrera
    FOR EACH ROW
    EXECUTE FUNCTION operativo.update_updated_at_column();

-- 3. materia
CREATE TABLE IF NOT EXISTS operativo.materia (
    id         SERIAL PRIMARY KEY,
    id_carrera INTEGER NOT NULL REFERENCES operativo.carrera(id) ON DELETE RESTRICT,
    nombre     VARCHAR(200) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_materia_carrera ON operativo.materia(id_carrera);

CREATE TRIGGER update_materia_updated_at
    BEFORE UPDATE ON operativo.materia
    FOR EACH ROW
    EXECUTE FUNCTION operativo.update_updated_at_column();

-- =============================================================
-- USUARIOS
-- =============================================================

-- 4. usuario
CREATE TABLE IF NOT EXISTS operativo.usuario (
    id         SERIAL PRIMARY KEY,
    email      VARCHAR(255) NOT NULL UNIQUE CHECK (email ~* '^[A-Z0-9._%-]+@[A-Z0-9.-]+\.[A-Z]{2,4}$'),
    nombre     VARCHAR(200) NOT NULL,
    rol        VARCHAR(20) NOT NULL CHECK (rol IN ('estudiante', 'docente')),
    id_carrera INTEGER REFERENCES operativo.carrera(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indice en FK para evitar sequential scans durante deletes en carrera
CREATE INDEX IF NOT EXISTS idx_usuario_carrera ON operativo.usuario(id_carrera);

CREATE TRIGGER update_usuario_updated_at
    BEFORE UPDATE ON operativo.usuario
    FOR EACH ROW
    EXECUTE FUNCTION operativo.update_updated_at_column();

-- =============================================================
-- DOCUMENTOS (con vectorial integrada)
-- =============================================================

-- 5. tipo_documento
CREATE TABLE IF NOT EXISTS operativo.tipo_documento (
    id     SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE
);

-- 6. documento
CREATE TABLE IF NOT EXISTS operativo.documento (
    id              SERIAL PRIMARY KEY,
    titulo          VARCHAR(500) NOT NULL,
    abstract        TEXT,
    texto_completo  TEXT,
    visibilidad     VARCHAR(20) NOT NULL CHECK (visibilidad IN ('publico', 'interno', 'privado')),
    id_tipo         INTEGER NOT NULL REFERENCES operativo.tipo_documento(id) ON DELETE RESTRICT,
    id_materia      INTEGER NOT NULL REFERENCES operativo.materia(id) ON DELETE RESTRICT,
    id_uploader     INTEGER NOT NULL REFERENCES operativo.usuario(id) ON DELETE RESTRICT,
    archivo_url     TEXT,
    
    -- pgvector embedding (384 dimensiones - all-MiniLM-L6-v2)
    embedding       public.vector(384),
    
    -- tsvector generada siempre para busqueda lexica en espanol
    texto_busqueda  tsvector GENERATED ALWAYS AS (
                        to_tsvector('spanish',
                            coalesce(titulo, '') || ' ' ||
                            coalesce(abstract, '') || ' ' ||
                            coalesce(texto_completo, '')
                        )
                    ) STORED,
                    
    deleted_at      TIMESTAMPTZ, -- soft delete (NULL = activo)
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indices parciales para optimizar busquedas deterministicas de UI sobre documentos activos
CREATE INDEX IF NOT EXISTS idx_documento_materia_activo ON operativo.documento(id_materia) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_documento_tipo_activo    ON operativo.documento(id_tipo) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_documento_uploader       ON operativo.documento(id_uploader);

-- Indice vectorial HNSW (similitud coseno)
CREATE INDEX IF NOT EXISTS idx_documento_embedding_hnsw
    ON operativo.documento USING hnsw (embedding public.vector_cosine_ops);

-- Indice GIN para busqueda lexica (tsvector)
CREATE INDEX IF NOT EXISTS idx_documento_texto_busqueda_gin
    ON operativo.documento USING gin (texto_busqueda);

CREATE TRIGGER update_documento_updated_at
    BEFORE UPDATE ON operativo.documento
    FOR EACH ROW
    EXECUTE FUNCTION operativo.update_updated_at_column();

-- =============================================================
-- CO-AUTORIAS
-- =============================================================

-- 7. documento_autor
CREATE TABLE IF NOT EXISTS operativo.documento_autor (
    id_documento INTEGER NOT NULL REFERENCES operativo.documento(id) ON DELETE CASCADE,
    id_usuario   INTEGER NOT NULL REFERENCES operativo.usuario(id) ON DELETE RESTRICT,
    orden        SMALLINT NOT NULL CHECK (orden >= 1),
    PRIMARY KEY (id_documento, id_usuario)
);

CREATE INDEX IF NOT EXISTS idx_doc_autor_usuario ON operativo.documento_autor(id_usuario);

-- =============================================================
-- INTERACCIONES Y EVENTOS
-- =============================================================

-- 8. favorito (estado activo de favoritos)
CREATE TABLE IF NOT EXISTS operativo.favorito (
    id_usuario   INTEGER NOT NULL REFERENCES operativo.usuario(id) ON DELETE CASCADE,
    id_documento INTEGER NOT NULL REFERENCES operativo.documento(id) ON DELETE CASCADE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (id_usuario, id_documento)
);

CREATE INDEX IF NOT EXISTS idx_favorito_documento ON operativo.favorito(id_documento);

-- 9. evento_visualizacion
CREATE TABLE IF NOT EXISTS operativo.evento_visualizacion (
    id           BIGSERIAL PRIMARY KEY,
    id_usuario   INTEGER REFERENCES operativo.usuario(id) ON DELETE SET NULL, -- NULL = invitado
    id_documento INTEGER NOT NULL REFERENCES operativo.documento(id) ON DELETE CASCADE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_evento_vis_created   ON operativo.evento_visualizacion(created_at);
CREATE INDEX IF NOT EXISTS idx_evento_vis_documento ON operativo.evento_visualizacion(id_documento);
CREATE INDEX IF NOT EXISTS idx_evento_vis_usuario   ON operativo.evento_visualizacion(id_usuario);

-- 10. descarga (evento de descarga de archivos)
CREATE TABLE IF NOT EXISTS operativo.descarga (
    id           BIGSERIAL PRIMARY KEY,
    id_usuario   INTEGER REFERENCES operativo.usuario(id) ON DELETE SET NULL, -- NULL = invitado
    id_documento INTEGER NOT NULL REFERENCES operativo.documento(id) ON DELETE CASCADE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_descarga_created   ON operativo.descarga(created_at);
CREATE INDEX IF NOT EXISTS idx_descarga_documento ON operativo.descarga(id_documento);
CREATE INDEX IF NOT EXISTS idx_descarga_usuario   ON operativo.descarga(id_usuario);

-- 11. comentario (comentarios con moderacion reactiva y threading 1 nivel)
CREATE TABLE IF NOT EXISTS operativo.comentario (
    id                  BIGSERIAL PRIMARY KEY,
    id_usuario          INTEGER NOT NULL REFERENCES operativo.usuario(id) ON DELETE CASCADE,
    id_documento        INTEGER NOT NULL REFERENCES operativo.documento(id) ON DELETE CASCADE,
    id_comentario_padre BIGINT REFERENCES operativo.comentario(id) ON DELETE CASCADE, -- NULL = raiz
    texto               TEXT NOT NULL CHECK (char_length(texto) <= 2000), -- limite anti-abuso
    esta_oculto         BOOLEAN NOT NULL DEFAULT FALSE,
    fecha_oculto        TIMESTAMPTZ, -- nulo si no esta moderado
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_comentario_created   ON operativo.comentario(created_at);
CREATE INDEX IF NOT EXISTS idx_comentario_documento ON operativo.comentario(id_documento);
CREATE INDEX IF NOT EXISTS idx_comentario_usuario   ON operativo.comentario(id_usuario);
CREATE INDEX IF NOT EXISTS idx_comentario_padre     ON operativo.comentario(id_comentario_padre);

CREATE TRIGGER update_comentario_updated_at
    BEFORE UPDATE ON operativo.comentario
    FOR EACH ROW
    EXECUTE FUNCTION operativo.update_updated_at_column();

-- 12. busqueda (historial de busquedas y filtros aplicados)
CREATE TABLE IF NOT EXISTS operativo.busqueda (
    id                       BIGSERIAL PRIMARY KEY,
    id_usuario               INTEGER REFERENCES operativo.usuario(id) ON DELETE SET NULL, -- NULL = invitado
    query_texto              TEXT NOT NULL CHECK (char_length(query_texto) <= 255), -- limite anti-abuso
    
    -- Filtros aplicados
    id_escuela_filtro        INTEGER REFERENCES operativo.escuela(id) ON DELETE SET NULL,
    id_carrera_filtro        INTEGER REFERENCES operativo.carrera(id) ON DELETE SET NULL,
    id_materia_filtro        INTEGER REFERENCES operativo.materia(id) ON DELETE SET NULL,
    id_tipo_documento_filtro INTEGER REFERENCES operativo.tipo_documento(id) ON DELETE SET NULL,
    fecha_desde_filtro       DATE,
    fecha_hasta_filtro       DATE,
    
    cant_resultados          INTEGER NOT NULL DEFAULT 0,
    hizo_click               BOOLEAN NOT NULL DEFAULT FALSE,
    session_hash             VARCHAR(64),
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indices para optimizacion de busquedas y deletes en cascada
CREATE INDEX IF NOT EXISTS idx_busqueda_created        ON operativo.busqueda(created_at);
CREATE INDEX IF NOT EXISTS idx_busqueda_usuario        ON operativo.busqueda(id_usuario);
CREATE INDEX IF NOT EXISTS idx_busqueda_materia_filtro ON operativo.busqueda(id_materia_filtro);
CREATE INDEX IF NOT EXISTS idx_busqueda_escuela_filtro ON operativo.busqueda(id_escuela_filtro);
CREATE INDEX IF NOT EXISTS idx_busqueda_carrera_filtro ON operativo.busqueda(id_carrera_filtro);
CREATE INDEX IF NOT EXISTS idx_busqueda_tipo_filtro    ON operativo.busqueda(id_tipo_documento_filtro);
