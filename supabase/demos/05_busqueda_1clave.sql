-- =============================================================
-- DEMO 05 - Busqueda por una clave (1 dimension)
-- =============================================================
-- Cuantas busquedas hubo durante el primer cuatrimestre de 2026.
-- PostgreSQL usa idx_fact_busqueda_fecha para leer solo el
-- rango de fechas relevante, sin escanear toda la tabla.
-- =============================================================

SELECT count(*) AS total_busquedas
FROM   dwh.fact_busqueda
WHERE  fecha BETWEEN '2026-03-01' AND '2026-07-31';
