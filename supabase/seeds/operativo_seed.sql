-- =============================================================
-- BUSCASAM - Seed Data Schema Operativo (OLTP)
-- =============================================================
-- Genera datos de prueba coherentes con los volumenes
-- del DWH seed. Utiliza setseed para reproducibilidad.
-- =============================================================

SELECT setseed(0.42);

-- ---------- escuelas (5) ----------
INSERT INTO operativo.escuela (id, nombre, created_at, updated_at) VALUES
    (1, 'Escuela de Ciencia y Tecnologia', '2024-01-01 00:00:00+00', '2024-01-01 00:00:00+00'),
    (2, 'Escuela de Humanidades', '2024-01-01 00:00:00+00', '2024-01-01 00:00:00+00'),
    (3, 'Escuela de Economia y Negocios', '2024-01-01 00:00:00+00', '2024-01-01 00:00:00+00'),
    (4, 'Escuela de Politica y Gobierno', '2024-01-01 00:00:00+00', '2024-01-01 00:00:00+00'),
    (5, 'Escuela de Bio y Nanotecnologias', '2024-01-01 00:00:00+00', '2024-01-01 00:00:00+00');

SELECT setval('operativo.escuela_id_seq', (SELECT max(id) FROM operativo.escuela));

-- ---------- carreras (30) ----------
INSERT INTO operativo.carrera (id, id_escuela, nombre, created_at, updated_at)
SELECT
    i,
    ((i - 1) % 5) + 1,
    'Carrera ' || i,
    '2024-01-01 00:00:00+00',
    '2024-01-01 00:00:00+00'
FROM generate_series(1, 30) i;

-- Nombres realistas para las primeras 10 (coincidentes con DWH)
UPDATE operativo.carrera SET nombre = 'Ingenieria en Informatica'  WHERE id = 1;
UPDATE operativo.carrera SET nombre = 'Licenciatura en Letras'     WHERE id = 2;
UPDATE operativo.carrera SET nombre = 'Contador Publico'           WHERE id = 3;
UPDATE operativo.carrera SET nombre = 'Ciencia Politica'           WHERE id = 4;
UPDATE operativo.carrera SET nombre = 'Biotecnologia'              WHERE id = 5;
UPDATE operativo.carrera SET nombre = 'Ingenieria Electronica'     WHERE id = 6;
UPDATE operativo.carrera SET nombre = 'Licenciatura en Historia'   WHERE id = 7;
UPDATE operativo.carrera SET nombre = 'Administracion de Empresas' WHERE id = 8;
UPDATE operativo.carrera SET nombre = 'Relaciones Internacionales' WHERE id = 9;
UPDATE operativo.carrera SET nombre = 'Bioinformatica'             WHERE id = 10;

SELECT setval('operativo.carrera_id_seq', (SELECT max(id) FROM operativo.carrera));

-- ---------- materias (300) ----------
INSERT INTO operativo.materia (id, id_carrera, nombre, created_at, updated_at)
SELECT
    i,
    ((i - 1) % 30) + 1,
    'Materia ' || i,
    '2024-01-01 00:00:00+00',
    '2024-01-01 00:00:00+00'
FROM generate_series(1, 300) i;

SELECT setval('operativo.materia_id_seq', (SELECT max(id) FROM operativo.materia));

-- ---------- tipos de documento ----------
INSERT INTO operativo.tipo_documento (id, nombre) VALUES
    (1, 'tesis'),
    (2, 'paper'),
    (3, 'trabajo_practico'),
    (4, 'proyecto_investigacion'),
    (5, 'monografia'),
    (6, 'ponencia'),
    (7, 'apunte'),
    (8, 'informe_catedra');

SELECT setval('operativo.tipo_documento_id_seq', (SELECT max(id) FROM operativo.tipo_documento));

-- ---------- usuarios (2000) ----------
INSERT INTO operativo.usuario (id, email, nombre, rol, id_carrera, created_at, updated_at)
SELECT
    i,
    'usuario' || i || '@unsam.edu.ar',
    'Usuario ' || i,
    CASE WHEN random() < 0.85 THEN 'estudiante' ELSE 'docente' END,
    (floor(power(random(), 1.5) * 30))::int + 1,
    '2024-01-01 00:00:00+00'::timestamptz + (random() * 700)::int * INTERVAL '1 day',
    '2024-01-01 00:00:00+00'::timestamptz + (random() * 700)::int * INTERVAL '1 day'
FROM generate_series(1, 2000) i;

