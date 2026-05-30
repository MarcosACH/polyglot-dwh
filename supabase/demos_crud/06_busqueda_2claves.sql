-- =============================================================
-- DEMO 06 - Busqueda por dos claves (2 dimensiones)
-- =============================================================
-- Visualizaciones por tipo de documento y por año. Cruza dos
-- dimensiones (tipo_documento + tiempo) sobre el hecho
-- fact_interaccion_documento, filtrando el tipo de interaccion.
-- =============================================================

SELECT
    td.nombre AS tipo_documento,
    t.anio,
    SUM(f.cant_interacciones) AS visualizaciones
FROM   dwh.fact_interaccion_documento f
JOIN   dwh.dim_tipo_interaccion ti ON f.id_tipo_interaccion = ti.id_tipo_interaccion
                                   AND ti.nombre = 'visualizacion'
JOIN   dwh.dim_documento        d  ON f.id_documento = d.id_documento
JOIN   dwh.dim_tipo_documento  td  ON d.id_tipo = td.id_tipo
JOIN   dwh.dim_tiempo           t  ON f.fecha = t.fecha
GROUP  BY td.nombre, t.anio
ORDER  BY td.nombre, t.anio;

-- Variante (heatmap, elemento 1 del dashboard): publicaciones por
-- Escuela y cuatrimestre durante 2026. Antes era un copo de nieve
-- (documento -> materia -> carrera -> escuela); ahora la jerarquia
-- esta aplanada en dim_materia, asi que se resuelve con un solo
-- JOIN a la dimension en vez de recorrer cuatro tablas.
/*
SELECT
    m.nombre_escuela AS escuela,
    t.cuatrimestre,
    SUM(f.cant_interacciones) AS total_publicaciones
FROM   dwh.fact_interaccion_documento f
JOIN   dwh.dim_tipo_interaccion ti ON f.id_tipo_interaccion = ti.id_tipo_interaccion
                                   AND ti.nombre = 'publicacion'
JOIN   dwh.dim_documento d ON f.id_documento = d.id_documento
                          AND d.is_deleted = FALSE
JOIN   dwh.dim_materia   m ON d.id_materia = m.id_materia
JOIN   dwh.dim_tiempo    t ON f.fecha = t.fecha
WHERE  t.anio = 2026
GROUP  BY m.nombre_escuela, t.cuatrimestre
ORDER  BY m.nombre_escuela, t.cuatrimestre;
*/
