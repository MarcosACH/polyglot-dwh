-- =============================================================
-- DEMO 04 - Actualizacion
-- =============================================================
-- Politicas segun importe o no preservar el historial:
--   * SCD Tipo 1: pisa el valor sin historial. Aplica a campos
--                 cosmeticos o no analiticos (nombres de
--                 dimension, visibilidad, etc.).
--   * SCD Tipo 2: cierra la fila vigente (valid_to=hoy,
--                 is_current=FALSE) e inserta una version nueva
--                 con id_subrogado fresco. Los hechos previos
--                 siguen apuntando al subrogado anterior, los
--                 nuevos al actual.
--
-- ETL (Actualizacion):
--   El ETL detecta cambios en el operativo comparando
--   updated_at contra el watermark. Decide la politica (SCD1 o
--   SCD2) segun el campo modificado y aplica la operacion en la
--   misma transaccion incremental.
-- =============================================================

BEGIN;

-- -------- SCD1: renombrar una carrera (pisar) --------
SELECT id_carrera, nombre AS nombre_antes
FROM   dwh.dim_carrera
WHERE  id_carrera = 27;

UPDATE dwh.dim_carrera
   SET nombre = 'Licenciatura en Ciencia de Datos'
 WHERE id_carrera = 27;

SELECT id_carrera, nombre AS nombre_despues
FROM   dwh.dim_carrera
WHERE  id_carrera = 27;

-- -------- SCD2: usuario cambia de carrera --------
-- Estado inicial
SELECT id_usuario_sk, id_usuario_bk, id_carrera, is_current, valid_from, valid_to
FROM   dwh.dim_usuario
WHERE  id_usuario_bk = 1500
ORDER  BY valid_from;

-- 1) cerrar la version vigente
UPDATE dwh.dim_usuario
   SET valid_to = CURRENT_DATE, is_current = FALSE
 WHERE id_usuario_bk = 1500 AND is_current;

-- 2) insertar la version nueva con sk fresco y nueva carrera
INSERT INTO dwh.dim_usuario
    (id_usuario_sk, id_usuario_bk, id_rol, id_carrera, nombre, email_hash,
     valid_from, valid_to, is_current)
SELECT
    (SELECT max(id_usuario_sk) + 1 FROM dwh.dim_usuario),
    u.id_usuario_bk,
    u.id_rol,
    7,                                 -- nueva carrera
    u.nombre,
    u.email_hash,
    CURRENT_DATE,
    NULL,
    TRUE
FROM   dwh.dim_usuario u
WHERE  u.id_usuario_bk = 1500
  AND  u.valid_to      = CURRENT_DATE;

-- Estado final: dos versiones, la nueva is_current=TRUE
SELECT id_usuario_sk, id_usuario_bk, id_carrera, is_current, valid_from, valid_to
FROM   dwh.dim_usuario
WHERE  id_usuario_bk = 1500
ORDER  BY valid_from;

ROLLBACK;