-- Aplicar cambios para reflejar el estado actual de los usuarios promocionados el 2025-06-01 (SCD2 en DWH)
UPDATE operativo.usuario
SET
    rol = 'docente',
    id_carrera = ((id * 17) % 30) + 1,
    updated_at = '2025-06-01 00:00:00+00'::timestamptz
WHERE id BETWEEN 1 AND 50;

SELECT setval('operativo.usuario_id_seq', (SELECT max(id) FROM operativo.usuario));

-- ---------- documentos (5000) ----------

-- Crear una funcion auxiliar temporal para generar un vector mock de 384 dimensiones
CREATE OR REPLACE FUNCTION operativo.generar_mock_vector(seed_val INT)
RETURNS public.vector AS $$
DECLARE
    v_arr FLOAT[];
    i INT;
BEGIN
    FOR i IN 1..384 LOOP
        v_arr := v_arr || (sin(seed_val * 0.1 + i * 0.05) * 0.5)::FLOAT;
    END LOOP;
    RETURN v_arr::public.vector;
END;
$$ LANGUAGE plpgsql;

WITH raw_data AS (
    SELECT
        i,
        '2024-01-01'::timestamptz + (random() * 879)::int * INTERVAL '1 day' + (random() * 24)::int * INTERVAL '1 hour' AS c_at,
        random() AS r_vis,
        random() AS r_tipo,
        random() AS r_mat,
        random() AS r_up,
        random() AS r_del
    FROM generate_series(1, 5000) i
)
INSERT INTO operativo.documento (
    id, titulo, abstract, texto_completo, visibilidad,
    id_tipo, id_materia, id_uploader, archivo_url, embedding,
    deleted_at, created_at, updated_at
)
SELECT
    i,
    'Documento ' || i || ': estudio sobre ' ||
        (ARRAY['IA aplicada','cambio climatico','politica publica','genomica',
               'historia argentina','algebra lineal','sociologia urbana','redes neuronales',
               'biotecnologia','filosofia','ecologia','derecho ambiental'])[((i * 7) % 12) + 1],
    'Resumen del documento ' || i || '. Este estudio analiza las implicancias de la investigacion en ' || 
        (ARRAY['IA aplicada','cambio climatico','politica publica','genomica',
               'historia argentina','algebra lineal','sociologia urbana','redes neuronales',
               'biotecnologia','filosofia','ecologia','derecho ambiental'])[((i * 7) % 12) + 1] || 
        ' en el ambito academico y cientifico, aportando nuevos enfoques conceptuales.',
    'Contenido completo del documento de prueba numero ' || i || '. Describe detalladamente la metodologia empleada, el marco teorico, los experimentos realizados y las conclusiones. Se discute extensamente la relacion con ' || 
        (ARRAY['IA aplicada','cambio climatico','politica publica','genomica',
               'historia argentina','algebra lineal','sociologia urbana','redes neuronales',
               'biotecnologia','filosofia','ecologia','derecho ambiental'])[((i * 7) % 12) + 1] || 
        ' y la bibliografia asociada. Se concluye que el impacto en la materia es relevante.',
    CASE WHEN r_vis < 0.70 THEN 'publico' WHEN r_vis < 0.90 THEN 'interno' ELSE 'privado' END,
    CASE 
        WHEN r_tipo < 0.05 THEN 1
        WHEN r_tipo < 0.20 THEN 2
        WHEN r_tipo < 0.55 THEN 3
        WHEN r_tipo < 0.60 THEN 4
        WHEN r_tipo < 0.75 THEN 5
        WHEN r_tipo < 0.80 THEN 6
        WHEN r_tipo < 0.95 THEN 7
        ELSE 8 
    END,
    (floor(power(r_mat, 1.5) * 300))::int + 1,
    (floor(power(r_up, 3) * 1999))::int + 1,
    'https://storage.buscasam.unsam.edu.ar/documentos/' || i || '.pdf',
    operativo.generar_mock_vector(i),
    CASE WHEN r_del < 0.03 THEN c_at + (random() * 80)::int * INTERVAL '1 day' ELSE NULL END,
    c_at,
    c_at
FROM raw_data;

-- Eliminar la funcion auxiliar temporal
DROP FUNCTION IF EXISTS operativo.generar_mock_vector(INT);

-- Aplicar cambios para reflejar el estado actual de los documentos modificados el 2025-09-01 (SCD2 en DWH)
UPDATE operativo.documento
SET
    id_materia = ((id * 29) % 300) + 1,
    updated_at = '2025-09-01 00:00:00+00'::timestamptz
WHERE id BETWEEN 1 AND 100;

