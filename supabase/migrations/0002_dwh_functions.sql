-- =============================================================
-- BUSCASAM DWH - Funciones de mineria de datos (Supabase-compatible)
-- =============================================================
-- predecir_descargas: plpgsql puro, corre tal cual en Supabase.
-- segmentar_usuarios: requiere plpython3u (no disponible en Supabase Cloud).
--                     Ver supabase/optional/segmentar_usuarios_plpython.sql
--                     para correrla en una instancia self-hosted.
-- =============================================================

CREATE OR REPLACE FUNCTION dwh.predecir_descargas(
    p_id_documento_bk INTEGER,
    p_dias_horizonte  INTEGER DEFAULT 30
)
RETURNS TABLE (
    descargas_actuales  INTEGER,
    descargas_estimadas INTEGER,
    r2                  NUMERIC(4,3),
    dias_de_historia    INTEGER
)
LANGUAGE plpgsql AS $$
DECLARE
    v_slope     NUMERIC;
    v_intercept NUMERIC;
    v_r2        NUMERIC;
    v_dias      INTEGER;
    v_total     INTEGER;
BEGIN
    WITH serie AS (
        SELECT f.fecha,
               (f.fecha - min(f.fecha) OVER ())      AS dias_desde_inicio,
               sum(count(*)) OVER (ORDER BY f.fecha) AS acumulado
        FROM   dwh.fact_descarga f
        JOIN   dwh.dim_documento d ON f.id_documento_sk = d.id_documento_sk
        WHERE  d.id_documento_bk = p_id_documento_bk
        GROUP  BY f.fecha
    )
    SELECT regr_slope(acumulado, dias_desde_inicio),
           regr_intercept(acumulado, dias_desde_inicio),
           regr_r2(acumulado, dias_desde_inicio),
           max(dias_desde_inicio),
           max(acumulado)
    INTO   v_slope, v_intercept, v_r2, v_dias, v_total
    FROM   serie;

    IF v_dias IS NULL OR v_dias < 7 OR v_slope IS NULL THEN
        RAISE EXCEPTION 'historia insuficiente: se requieren al menos 7 dias con descargas (hay %)',
            COALESCE(v_dias, 0);
    END IF;

    RETURN QUERY SELECT
        v_total::INTEGER,
        GREATEST(
            v_total,
            ROUND(v_slope * (v_dias + p_dias_horizonte) + v_intercept)
        )::INTEGER,
        ROUND(v_r2, 3),
        v_dias;
END;
$$;
