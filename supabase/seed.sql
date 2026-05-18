-- =============================================================
-- BUSCASAM DWH - Datos sinteticos (reproducible)
-- =============================================================
-- Volumenes aproximados:
--   5 escuelas, 30 carreras, 300 materias, 1095 dias (3 anios)
--   2001 usuarios (2000 + sentinel) + 50 versiones SCD2
--   5000 documentos + 100 versiones SCD2
--   ~7500 filas en bridge_documento_autor
--   50000 busquedas, 30000 visualizaciones, 5000 publicaciones,
--   10000 descargas, 8000 favoritos, 4000 comentarios
--
-- Se asume schema dwh ya creado (migrations/0001_dwh_schema.sql).
-- Reproducible: setseed fija la semilla del random() de la sesion.
-- =============================================================

SELECT setseed(0.42);

-- ---------- dim_escuela (5) ----------
INSERT INTO dwh.dim_escuela (id_escuela, nombre) VALUES
    (1, 'Escuela de Ciencia y Tecnologia'),
    (2, 'Escuela de Humanidades'),
    (3, 'Escuela de Economia y Negocios'),
    (4, 'Escuela de Politica y Gobierno'),
    (5, 'Escuela de Bio y Nanotecnologias');

-- ---------- dim_carrera (30) ----------
INSERT INTO dwh.dim_carrera (id_carrera, id_escuela, nombre)
SELECT
    i,
    ((i - 1) % 5) + 1,
    'Carrera ' || i
FROM generate_series(1, 30) i;

-- Nombres realistas para las primeras 10
UPDATE dwh.dim_carrera SET nombre = 'Ingenieria en Informatica'  WHERE id_carrera = 1;
UPDATE dwh.dim_carrera SET nombre = 'Licenciatura en Letras'     WHERE id_carrera = 2;
UPDATE dwh.dim_carrera SET nombre = 'Contador Publico'           WHERE id_carrera = 3;
UPDATE dwh.dim_carrera SET nombre = 'Ciencia Politica'           WHERE id_carrera = 4;
UPDATE dwh.dim_carrera SET nombre = 'Biotecnologia'              WHERE id_carrera = 5;
UPDATE dwh.dim_carrera SET nombre = 'Ingenieria Electronica'     WHERE id_carrera = 6;
UPDATE dwh.dim_carrera SET nombre = 'Licenciatura en Historia'   WHERE id_carrera = 7;
UPDATE dwh.dim_carrera SET nombre = 'Administracion de Empresas' WHERE id_carrera = 8;
UPDATE dwh.dim_carrera SET nombre = 'Relaciones Internacionales' WHERE id_carrera = 9;
UPDATE dwh.dim_carrera SET nombre = 'Bioinformatica'             WHERE id_carrera = 10;

-- ---------- dim_materia (300) ----------
INSERT INTO dwh.dim_materia (id_materia, id_carrera, nombre)
SELECT
    i,
    ((i - 1) % 30) + 1,
    'Materia ' || i
FROM generate_series(1, 300) i;

-- ---------- dim_tiempo (2024-01-01 a 2026-12-31) ----------
INSERT INTO dwh.dim_tiempo (fecha, dia, mes, cuatrimestre, anio)
SELECT
    d::date,
    EXTRACT(DAY   FROM d)::smallint,
    EXTRACT(MONTH FROM d)::smallint,
    CASE WHEN EXTRACT(MONTH FROM d) <= 7 THEN 1 ELSE 2 END::smallint,
    EXTRACT(YEAR FROM d)::smallint
FROM generate_series('2024-01-01'::date, '2026-12-31'::date, '1 day'::interval) d;

-- ---------- dim_rol ----------
INSERT INTO dwh.dim_rol (id_rol, nombre) VALUES
    (1, 'estudiante'),
    (2, 'docente'),
    (3, 'invitado');

-- ---------- dim_tipo_documento ----------
INSERT INTO dwh.dim_tipo_documento (id_tipo, nombre) VALUES
    (1, 'tesis'),
    (2, 'paper'),
    (3, 'trabajo_practico'),
    (4, 'proyecto_investigacion'),
    (5, 'monografia'),
    (6, 'ponencia'),
    (7, 'apunte'),
    (8, 'informe_catedra');

