-- =============================================================
-- DEMO 04 - Actualizacion
-- =============================================================
-- El modelo usa SCD Tipo 1 en todas las dimensiones: sobreescribe
-- el valor en su lugar, sin guardar historial. Es una decision de
-- diseño: el dashboard solo necesita el estado actual, asi que se
-- descarto el versionado (SCD2) para mantener el modelo simple.
--
-- ETL (Actualizacion):
--   El ETL detecta cambios en el operativo comparando updated_at
--   contra el watermark y aplica el UPDATE en la misma transaccion
--   incremental. Al ser todo SCD1, no abre ni cierra versiones:
--   pisa los campos cambiados de la fila vigente.
-- =============================================================

BEGIN;

-- -------- SCD1: un usuario cambia de carrera --------
-- dim_usuario tiene carrera/escuela desnormalizadas: hay que pisar
-- los tres campos en forma consistente. Los nombres de la nueva
-- carrera se resuelven desde dim_materia (que ya los tiene).
SELECT id_usuario, id_carrera, nombre_carrera, nombre_escuela
FROM   dwh.dim_usuario
WHERE  id_usuario = 1500;

UPDATE dwh.dim_usuario u
   SET id_carrera     = c.id_carrera,
       nombre_carrera = c.nombre_carrera,
       nombre_escuela = c.nombre_escuela
FROM  (SELECT DISTINCT id_carrera, nombre_carrera, nombre_escuela
         FROM dwh.dim_materia
        WHERE id_carrera = 7) c
WHERE  u.id_usuario = 1500;

SELECT id_usuario, id_carrera, nombre_carrera, nombre_escuela
FROM   dwh.dim_usuario
WHERE  id_usuario = 1500;

-- -------- SCD1: un documento cambia de visibilidad --------
SELECT id_documento, visibilidad AS visibilidad_antes
FROM   dwh.dim_documento
WHERE  id_documento = 1011;

UPDATE dwh.dim_documento
   SET visibilidad = 'privado'
 WHERE id_documento = 1011;

SELECT id_documento, visibilidad AS visibilidad_despues
FROM   dwh.dim_documento
WHERE  id_documento = 1011;

ROLLBACK;
