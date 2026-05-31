-- =============================================================
-- BUSCASAM DWH - Datos sinteticos (reproducible)
-- Modelo agregado (estrella desnormalizada, Kimball SCD1).
-- =============================================================
-- Volumenes aproximados:
--   5 escuelas, 30 carreras, 300 materias (aplanadas en dim_materia)
--   1096 dias (2024-01-01 a 2026-12-31)
--   2000 usuarios (SCD1)
--   5000 documentos (SCD1, 3% soft-deleted)
--   3 tipos de interaccion: publicacion | visualizacion | favorito_agregar
--   fact_interaccion_documento: 5000 publicaciones + ~30000 visualizaciones
--                               + ~6000 favoritos, agregados por (dia, doc, tipo)
--   fact_interaccion_autor:     agregado por (dia, autor, tipo); autoria principal
--                               + co-autores (~30% segundo, ~10% tercero)
--   fact_query_popularity:      snapshot diario de 12 queries (score + ranking)
--
-- Escuela y carrera ya no son tablas (jerarquia aplanada): se usan tablas
-- TEMP de lookup solo para resolver los nombres desnormalizados.
-- doc->autor tambien se resuelve en una tabla TEMP (reemplaza al viejo bridge).
--
-- Se asume schema dwh ya creado (migrations/0001_dwh_schema.sql).
-- Reproducible: setseed fija la semilla del random() de la sesion.
-- =============================================================

SELECT setseed(0.42);

-- ---------- lookup TEMP: escuela (5) ----------
CREATE TEMP TABLE _escuela AS
SELECT * FROM (VALUES
    (1, 'Escuela de Ciencia y Tecnologia'),
    (2, 'Escuela de Humanidades'),
    (3, 'Escuela de Economia y Negocios'),
    (4, 'Escuela de Politica y Gobierno'),
    (5, 'Escuela de Bio y Nanotecnologias')
) e(id_escuela, nombre);

-- ---------- lookup TEMP: carrera (30) ----------
CREATE TEMP TABLE _carrera AS
SELECT i AS id_carrera, ((i - 1) % 5) + 1 AS id_escuela, 'Carrera ' || i AS nombre
FROM generate_series(1, 30) AS g(i);

-- Nombres realistas para las primeras 10
UPDATE _carrera SET nombre = 'Ingenieria en Informatica'  WHERE id_carrera = 1;
UPDATE _carrera SET nombre = 'Licenciatura en Letras'     WHERE id_carrera = 2;
UPDATE _carrera SET nombre = 'Contador Publico'           WHERE id_carrera = 3;
UPDATE _carrera SET nombre = 'Ciencia Politica'           WHERE id_carrera = 4;
UPDATE _carrera SET nombre = 'Biotecnologia'              WHERE id_carrera = 5;
UPDATE _carrera SET nombre = 'Ingenieria Electronica'     WHERE id_carrera = 6;
UPDATE _carrera SET nombre = 'Licenciatura en Historia'   WHERE id_carrera = 7;
UPDATE _carrera SET nombre = 'Administracion de Empresas' WHERE id_carrera = 8;
UPDATE _carrera SET nombre = 'Relaciones Internacionales' WHERE id_carrera = 9;
UPDATE _carrera SET nombre = 'Bioinformatica'             WHERE id_carrera = 10;

-- ---------- dim_materia (300, jerarquia aplanada) ----------
INSERT INTO dwh.dim_materia
    (id_materia, nombre_materia, id_carrera, nombre_carrera, id_escuela, nombre_escuela)
SELECT
    m.i,
    'Materia ' || m.i,
    c.id_carrera,
    c.nombre,
    e.id_escuela,
    e.nombre
FROM generate_series(1, 300) AS m(i)
JOIN _carrera c ON c.id_carrera = ((m.i - 1) % 30) + 1
JOIN _escuela e ON e.id_escuela = c.id_escuela;

-- ---------- dim_tiempo (2024-01-01 a 2026-12-31) ----------
INSERT INTO dwh.dim_tiempo (fecha, dia, mes, cuatrimestre, anio)
SELECT
    d::date,
    EXTRACT(DAY   FROM d)::smallint,
    EXTRACT(MONTH FROM d)::smallint,
    CASE WHEN EXTRACT(MONTH FROM d) <= 7 THEN 1 ELSE 2 END::smallint,
    EXTRACT(YEAR FROM d)::smallint
FROM generate_series('2024-01-01'::date, '2026-12-31'::date, '1 day'::interval) d;

-- ---------- dim_usuario (SCD1, 2000) ----------
-- carrera/escuela desnormalizadas. user->carrera = ((i*31)%30)+1
INSERT INTO dwh.dim_usuario
    (id_usuario, id_carrera, nombre_carrera, nombre_escuela, nombre)