-- ---------- dim_usuario ----------
-- Sentinel para busquedas de invitados anonimos
INSERT INTO dwh.dim_usuario
    (id_usuario_sk, id_usuario_bk, id_rol, id_carrera, nombre, email_hash,
     valid_from, valid_to, is_current)
VALUES
    (0, 0, 3, NULL, 'Invitado Anonimo', NULL, '2024-01-01', NULL, TRUE);

-- 2000 usuarios reales (sk = bk en la carga inicial; 85% estudiantes, 15% docentes)
INSERT INTO dwh.dim_usuario
    (id_usuario_sk, id_usuario_bk, id_rol, id_carrera, nombre, email_hash,
     valid_from, valid_to, is_current)
SELECT
    i,
    i,
    CASE WHEN (i * 7919) % 100 < 85 THEN 1 ELSE 2 END,
    ((i * 31) % 30) + 1,
    'Usuario ' || i,
    md5('user' || i),
    '2024-01-01'::date + ((i * 13) % 700),
    NULL,
    TRUE
FROM generate_series(1, 2000) i;

-- SCD2: 50 usuarios cambian de rol/carrera el 2025-06-01
UPDATE dwh.dim_usuario
   SET valid_to = '2025-06-01', is_current = FALSE
 WHERE id_usuario_sk BETWEEN 1 AND 50;

INSERT INTO dwh.dim_usuario
    (id_usuario_sk, id_usuario_bk, id_rol, id_carrera, nombre, email_hash,
     valid_from, valid_to, is_current)
SELECT
    2000 + i,
    i,
    2,                              -- promocion a docente
    ((i * 17) % 30) + 1,            -- nueva carrera
    'Usuario ' || i,
    md5('user' || i),
    '2025-06-01'::date,
    NULL,
    TRUE
FROM generate_series(1, 50) i;

-- ---------- dim_documento ----------
-- 5000 documentos originales (sk = bk en carga inicial)
INSERT INTO dwh.dim_documento
    (id_documento_sk, id_documento_bk, id_tipo, id_materia, titulo, fecha_alta,
     visibilidad, is_deleted, deleted_at, valid_from, valid_to, is_current)
SELECT
    i,
    i,
    ((i * 11) % 8) + 1,
    ((i * 23) % 300) + 1,
    'Documento ' || i || ': estudio sobre ' ||
        (ARRAY['IA aplicada','cambio climatico','politica publica','genomica',
               'historia argentina','algebra lineal','sociologia urbana','redes neuronales',
               'biotecnologia','filosofia','ecologia','derecho ambiental'])[((i * 7) % 12) + 1],
    '2024-01-01'::date + ((i * 17) % 900),
    (ARRAY['publico','interno','privado'])[((i * 3) % 3) + 1],
    -- 3% soft-deleted
    (i * 41) % 100 < 3,
    CASE WHEN (i * 41) % 100 < 3
         THEN '2024-01-01'::date + ((i * 17) % 900) + ((i * 19) % 200)
         ELSE NULL END,
    '2024-01-01'::date + ((i * 17) % 900),
    NULL,
    TRUE
FROM generate_series(1, 5000) i;

-- SCD2: 100 documentos cambian de materia el 2025-09-01
UPDATE dwh.dim_documento
   SET valid_to = '2025-09-01', is_current = FALSE
 WHERE id_documento_sk BETWEEN 1 AND 100;

INSERT INTO dwh.dim_documento
    (id_documento_sk, id_documento_bk, id_tipo, id_materia, titulo, fecha_alta,
     visibilidad, is_deleted, deleted_at, valid_from, valid_to, is_current)
SELECT
    5000 + i,
    i,
    ((i * 11) % 8) + 1,
    ((i * 29) % 300) + 1,           -- nueva materia
    'Documento ' || i || ': estudio sobre ' ||
        (ARRAY['IA aplicada','cambio climatico','politica publica','genomica',
               'historia argentina','algebra lineal','sociologia urbana','redes neuronales',
               'biotecnologia','filosofia','ecologia','derecho ambiental'])[((i * 7) % 12) + 1],
    '2024-01-01'::date + ((i * 17) % 900),
    (ARRAY['publico','interno','privado'])[((i * 3) % 3) + 1],
    FALSE,
    NULL,
    '2025-09-01'::date,
    NULL,
    TRUE
