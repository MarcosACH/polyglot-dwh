-- =============================================================
-- DEMO 06 - Busqueda por dos claves (2 dimensiones)
-- =============================================================
-- Cantidad de busquedas por tipo de documento filtrado y por
-- año. Cruza dos dimensiones (tipo_documento + tiempo) sobre el
-- hecho fact_busqueda usando sus FK directas.
-- =============================================================

SELECT
    td.nombre AS tipo_filtrado,
    t.anio,
    count(*)  AS busquedas
FROM   dwh.fact_busqueda        f
JOIN   dwh.dim_tipo_documento  td ON f.id_tipo_documento_filtro = td.id_tipo
JOIN   dwh.dim_tiempo           t ON f.fecha                    = t.fecha
GROUP  BY td.nombre, t.anio
ORDER  BY td.nombre, t.anio;

-- Variante mas compleja: recorre la jerarquia del copo de nieve
-- (documento -> materia -> carrera -> escuela) para agrupar
-- publicaciones por Escuela y cuatrimestre durante 2026.
/*
SELECT
    e.nombre        AS escuela,
    t.cuatrimestre,
    count(*)        AS total_publicaciones
FROM   dwh.fact_publicacion f
JOIN   dwh.dim_documento    d ON f.id_documento_sk = d.id_documento_sk
JOIN   dwh.dim_materia      m ON d.id_materia      = m.id_materia
JOIN   dwh.dim_carrera      c ON m.id_carrera      = c.id_carrera
JOIN   dwh.dim_escuela      e ON c.id_escuela      = e.id_escuela
JOIN   dwh.dim_tiempo       t ON f.fecha           = t.fecha
WHERE  t.anio = 2026
GROUP  BY e.nombre, t.cuatrimestre
ORDER  BY e.nombre, t.cuatrimestre;
*/
