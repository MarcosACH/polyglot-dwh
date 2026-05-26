-- =============================================================
-- DEMO 03 - Insercion
-- =============================================================
-- Carga del agregado diario del 2026-05-04 sobre el hecho
-- fact_interaccion_documento (tipo 2 = visualizacion,
-- 3 = favorito_agregar).
--
-- Clave del modelo agregado: NO se inserta una fila por evento,
-- sino una fila por (fecha, documento, tipo) con el total del dia
-- en cant_interacciones. El INSERT ... ON CONFLICT DO UPDATE hace
-- el upsert: si la corrida del dia se repite, re-suma sobre la
-- fila existente en vez de duplicar la PK.
--
-- ETL (Insercion):
--   El ETL guarda en dwh.etl_watermark la fecha/hora del ultimo
--   registro procesado por tabla origen. En cada corrida:
--     1. EXTRAE del operativo solo los eventos con
--        created_at > watermark (carga incremental).
--     2. TRANSFORMA: traduce IDs, normaliza, y AGREGA los eventos
--        por (fecha, id_documento, id_tipo_interaccion) sumando la
--        cantidad -> asi N visualizaciones de un doc en un dia
--        colapsan en una sola fila (compresion del modelo).
--     3. CARGA con INSERT ... ON CONFLICT DO UPDATE (upsert
--        idempotente) dentro de una transaccion y actualiza el
--        watermark con la fecha del ultimo registro procesado.
-- =============================================================

BEGIN;

SELECT COALESCE(SUM(cant_interacciones), 0) AS interacciones_antes
FROM   dwh.fact_interaccion_documento
WHERE  fecha = '2026-05-04';

INSERT INTO dwh.fact_interaccion_documento
    (fecha, id_documento, id_tipo_interaccion, cant_interacciones)
VALUES
    ('2026-05-04', 1010, 2, 27),   -- 27 visualizaciones del doc 1010
    ('2026-05-04', 1010, 3,  4),   -- 4 favoritos del doc 1010
    ('2026-05-04',  587, 2,  8)    -- 8 visualizaciones del doc 587
ON CONFLICT (fecha, id_documento, id_tipo_interaccion)
DO UPDATE SET cant_interacciones =
    dwh.fact_interaccion_documento.cant_interacciones + EXCLUDED.cant_interacciones;

SELECT COALESCE(SUM(cant_interacciones), 0) AS interacciones_despues
FROM   dwh.fact_interaccion_documento
WHERE  fecha = '2026-05-04';

ROLLBACK;