FROM generate_series(1, 100) i;

-- ---------- bridge_documento_autor ----------
-- Autor principal de cada surrogado (current + cerrado)
INSERT INTO dwh.bridge_documento_autor (id_documento_sk, id_usuario_sk, orden, peso)
SELECT
    d.id_documento_sk,
    ((d.id_documento_bk * 53) % 2000) + 1,
    1,
    1.0                              -- peso temporal, se recalcula al final
FROM dwh.dim_documento d;

-- Co-autor 2 para ~30% de los documentos
INSERT INTO dwh.bridge_documento_autor (id_documento_sk, id_usuario_sk, orden, peso)
SELECT
    d.id_documento_sk,
    ((d.id_documento_bk * 97) % 2000) + 1,
    2,
    1.0
FROM dwh.dim_documento d
WHERE (d.id_documento_bk * 41) % 100 < 30
  AND ((d.id_documento_bk * 97) % 2000) + 1 <> ((d.id_documento_bk * 53) % 2000) + 1
ON CONFLICT DO NOTHING;

-- Co-autor 3 para ~10% de los documentos
INSERT INTO dwh.bridge_documento_autor (id_documento_sk, id_usuario_sk, orden, peso)
SELECT
    d.id_documento_sk,
    ((d.id_documento_bk * 131) % 2000) + 1,
    3,
    1.0
FROM dwh.dim_documento d
WHERE (d.id_documento_bk * 71) % 100 < 10
  AND ((d.id_documento_bk * 131) % 2000) + 1 <> ((d.id_documento_bk * 53) % 2000) + 1
  AND ((d.id_documento_bk * 131) % 2000) + 1 <> ((d.id_documento_bk * 97) % 2000) + 1
ON CONFLICT DO NOTHING;

-- Recalcular peso = 1/N
UPDATE dwh.bridge_documento_autor b
   SET peso = ROUND(1.0 / c.cnt, 4)
  FROM (SELECT id_documento_sk, count(*) AS cnt
          FROM dwh.bridge_documento_autor
         GROUP BY id_documento_sk) c
 WHERE b.id_documento_sk = c.id_documento_sk;

-- ---------- fact_busqueda (50000) ----------
-- 10% invitados (sk=0), filtros aplicados solo en algunos niveles a la vez
INSERT INTO dwh.fact_busqueda
    (fecha, id_usuario_sk, id_escuela_filtro, id_carrera_filtro, id_materia_filtro,
     id_tipo_documento_filtro, fecha_desde_filtro, fecha_hasta_filtro,
     query_texto, cant_resultados, hizo_click, session_hash)
SELECT
    '2024-01-01'::date + (random() * 1095)::int,
    CASE WHEN random() < 0.10 THEN 0
         ELSE (random() * 1999)::int + 1
    END,
    CASE WHEN random() < 0.10 THEN (random() * 4)::int + 1   END,
    CASE WHEN random() < 0.10 THEN (random() * 29)::int + 1  END,
    CASE WHEN random() < 0.15 THEN (random() * 299)::int + 1 END,
    CASE WHEN random() < 0.05 THEN (random() * 7)::int + 1   END,
    NULL,
    NULL,
    (ARRAY['redes neuronales','cambio climatico','foucault biopolitica',
           'algoritmos geneticos','derecho constitucional','biotecnologia vegetal',
           'historia colonial','algebra lineal','ecologia urbana','python pandas',
           'crispr edicion genetica','filosofia analitica'])[((random() * 11)::int) + 1],
    (random() * 50)::int,
    random() < 0.65,
    md5('session' || (random() * 10000)::int)
FROM generate_series(1, 50000) i;

-- ---------- fact_visualizacion (30000) ----------
INSERT INTO dwh.fact_visualizacion (fecha, id_usuario_sk, id_documento_sk)
SELECT
    '2024-01-01'::date + (random() * 1095)::int,
    (random() * 2000)::int,              -- 0..2000 incluye sentinel
    (random() * 4999)::int + 1           -- 1..5000 surrogados originales
FROM generate_series(1, 30000) i;