SELECT setval('operativo.documento_id_seq', (SELECT max(id) FROM operativo.documento));

-- ---------- documento_autor (N:M co-autorias) ----------

-- Autor principal (orden = 1)
INSERT INTO operativo.documento_autor (id_documento, id_usuario, orden)
SELECT
    id,
    id_uploader,
    1
FROM operativo.documento;

-- Co-autor 2 para ~30% de los documentos
INSERT INTO operativo.documento_autor (id_documento, id_usuario, orden)
SELECT
    id,
    ((id * 97) % 2000) + 1,
    2
FROM operativo.documento
WHERE (id * 41) % 100 < 30
  AND ((id * 97) % 2000) + 1 <> id_uploader
ON CONFLICT (id_documento, id_usuario) DO NOTHING;

-- Co-autor 3 para ~10% de los documentos
INSERT INTO operativo.documento_autor (id_documento, id_usuario, orden)
SELECT
    id,
    ((id * 131) % 2000) + 1,
    3
FROM operativo.documento
WHERE (id * 71) % 100 < 10
  AND ((id * 131) % 2000) + 1 <> id_uploader
  AND ((id * 131) % 2000) + 1 <> ((id * 97) % 2000) + 1
ON CONFLICT (id_documento, id_usuario) DO NOTHING;

-- ---------- favoritos (~4000) ----------
INSERT INTO operativo.favorito (id_usuario, id_documento, created_at)
SELECT
    (floor(power(random(), 2) * 1999))::int + 1,
    (floor(power(random(), 2) * 4997))::int + 4,
    '2024-01-01'::timestamptz + (random() * 879)::int * INTERVAL '1 day' + (random() * 24)::int * INTERVAL '1 hour'
FROM generate_series(1, 4000) i
ON CONFLICT (id_usuario, id_documento) DO NOTHING;

-- ---------- evento_visualizacion (30000) ----------
INSERT INTO operativo.evento_visualizacion (id, id_usuario, id_documento, created_at)
SELECT
    i,
    CASE WHEN random() < 0.10 THEN NULL -- 10% invitados anonimos
         ELSE (floor(power(random(), 2) * 1999))::int + 1
    END,
    (floor(power(random(), 2) * 4997))::int + 4,
    '2024-01-01'::timestamptz + (random() * 879)::int * INTERVAL '1 day' + (random() * 24)::int * INTERVAL '1 hour'
FROM generate_series(1, 30000) i;

SELECT setval('operativo.evento_visualizacion_id_seq', (SELECT max(id) FROM operativo.evento_visualizacion));

-- ---------- tendencia showcase para la demo de prediccion (docs 1, 2, 3) ----------
-- Inyecta visualizaciones con una serie MENSUAL marcada para que, tras el ETL,
-- dwh.predecir_interacciones_documento muestre una tendencia clara por documento:
--   doc 1 -> creciente (6..41), doc 2 -> decreciente (41..6), doc 3 -> estable (22).
-- Una fila por evento (1 visualizacion) el dia 15 de cada mes; id por default (BIGSERIAL,
-- ya seteado por el setval de arriba). El ETL las agrega por (dia, doc) y la funcion de
-- prediccion arma la serie mensual y ajusta la recta. Sin esto, las visualizaciones del
-- seed son uniformes en el tiempo y la regresion da pendiente ~ 0.
INSERT INTO operativo.evento_visualizacion (id_usuario, id_documento, created_at)
SELECT
    ((doc.id_documento * 53 + n) % 2000) + 1,
    doc.id_documento,
    (g.gm + INTERVAL '14 days') + (n % 24) * INTERVAL '1 hour'
FROM generate_series('2024-01-01'::date, '2026-05-01'::date, '1 month') WITH ORDINALITY AS g(gm, ord)
CROSS JOIN (VALUES
    (1,  6,  1),    -- creciente
    (2, 41, -1),    -- decreciente
    (3, 22,  0)     -- estable
) AS doc(id_documento, base, slope)
CROSS JOIN LATERAL generate_series(1, GREATEST(doc.base + doc.slope * (g.ord - 1), 1)) AS n;

-- ---------- descarga (10000) ----------
INSERT INTO operativo.descarga (id, id_usuario, id_documento, created_at)
SELECT
    i,
    CASE WHEN random() < 0.10 THEN NULL -- 10% invitados anonimos
         ELSE (floor(power(random(), 2) * 1999))::int + 1
    END,
    (floor(power(random(), 2) * 4997))::int + 4,
    '2024-01-01'::timestamptz + (random() * 879)::int * INTERVAL '1 day' + (random() * 24)::int * INTERVAL '1 hour'
