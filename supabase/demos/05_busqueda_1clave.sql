-- =============================================================
-- DEMO 05 - Busqueda por una clave (1 dimension)
-- =============================================================
-- Total de interacciones registradas durante el primer
-- cuatrimestre de 2026. Filtra por una sola dimension (tiempo):
-- PostgreSQL usa idx_fact_interaccion_fecha para leer solo el
-- rango de fechas relevante, sin escanear toda la tabla.
-- =============================================================

SELECT SUM(cant_interacciones) AS total_interacciones
FROM   dwh.fact_interaccion_documento
WHERE  fecha BETWEEN '2026-03-01' AND '2026-07-31';
