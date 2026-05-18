-- =============================================================
-- DEMO 03 - Insercion
-- =============================================================
-- Inserta tres busquedas del 2026-05-04 directamente sobre el
-- hecho fact_busqueda.
--
-- ETL (Insercion):
--   El ETL guarda en dwh.etl_watermark la fecha/hora del ultimo
--   registro procesado por tabla origen. En cada corrida:
--     1. EXTRAE del operativo solo las filas con
--        created_at > watermark (carga incremental).
--     2. TRANSFORMA: traduce IDs, normaliza textos, calcula
--        campos derivados (ej. hizo_click) y resuelve las claves
--        subrogadas vigentes (is_current=TRUE) para las
--        dimensiones SCD2.
--     3. CARGA con INSERT en bloque dentro de una transaccion
--        (si algo falla, ROLLBACK total) y actualiza el
--        watermark con la fecha del ultimo registro insertado.
-- =============================================================

BEGIN;

SELECT count(*) AS busquedas_antes
FROM   dwh.fact_busqueda
WHERE  fecha = '2026-05-04';

INSERT INTO dwh.fact_busqueda
    (fecha, id_usuario_sk, id_materia_filtro,
     query_texto, cant_resultados, hizo_click)
VALUES
    ('2026-05-04', 1010, 45, 'redes neuronales medicina', 27, TRUE),
    ('2026-05-04', 1010, 45, 'deep learning diagnostico', 19, TRUE),
    ('2026-05-04',  587, 78, 'foucault biopolitica',       8, FALSE);

SELECT count(*) AS busquedas_despues
FROM   dwh.fact_busqueda
WHERE  fecha = '2026-05-04';

ROLLBACK;