FROM generate_series(1, 10000) i;

SELECT setval('operativo.descarga_id_seq', (SELECT max(id) FROM operativo.descarga));

-- ---------- comentario (4000: 3000 raiz + 1000 respuestas) ----------
-- Raiz (id 1..3000)
WITH raw_com AS (
    SELECT
        i,
        '2024-01-01'::timestamptz + (random() * 870)::int * INTERVAL '1 day' AS c_at,
        random() < 0.02 AS is_hidden
    FROM generate_series(1, 3000) i
)
INSERT INTO operativo.comentario (id, id_usuario, id_documento, id_comentario_padre, texto, esta_oculto, fecha_oculto, created_at, updated_at)
SELECT
    i,
    (floor(power(random(), 2) * 1999))::int + 1,
    (floor(power(random(), 2) * 4997))::int + 4,
    NULL,
    'Comentario de prueba numero ' || i || ' sobre este valioso documento. Interesante punto de vista.',
    is_hidden,
    CASE WHEN is_hidden THEN c_at + (random() * 5)::int * INTERVAL '1 day' ELSE NULL END,
    c_at,
    c_at
FROM raw_com;

-- Respuestas (id 3001..4000)
WITH raw_reply AS (
    SELECT
        i,
        '2024-01-01'::timestamptz + (random() * 870)::int * INTERVAL '1 day' AS c_at
    FROM generate_series(1, 1000) i
)
INSERT INTO operativo.comentario (id, id_usuario, id_documento, id_comentario_padre, texto, esta_oculto, fecha_oculto, created_at, updated_at)
SELECT
    3000 + i,
    (floor(power(random(), 2) * 1999))::int + 1,
    (floor(power(random(), 2) * 4997))::int + 4,
    (floor(random() * 3000))::int + 1, -- referenciar un comentario raiz 1..3000
    'Respuesta de prueba numero ' || (3000 + i) || ' al comentario. Coincido con tu apreciacion del tema.',
    FALSE,
    NULL,
    c_at,
    c_at
FROM raw_reply;

SELECT setval('operativo.comentario_id_seq', (SELECT max(id) FROM operativo.comentario));

-- ---------- busqueda (50000) ----------
INSERT INTO operativo.busqueda (
    id, id_usuario, query_texto,
    id_escuela_filtro, id_carrera_filtro, id_materia_filtro, id_tipo_documento_filtro,
    fecha_desde_filtro, fecha_hasta_filtro,
    cant_resultados, hizo_click, session_hash, created_at
)
SELECT
    i,
    CASE WHEN (i * 31) % 100 < 10 THEN NULL -- 10% invitados anonimos
         ELSE ((i * 73) % 2000) + 1
    END,
    (ARRAY['redes neuronales','cambio climatico','foucault biopolitica',
           'algoritmos geneticos','derecho constitucional','biotecnologia vegetal',
           'historia colonial','algebra lineal','ecologia urbana','python pandas',
           'crispr edicion genetica','filosofia analitica'])[((i * 7) % 12) + 1],
    -- Filtros aplicados aleatoriamente
    CASE WHEN random() < 0.10 THEN (floor(random() * 5))::int + 1 END,
    CASE WHEN random() < 0.10 THEN (floor(random() * 30))::int + 1 END,
    CASE WHEN random() < 0.15 THEN (floor(random() * 300))::int + 1 END,
    CASE WHEN random() < 0.05  THEN (floor(random() * 8))::int + 1 END,
    NULL,
    NULL,
    (floor(random() * 50))::int,
    random() < 0.65,
    md5('session' || (floor(random() * 10000))::int),
    '2024-01-01'::timestamptz + (random() * 879)::int * INTERVAL '1 day' + (random() * 24)::int * INTERVAL '1 hour'
FROM generate_series(1, 50000) i;

SELECT setval('operativo.busqueda_id_seq', (SELECT max(id) FROM operativo.busqueda));

-- ---------- ANALYZE ----------
ANALYZE operativo.escuela;
ANALYZE operativo.carrera;
ANALYZE operativo.materia;
ANALYZE operativo.usuario;
ANALYZE operativo.tipo_documento;
ANALYZE operativo.documento;
ANALYZE operativo.documento_autor;
ANALYZE operativo.favorito;
ANALYZE operativo.evento_visualizacion;
ANALYZE operativo.descarga;
ANALYZE operativo.comentario;
ANALYZE operativo.busqueda;
