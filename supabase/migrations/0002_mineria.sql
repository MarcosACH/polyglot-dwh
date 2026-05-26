-- =============================================================
-- BUSCASAM DWH - Mineria de datos (punto 5 de la consigna)
-- Funciones dinamicas implementadas en SQL nativo de PostgreSQL:
--   1. Segmentacion: autores en matriz volumen x impacto (NTILE).
--   2. Prediccion: forecast de visualizaciones de un documento
--      por regresion lineal (regr_slope / regr_intercept / regr_r2).
-- Son "dinamicas" porque recalculan sobre los datos actuales del
-- DWH segun los parametros recibidos.
-- =============================================================

-- =============================================================
-- 1. SEGMENTACION - autores en matriz volumen x impacto
-- =============================================================
-- Dos ejes por autor en el rango de fechas dado:
--   volumen  = publicaciones                (fact_interaccion_autor, tipo publicacion)
--   impacto  = visualizaciones + favoritos  (tipos visualizacion + favorito_agregar)
-- NTILE(2) parte cada eje por la mediana -> 4 cuadrantes:
--   Referente | Prolifico sin alcance | Joya oculta | Periferico
-- =============================================================

CREATE OR REPLACE FUNCTION dwh.segmentar_autores(
    p_fecha_desde DATE    DEFAULT '2024-01-01',
    p_fecha_hasta DATE    DEFAULT CURRENT_DATE,
    p_escuela     VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    id_usuario      INTEGER,
    autor           VARCHAR,
    nombre_escuela  VARCHAR,
    n_publicaciones BIGINT,
    impacto         BIGINT,
    segmento        TEXT
)
LANGUAGE sql STABLE
AS $$
    WITH metricas AS (
        SELECT
            u.id_usuario,
            u.nombre          AS autor,
            u.nombre_escuela,
            COALESCE(SUM(f.cant_interacciones)
                     FILTER (WHERE ti.nombre = 'publicacion'), 0) AS n_publicaciones,
            COALESCE(SUM(f.cant_interacciones)
                     FILTER (WHERE ti.nombre IN ('visualizacion','favorito_agregar')), 0) AS impacto
        FROM dwh.dim_usuario u
        JOIN dwh.fact_interaccion_autor f  ON f.id_usuario = u.id_usuario
        JOIN dwh.dim_tipo_interaccion  ti  ON ti.id_tipo_interaccion = f.id_tipo_interaccion
        WHERE f.fecha BETWEEN p_fecha_desde AND p_fecha_hasta
          AND (p_escuela IS NULL OR u.nombre_escuela = p_escuela)
        GROUP BY u.id_usuario, u.nombre, u.nombre_escuela
    ),
    cuadrantes AS (
        SELECT *,
            NTILE(2) OVER (ORDER BY n_publicaciones) AS q_vol,
            NTILE(2) OVER (ORDER BY impacto)         AS q_imp
        FROM metricas
    )
    SELECT
        id_usuario, autor, nombre_escuela, n_publicaciones, impacto,
        CASE
            WHEN q_vol = 2 AND q_imp = 2 THEN 'Referente'
            WHEN q_vol = 2 AND q_imp = 1 THEN 'Prolifico sin alcance'
            WHEN q_vol = 1 AND q_imp = 2 THEN 'Joya oculta'
            ELSE 'Periferico'
        END AS segmento
    FROM cuadrantes
    ORDER BY impacto DESC, n_publicaciones DESC;
$$;

-- =============================================================
-- 2. PREDICCION - forecast de visualizaciones de un documento
-- =============================================================
-- Arma la serie mensual de visualizaciones del documento y ajusta
-- una recta total = a + b*mes (regresion lineal por minimos
-- cuadrados, agregados nativos regr_*). Proyecta el promedio mensual
-- a p_horizonte_meses y clasifica la tendencia por la pendiente.
-- =============================================================

CREATE OR REPLACE FUNCTION dwh.predecir_interacciones_documento(
    p_id_documento    INTEGER,
    p_horizonte_meses INTEGER DEFAULT 3
)
RETURNS TABLE (
    id_documento      INTEGER,
    titulo            VARCHAR,
    meses_con_datos   BIGINT,
    pendiente_mensual NUMERIC,
    r2                NUMERIC,
    prom_mensual      NUMERIC,
    proyeccion        NUMERIC,
    tendencia         TEXT
)
LANGUAGE sql STABLE
AS $$
    WITH serie AS (
        SELECT
            date_trunc('month', f.fecha)::date AS mes,
            SUM(f.cant_interacciones)          AS total
        FROM dwh.fact_interaccion_documento f
        JOIN dwh.dim_tipo_interaccion ti ON ti.id_tipo_interaccion = f.id_tipo_interaccion
        WHERE f.id_documento = p_id_documento
          AND ti.nombre = 'visualizacion'
        GROUP BY 1
    ),
    indexada AS (
        -- m = numero de mes relativo al primer mes con datos (respeta gaps)
        SELECT
            total,
            ((EXTRACT(YEAR FROM mes) * 12 + EXTRACT(MONTH FROM mes))
              - MIN(EXTRACT(YEAR FROM mes) * 12 + EXTRACT(MONTH FROM mes)) OVER ())::int AS m
        FROM serie
    ),
    reg AS (
        SELECT
            regr_slope(total, m)     AS slope,
            regr_intercept(total, m) AS intercept,
            regr_r2(total, m)        AS r2,
            count(*)                 AS n,
            max(m)                   AS m_max,
            avg(total)               AS prom
        FROM indexada
    )
    SELECT
        p_id_documento,
        (SELECT titulo FROM dwh.dim_documento WHERE id_documento = p_id_documento),
        reg.n,
        ROUND(reg.slope::numeric, 3),
        ROUND(reg.r2::numeric, 3),
        ROUND(reg.prom::numeric, 2),
        ROUND((reg.intercept + reg.slope * (reg.m_max + p_horizonte_meses))::numeric, 2),
        CASE
            WHEN reg.slope >  0.5 THEN 'creciente'
            WHEN reg.slope < -0.5 THEN 'decreciente'
            ELSE 'estable'
        END
    FROM reg;
$$;