-- ---------- fact_publicacion (5000) ----------
-- Una publicacion por documento original; autor principal del bridge.
INSERT INTO dwh.fact_publicacion (fecha, id_usuario_sk, id_documento_sk)
SELECT
    d.fecha_alta,
    ((d.id_documento_bk * 53) % 2000) + 1,
    d.id_documento_sk
FROM dwh.dim_documento d
WHERE d.id_documento_sk <= 5000;          -- solo surrogados originales

-- ---------- fact_descarga (10000) ----------
INSERT INTO dwh.fact_descarga (fecha, id_usuario_sk, id_documento_sk)
SELECT
    '2024-01-01'::date + (random() * 1095)::int,
    (random() * 1999)::int + 1,           -- descargas requieren login: 1..2000
    (random() * 4999)::int + 1
FROM generate_series(1, 10000) i;

-- ---------- fact_favorito (8000) ----------
-- 75% agregar / 25% quitar (transaccional)
INSERT INTO dwh.fact_favorito (fecha, id_usuario_sk, id_documento_sk, accion)
SELECT
    '2024-01-01'::date + (random() * 1095)::int,
    (random() * 1999)::int + 1,           -- favoritos requieren login
    (random() * 4999)::int + 1,
    CASE WHEN random() < 0.75 THEN 'agregar' ELSE 'quitar' END
FROM generate_series(1, 8000) i;

-- ---------- fact_comentario ----------
-- 3000 comentarios raiz + 1000 respuestas (threading 1 nivel)
-- Invitados NO comentan (spec). 2% de los raiz quedan ocultos por moderacion.
INSERT INTO dwh.fact_comentario
    (id_comentario, fecha, id_usuario_sk, id_documento_sk, id_comentario_padre,
     esta_oculto, fecha_oculto)
SELECT
    i,
    '2024-01-01'::date + ((i * 271) % 1095),
    ((i * 47) % 2000) + 1,
    ((i * 89) % 5000) + 1,
    NULL,
    (i * 113) % 100 < 2,
    CASE WHEN (i * 113) % 100 < 2
         THEN '2024-01-01'::date + ((i * 271) % 1095) + 5
         ELSE NULL END
FROM generate_series(1, 3000) i;

INSERT INTO dwh.fact_comentario
    (id_comentario, fecha, id_usuario_sk, id_documento_sk, id_comentario_padre,
     esta_oculto, fecha_oculto)
SELECT
    3000 + i,
    '2024-01-01'::date + ((i * 311) % 1095),
    ((i * 59) % 2000) + 1,
    ((i * 89) % 5000) + 1,
    ((i * 17) % 3000) + 1,                -- padre 1..3000
    FALSE,
    NULL
FROM generate_series(1, 1000) i;

-- ---------- etl_watermark ----------
INSERT INTO dwh.etl_watermark (tabla_origen, ultimo_procesado, ultima_corrida) VALUES
    ('busqueda',      '2026-12-31 03:00:00', '2026-12-31 03:15:00'),
    ('visualizacion', '2026-12-31 03:00:00', '2026-12-31 03:15:00'),
    ('publicacion',   '2026-12-31 03:00:00', '2026-12-31 03:15:00'),
    ('descarga',      '2026-12-31 03:00:00', '2026-12-31 03:15:00'),
    ('favorito',      '2026-12-31 03:00:00', '2026-12-31 03:15:00'),
    ('comentario',    '2026-12-31 03:00:00', '2026-12-31 03:15:00'),
    ('usuario',       '2026-12-31 03:00:00', '2026-12-31 03:15:00'),
    ('documento',     '2026-12-31 03:00:00', '2026-12-31 03:15:00');

-- ANALYZE para que el planner tenga estadisticas frescas tras la carga.
ANALYZE dwh.dim_escuela;
ANALYZE dwh.dim_carrera;
ANALYZE dwh.dim_materia;
ANALYZE dwh.dim_tiempo;
ANALYZE dwh.dim_rol;
ANALYZE dwh.dim_usuario;
ANALYZE dwh.dim_tipo_documento;
ANALYZE dwh.dim_documento;
ANALYZE dwh.bridge_documento_autor;
ANALYZE dwh.fact_busqueda;
ANALYZE dwh.fact_visualizacion;
ANALYZE dwh.fact_publicacion;
ANALYZE dwh.fact_descarga;
ANALYZE dwh.fact_favorito;
ANALYZE dwh.fact_comentario;