SELECT
    u.i,
    c.id_carrera,
    c.nombre,
    e.nombre,
    'Usuario ' || u.i
FROM generate_series(1, 2000) AS u(i)
JOIN _carrera c ON c.id_carrera = (floor(power(random(), 1.5) * 30))::int + 1
JOIN _escuela e ON e.id_escuela = c.id_escuela;

-- ---------- dim_tipo_documento (8) ----------
INSERT INTO dwh.dim_tipo_documento (id_tipo, nombre) VALUES
    (1, 'tesis'),
    (2, 'paper'),
    (3, 'trabajo_practico'),
    (4, 'proyecto_investigacion'),
    (5, 'monografia'),
    (6, 'ponencia'),
    (7, 'apunte'),
    (8, 'informe_catedra');

-- ---------- dim_documento (SCD1, 5000) ----------
WITH raw_doc AS (
    SELECT
        i,
        '2024-01-01'::date + (random() * 879)::int AS f_alta,
        random() AS r_tipo,
        random() AS r_mat,
        random() AS r_vis,
        random() AS r_del
    FROM generate_series(1, 5000) AS g(i)
)
INSERT INTO dwh.dim_documento
    (id_documento, id_tipo, id_materia, titulo, fecha_alta, visibilidad, is_deleted, deleted_at)
SELECT
    i,
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
    'Documento ' || i || ': estudio sobre ' ||
        (ARRAY['IA aplicada','cambio climatico','politica publica','genomica',
               'historia argentina','algebra lineal','sociologia urbana','redes neuronales',
               'biotecnologia','filosofia','ecologia','derecho ambiental'])[((i * 7) % 12) + 1],
    f_alta,
    CASE WHEN r_vis < 0.70 THEN 'publico' WHEN r_vis < 0.90 THEN 'interno' ELSE 'privado' END,
    r_del < 0.03,
    CASE WHEN r_del < 0.03 THEN f_alta + (random() * 80)::int ELSE NULL END
FROM raw_doc;

-- ---------- dim_tipo_interaccion ----------
INSERT INTO dwh.dim_tipo_interaccion (id_tipo_interaccion, nombre) VALUES
    (1, 'publicacion'),
    (2, 'visualizacion'),
    (3, 'favorito_agregar');

-- ---------- fact_interaccion_documento ----------
-- Granularidad: (fecha, documento, tipo). cant_interacciones = eventos del dia.

-- publicacion (tipo 1): una por documento, en su fecha_alta
INSERT INTO dwh.fact_interaccion_documento
    (fecha, id_documento, id_tipo_interaccion, cant_interacciones)
SELECT d.fecha_alta, d.id_documento, 1, 1
FROM dwh.dim_documento d;

-- visualizacion (tipo 2): 30000 eventos agregados por (dia, doc)
INSERT INTO dwh.fact_interaccion_documento
    (fecha, id_documento, id_tipo_interaccion, cant_interacciones)
SELECT fecha, id_documento, 2, COUNT(*)
FROM (
    SELECT
        '2024-01-01'::date + (random() * 880)::int AS fecha,
        (floor(power(random(), 2) * 4997))::int + 4 AS id_documento
    FROM generate_series(1, 30000)
) v
GROUP BY fecha, id_documento;

-- favorito_agregar (tipo 3): 8000 favoritos, 75% agregar -> ~6000, agregados por (dia, doc)
INSERT INTO dwh.fact_interaccion_documento
    (fecha, id_documento, id_tipo_interaccion, cant_interacciones)
SELECT fecha, id_documento, 3, COUNT(*)
FROM (
    SELECT
        '2024-01-01'::date + (random() * 880)::int AS fecha,
        (floor(power(random(), 2) * 4997))::int + 4 AS id_documento
    FROM generate_series(1, 8000)
    WHERE random() < 0.75
) f
GROUP BY fecha, id_documento;

-- ---------- tendencia showcase para la demo de prediccion ----------
-- 3 documentos con serie MENSUAL marcada (no aleatoria) para que la
-- regresion lineal por documento muestre una tendencia clara:
--   doc 1 -> creciente (6..41), doc 2 -> decreciente (41..6), doc 3 -> estable (22).
-- Una fila de visualizaciones (tipo 2) por mes, el dia 15. ON CONFLICT
-- por si coincide con alguna visualizacion aleatoria ya cargada.
INSERT INTO dwh.fact_interaccion_documento
    (fecha, id_documento, id_tipo_interaccion, cant_interacciones)
SELECT
    (g.gm + INTERVAL '14 days')::date,
    doc.id_documento,
    2,
    doc.base + doc.slope * (g.ord - 1)::int
