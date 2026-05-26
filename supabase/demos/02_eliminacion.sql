-- =============================================================
-- DEMO 02 - Eliminacion
-- =============================================================
-- Solo se borran datos del DWH por moderacion, pedido del autor
-- (derecho al olvido) o politicas de retencion.
--
-- El modelo usa SCD1 con clave natural (id_documento), asi que la
-- baja se resuelve directo por esa clave. Dos mecanismos:
--   1. Baja logica (lo habitual): marcar dim_documento.is_deleted
--      = TRUE + deleted_at. Todos los elementos del dashboard
--      filtran is_deleted = FALSE, asi que el documento desaparece
--      de los reportes pero queda la traza.
--   2. Purga fisica (derecho al olvido): DELETE de los hechos del
--      documento en fact_interaccion_documento.
--
-- ETL (Eliminacion):
--   La baja logica del operativo llega como un cambio mas en la
--   corrida incremental: el ETL detecta is_deleted/deleted_at via
--   updated_at y lo sobreescribe (SCD1). La purga fisica es una
--   operacion puntual fuera del flujo incremental. El agregado por
--   autor (fact_interaccion_autor) se recalcula en la corrida.
-- =============================================================

BEGIN;

-- Antes
SELECT
    (SELECT is_deleted FROM dwh.dim_documento WHERE id_documento = 4521) AS is_deleted_antes,
    (SELECT count(*) FROM dwh.fact_interaccion_documento WHERE id_documento = 4521) AS hechos_antes;

-- 1) Baja logica en la dimension
UPDATE dwh.dim_documento
   SET is_deleted = TRUE,
       deleted_at = CURRENT_DATE
 WHERE id_documento = 4521;

-- 2) Purga fisica de los hechos del documento (derecho al olvido)
DELETE FROM dwh.fact_interaccion_documento
 WHERE id_documento = 4521;

-- Despues
SELECT
    (SELECT is_deleted FROM dwh.dim_documento WHERE id_documento = 4521) AS is_deleted_despues,
    (SELECT count(*) FROM dwh.fact_interaccion_documento WHERE id_documento = 4521) AS hechos_despues;

ROLLBACK;
