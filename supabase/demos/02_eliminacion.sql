-- =============================================================
-- DEMO 02 - Eliminacion
-- =============================================================
-- Solo se borran datos del DWH por moderacion, pedido del autor
-- (derecho al olvido) o politicas de retencion. Como las
-- dimensiones SCD2 usan clave subrogada, las eliminaciones
-- puntuales se resuelven contra id_documento_sk o via lookup
-- desde la natural key (id_documento_bk).
-- =============================================================

BEGIN;

-- Antes
SELECT count(*) AS publicaciones_antes
FROM   dwh.fact_publicacion fp
JOIN   dwh.dim_documento    d  ON fp.id_documento_sk = d.id_documento_sk
WHERE  d.id_documento_bk = 4521;

-- Borrar las publicaciones del documento (resuelve desde la clave natural)
DELETE FROM dwh.fact_publicacion
WHERE id_documento_sk IN (
    SELECT id_documento_sk
    FROM   dwh.dim_documento
    WHERE  id_documento_bk = 4521
);

-- Despues
SELECT count(*) AS publicaciones_despues
FROM   dwh.fact_publicacion fp
JOIN   dwh.dim_documento    d  ON fp.id_documento_sk = d.id_documento_sk
WHERE  d.id_documento_bk = 4521;

ROLLBACK;