FROM generate_series('2024-01-01'::date, '2026-05-01'::date, '1 month') WITH ORDINALITY AS g(gm, ord)
CROSS JOIN (VALUES
    (1,  6,  1),    -- creciente
    (2, 41, -1),    -- decreciente
    (3, 22,  0)     -- estable
) AS doc(id_documento, base, slope)
ON CONFLICT (fecha, id_documento, id_tipo_interaccion)
DO UPDATE SET cant_interacciones =
    dwh.fact_interaccion_documento.cant_interacciones + EXCLUDED.cant_interacciones;

-- ---------- doc -> autor (TEMP, reemplaza al viejo bridge) ----------
-- Autor principal + co-autor 2 (~30%) + co-autor 3 (~10%). UNION dedup.
CREATE TEMP TABLE _doc_autor AS
SELECT id_documento, ((id_documento * 53) % 2000) + 1 AS id_usuario
FROM dwh.dim_documento
UNION
SELECT id_documento, ((id_documento * 97) % 2000) + 1
FROM dwh.dim_documento
WHERE (id_documento * 41) % 100 < 30
  AND ((id_documento * 97) % 2000) + 1 <> ((id_documento * 53) % 2000) + 1
UNION
SELECT id_documento, ((id_documento * 131) % 2000) + 1
FROM dwh.dim_documento
WHERE (id_documento * 71) % 100 < 10
  AND ((id_documento * 131) % 2000) + 1 <> ((id_documento * 53) % 2000) + 1
  AND ((id_documento * 131) % 2000) + 1 <> ((id_documento * 97) % 2000) + 1;

-- ---------- fact_interaccion_autor ----------
-- Agrega las interacciones de los documentos de cada autor por (dia, autor, tipo).
INSERT INTO dwh.fact_interaccion_autor
    (fecha, id_usuario, id_tipo_interaccion, cant_interacciones)
SELECT f.fecha, da.id_usuario, f.id_tipo_interaccion, SUM(f.cant_interacciones)
FROM dwh.fact_interaccion_documento f
JOIN _doc_autor da ON da.id_documento = f.id_documento
GROUP BY f.fecha, da.id_usuario, f.id_tipo_interaccion;

-- ---------- fact_query_popularity ----------
-- Snapshot diario de 12 queries. score = base + wobble diario deterministico.
-- ranking = posicion por score dentro del dia.
WITH q(query_texto, base, k) AS (
    VALUES
        ('redes neuronales',        980,  3),
        ('python pandas',           910,  5),
        ('cambio climatico',        870,  7),
        ('crispr edicion genetica', 820, 11),
        ('algoritmos geneticos',    780, 13),
        ('biotecnologia vegetal',   740, 17),
        ('algebra lineal',          700, 19),
        ('derecho constitucional',  660, 23),
        ('ecologia urbana',         620, 29),
        ('foucault biopolitica',    580, 31),
        ('historia colonial',       540, 37),
        ('filosofia analitica',     500, 41)
),
snap AS (
    SELECT
        t.fecha,
        q.query_texto,
        (q.base + ((((t.fecha - DATE '2024-01-01') * q.k) % 81) - 40))::int AS score
    FROM dwh.dim_tiempo t
    CROSS JOIN q
)
INSERT INTO dwh.fact_query_popularity (fecha, query_texto, score, ranking)
SELECT
    fecha,
    query_texto,
    score,
    (ROW_NUMBER() OVER (PARTITION BY fecha ORDER BY score DESC, query_texto))::smallint
FROM snap;

-- ---------- etl_watermark ----------
INSERT INTO dwh.etl_watermark (tabla_origen, ultimo_procesado, ultima_corrida) VALUES
    ('usuario',          '2026-12-31 03:00:00', '2026-12-31 03:15:00'),
    ('materia',          '2026-12-31 03:00:00', '2026-12-31 03:15:00'),
    ('documento',        '2026-12-31 03:00:00', '2026-12-31 03:15:00'),
    ('publicacion',      '2026-12-31 03:00:00', '2026-12-31 03:15:00'),
    ('visualizacion',    '2026-12-31 03:00:00', '2026-12-31 03:15:00'),
    ('favorito',         '2026-12-31 03:00:00', '2026-12-31 03:15:00'),
    ('query_popularity', '2026-12-31 03:00:00', '2026-12-31 03:15:00');

-- ANALYZE para que el planner tenga estadisticas frescas tras la carga.
ANALYZE dwh.dim_materia;
ANALYZE dwh.dim_tiempo;
ANALYZE dwh.dim_usuario;
ANALYZE dwh.dim_tipo_documento;
ANALYZE dwh.dim_documento;
ANALYZE dwh.dim_tipo_interaccion;
ANALYZE dwh.fact_interaccion_documento;
ANALYZE dwh.fact_interaccion_autor;
ANALYZE dwh.fact_query_popularity;
