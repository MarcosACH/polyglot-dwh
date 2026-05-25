-- 1. Habilitar la extensión pgvector
CREATE EXTENSION IF NOT EXISTS vector;

-- 2. Crear un esquema dedicado para mantener el orden
CREATE SCHEMA IF NOT EXISTS vectorial;

-- Mudar la extensión al esquema seguro
ALTER EXTENSION vector SET SCHEMA vectorial;

DROP TABLE IF EXISTS vectorial.documentos;

CREATE TABLE vectorial.documentos (
    id               SERIAL PRIMARY KEY,
    id_documento_bk  INTEGER NOT NULL,    -- ID de negocio del paper
    id_escuela       INTEGER NOT NULL,    -- Filtro directo de Escuela
    id_carrera       INTEGER NOT NULL,    -- Filtro directo de Carrera
    id_materia       INTEGER NOT NULL,    -- Filtro directo de Materia
    id_tipo          INTEGER NOT NULL,    -- Filtro directo de Tipo de documento
    
    titulo           VARCHAR(500) NOT NULL,
    abstract         TEXT NOT NULL,
    texto_completo   TEXT,                
    archivo_url      TEXT NOT NULL,       
    
    -- El vector local de 384 dimensiones (all-MiniLM-L6-v2)
    embedding        vectorial.vector(384), 
    
    -- Buscador léxico integrado en español
    texto_busqueda   tsvector GENERATED ALWAYS AS (
                         to_tsvector('spanish',
                             coalesce(titulo, '') || ' ' ||
                             coalesce(abstract, '') || ' ' ||
                             coalesce(texto_completo, '')
                         )
                     ) STORED,
                     
    fecha_alta       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 1. Índice Vectorial HNSW (Semántica)
CREATE INDEX idx_documentos_embedding_hnsw 
    ON vectorial.documentos USING hnsw (embedding vectorial.vector_cosine_ops);

-- 2. Índice GIN (Palabras clave exactas)
CREATE INDEX idx_documentos_texto_busqueda_gin 
    ON vectorial.documentos USING gin (texto_busqueda);

-- 3. Índices B-Tree para los filtros deterministicos de la UI
CREATE INDEX idx_documentos_escuela ON vectorial.documentos (id_escuela);
CREATE INDEX idx_documentos_carrera ON vectorial.documentos (id_carrera);
CREATE INDEX idx_documentos_materia ON vectorial.documentos (id_materia);
CREATE INDEX idx_documentos_tipo    ON vectorial.documentos (id_tipo);

-- Seguridad RLS
ALTER TABLE vectorial.documentos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Permitir lectura publica de documentos" 
ON vectorial.documentos FOR SELECT USING (true);

-- Para Buscar (Lectura): cualquier consulta de lectura (SELECT) que haga la API para buscar papers va a funcionar perfectamente sin restricciones.

--Para Insertar/Subir Papers (Escritura): Como la inserción de nuevos papers la va a hacer el script de Python o el backend del MVP, lo ideal es que esa conexión use la service_role_key (la clave secreta de administrador que te da Supabase en la configuración)