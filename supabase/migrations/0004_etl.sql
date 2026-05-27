-- =============================================================
-- BUSCASAM DWH - Proceso ETL Integrado (ELT Interno)
-- =============================================================
-- Esta migracion define el procedimiento principal para realizar
-- la carga inicial y las actualizaciones incrementales diarias
-- desde el esquema operativo al analitico (DWH).
-- =============================================================

-- =============================================================
-- FUNCION PRINCIPAL: dwh.run_etl()
-- =============================================================
CREATE OR REPLACE FUNCTION dwh.run_etl()
RETURNS void AS $$
DECLARE
    v_watermark_vis TIMESTAMP;
    v_watermark_fav TIMESTAMP;
    v_watermark_doc TIMESTAMP;
    
    v_last_vis TIMESTAMP;
    v_last_fav TIMESTAMP;
    v_last_doc TIMESTAMP;
BEGIN
    -- -------------------------------------------------------------
    -- 1. ASEGURAR CATALOGOS Y SENTINELS EN DWH
    -- -------------------------------------------------------------
    
    -- Tipos de interacciones en DWH
    INSERT INTO dwh.dim_tipo_interaccion (id_tipo_interaccion, nombre) VALUES
        (1, 'publicacion'),
        (2, 'visualizacion'),
        (3, 'favorito_agregar')
    -- UPSERT: Si el ID ya existe, actualiza el valor con el que se intento insertar (EXCLUDED). Garantiza que el script sea idempotente.
    ON CONFLICT (id_tipo_interaccion) DO UPDATE SET nombre = EXCLUDED.nombre;
    
    -- Poblado de la dimension tiempo si esta vacia (2024-01-01 a 2026-12-31)
    IF NOT EXISTS (SELECT 1 FROM dwh.dim_tiempo LIMIT 1) THEN
        INSERT INTO dwh.dim_tiempo (fecha, dia, mes, cuatrimestre, anio)
        SELECT
            d::date,
            EXTRACT(DAY   FROM d)::smallint,
            EXTRACT(MONTH FROM d)::smallint,
            CASE WHEN EXTRACT(MONTH FROM d) <= 7 THEN 1 ELSE 2 END::smallint,
            EXTRACT(YEAR  FROM d)::smallint
        -- generate_series crea un conjunto de filas dinamico, una por cada dia. Forma eficiente en Postgres para poblar la tabla de tiempo sin bucles.
        FROM generate_series('2024-01-01'::date, '2026-12-31'::date, '1 day'::interval) d;
    END IF;

    -- Usuario sentinel para busquedas e interacciones anonimas
    INSERT INTO dwh.dim_usuario (id_usuario, id_carrera, nombre_carrera, nombre_escuela, nombre) VALUES
        (0, 0, 'Invitado Anonimo', 'Sin Escuela', 'Sin Carrera')
    ON CONFLICT (id_usuario) DO NOTHING;

    -- -------------------------------------------------------------
    -- 2. LEER WATERMARKS (MARCAS DE AGUA)
    -- -------------------------------------------------------------
    
    SELECT ultimo_procesado INTO v_watermark_vis FROM dwh.etl_watermark WHERE tabla_origen = 'visualizacion';
    SELECT ultimo_procesado INTO v_watermark_fav FROM dwh.etl_watermark WHERE tabla_origen = 'favorito';
    SELECT ultimo_procesado INTO v_watermark_doc FROM dwh.etl_watermark WHERE tabla_origen = 'documento';

    -- Si no existen las marcas de agua, inicializar con epoca (1970)
    -- COALESCE devuelve el primer valor no nulo. Si v_watermark_vis es NULL (primer uso del ETL), asegura leer toda la historia desde 1970.
    v_watermark_vis := COALESCE(v_watermark_vis, '1970-01-01 00:00:00'::timestamp);
    v_watermark_fav := COALESCE(v_watermark_fav, '1970-01-01 00:00:00'::timestamp);
    v_watermark_doc := COALESCE(v_watermark_doc, '1970-01-01 00:00:00'::timestamp);

    -- -------------------------------------------------------------
    -- 3. EXTRAER Y TRANSFORMAR DIMENSIONES (SCD Tipo 1)
    -- -------------------------------------------------------------
    
    -- dim_materia (jerarquia Escuela > Carrera > Materia aplanada)
    -- La aplanacion (desnormalizacion) agrupa todo en una sola tabla de dimension, clave en esquemas de estrella de DWH.
    INSERT INTO dwh.dim_materia (id_materia, nombre_materia, id_carrera, nombre_carrera, id_escuela, nombre_escuela)
    SELECT
        m.id,
        m.nombre,
        c.id,
        c.nombre,
        e.id,
        e.nombre
    FROM operativo.materia m
    JOIN operativo.carrera c ON m.id_carrera = c.id
    JOIN operativo.escuela e ON c.id_escuela = e.id
    -- Implementa SCD Tipo 1 (Slowly Changing Dimensions): sobrescribe datos antiguos sin guardar historial.
    ON CONFLICT (id_materia) DO UPDATE SET
        nombre_materia = EXCLUDED.nombre_materia,
        id_carrera = EXCLUDED.id_carrera,
        nombre_carrera = EXCLUDED.nombre_carrera,
        id_escuela = EXCLUDED.id_escuela,
        nombre_escuela = EXCLUDED.nombre_escuela;

    -- dim_tipo_documento
    INSERT INTO dwh.dim_tipo_documento (id_tipo, nombre)
    SELECT id, nombre FROM operativo.tipo_documento
    ON CONFLICT (id_tipo) DO UPDATE SET nombre = EXCLUDED.nombre;

    -- dim_usuario (SCD1 - sobreescribe datos academicos actuales)
    INSERT INTO dwh.dim_usuario (id_usuario, id_carrera, nombre_carrera, nombre_escuela, nombre)
    SELECT
        u.id,
        COALESCE(u.id_carrera, 0),
        COALESCE(c.nombre, 'Sin Carrera'),
        COALESCE(e.nombre, 'Sin Escuela'),
        u.nombre
    FROM operativo.usuario u
    LEFT JOIN operativo.carrera c ON u.id_carrera = c.id
    LEFT JOIN operativo.escuela e ON c.id_escuela = e.id
    ON CONFLICT (id_usuario) DO UPDATE SET
        id_carrera = EXCLUDED.id_carrera,
        nombre_carrera = EXCLUDED.nombre_carrera,
        nombre_escuela = EXCLUDED.nombre_escuela,
        nombre = EXCLUDED.nombre;

    -- dim_documento
    INSERT INTO dwh.dim_documento (id_documento, id_tipo, id_materia, titulo, fecha_alta, visibilidad, is_deleted, deleted_at)
    SELECT
        id,
        id_tipo,
        id_materia,
        titulo,
        created_at::date,
        visibilidad,
        (deleted_at IS NOT NULL) AS is_deleted,
        deleted_at::date
    FROM operativo.documento
    ON CONFLICT (id_documento) DO UPDATE SET
        id_tipo = EXCLUDED.id_tipo,
        id_materia = EXCLUDED.id_materia,
        titulo = EXCLUDED.titulo,
        visibilidad = EXCLUDED.visibilidad,
        is_deleted = EXCLUDED.is_deleted,
        deleted_at = EXCLUDED.deleted_at;

    -- -------------------------------------------------------------
    -- 4. CAPTURAR MAX_TIMESTAMPS DE LA CORRIDA ACTUAL
    -- -------------------------------------------------------------
    -- Captura la fecha/hora tope. Se usa para evitar perdida de datos de registros que ingresan *mientras* el ETL corre (race condition).
    SELECT COALESCE(max(created_at), v_watermark_vis) INTO v_last_vis FROM operativo.evento_visualizacion;
    SELECT COALESCE(max(created_at), v_watermark_fav) INTO v_last_fav FROM operativo.favorito;
    SELECT COALESCE(max(created_at), v_watermark_doc) INTO v_last_doc FROM operativo.documento;

    -- -------------------------------------------------------------
    -- 5. EXTRAER, TRANSFORMAR Y CARGAR HECHOS (INCREMENTAL)
    -- -------------------------------------------------------------

    -- hechos: fact_interaccion_documento (Rollup Diario)
    
    -- A) Visualizaciones
    INSERT INTO dwh.fact_interaccion_documento (fecha, id_documento, id_tipo_interaccion, cant_interacciones)
    SELECT
        created_at::date AS fecha,
        id_documento,
        2 AS id_tipo_interaccion, -- visualizacion
        COUNT(*) AS cant_interacciones
    FROM operativo.evento_visualizacion
    WHERE created_at > v_watermark_vis AND created_at <= v_last_vis
    GROUP BY 1, 2, 3
    -- Suma las nuevas interacciones (EXCLUDED) a las ya existentes en ese dia (delta updates). Util si el ETL corre varias veces al dia.
    ON CONFLICT (fecha, id_documento, id_tipo_interaccion) DO UPDATE SET
        cant_interacciones = dwh.fact_interaccion_documento.cant_interacciones + EXCLUDED.cant_interacciones;

    -- B) Favoritos
    INSERT INTO dwh.fact_interaccion_documento (fecha, id_documento, id_tipo_interaccion, cant_interacciones)
    SELECT
        created_at::date AS fecha,
        id_documento,
        3 AS id_tipo_interaccion, -- favorito_agregar
        COUNT(*) AS cant_interacciones
    FROM operativo.favorito
    WHERE created_at > v_watermark_fav AND created_at <= v_last_fav
    GROUP BY 1, 2, 3
    ON CONFLICT (fecha, id_documento, id_tipo_interaccion) DO UPDATE SET
        cant_interacciones = dwh.fact_interaccion_documento.cant_interacciones + EXCLUDED.cant_interacciones;

    -- C) Publicaciones (1 sola vez por documento)
    INSERT INTO dwh.fact_interaccion_documento (fecha, id_documento, id_tipo_interaccion, cant_interacciones)
    SELECT
        created_at::date AS fecha,
        id,
        1 AS id_tipo_interaccion, -- publicacion
        1 AS cant_interacciones
    FROM operativo.documento
    WHERE created_at > v_watermark_doc AND created_at <= v_last_doc
    -- Una publicacion solo se cuenta una vez. Si ya existe la interaccion de publicacion, se ignora.
    ON CONFLICT (fecha, id_documento, id_tipo_interaccion) DO NOTHING;


    -- hechos: fact_interaccion_autor (Rollup Diario, resolviendo coautorias)
    
    -- A) Visualizaciones por autor
    INSERT INTO dwh.fact_interaccion_autor (fecha, id_usuario, id_tipo_interaccion, cant_interacciones)
    SELECT
        ev.created_at::date AS fecha,
        da.id_usuario,
        2 AS id_tipo_interaccion, -- visualizacion
        COUNT(*) AS cant_interacciones
    FROM operativo.evento_visualizacion ev
    JOIN operativo.documento_autor da ON ev.id_documento = da.id_documento
    WHERE ev.created_at > v_watermark_vis AND ev.created_at <= v_last_vis
    GROUP BY 1, 2, 3
    ON CONFLICT (fecha, id_usuario, id_tipo_interaccion) DO UPDATE SET
        cant_interacciones = dwh.fact_interaccion_autor.cant_interacciones + EXCLUDED.cant_interacciones;

    -- B) Favoritos por autor
    INSERT INTO dwh.fact_interaccion_autor (fecha, id_usuario, id_tipo_interaccion, cant_interacciones)
    SELECT
        f.created_at::date AS fecha,
        da.id_usuario,
        3 AS id_tipo_interaccion, -- favorito_agregar
        COUNT(*) AS cant_interacciones
    FROM operativo.favorito f
    JOIN operativo.documento_autor da ON f.id_documento = da.id_documento
    WHERE f.created_at > v_watermark_fav AND f.created_at <= v_last_fav
    GROUP BY 1, 2, 3
    ON CONFLICT (fecha, id_usuario, id_tipo_interaccion) DO UPDATE SET
        cant_interacciones = dwh.fact_interaccion_autor.cant_interacciones + EXCLUDED.cant_interacciones;

    -- C) Publicaciones por autor
    INSERT INTO dwh.fact_interaccion_autor (fecha, id_usuario, id_tipo_interaccion, cant_interacciones)
    SELECT
        d.created_at::date AS fecha,
        da.id_usuario,
        1 AS id_tipo_interaccion, -- publicacion
        COUNT(*) AS cant_interacciones
    FROM operativo.documento d
    JOIN operativo.documento_autor da ON d.id = da.id_documento
    WHERE d.created_at > v_watermark_doc AND d.created_at <= v_last_doc
    GROUP BY 1, 2, 3
    ON CONFLICT (fecha, id_usuario, id_tipo_interaccion) DO NOTHING;


    -- -------------------------------------------------------------
    -- 6. ACTUALIZAR MARCAS DE AGUA
    -- -------------------------------------------------------------
    
    INSERT INTO dwh.etl_watermark (tabla_origen, ultimo_procesado, ultima_corrida) VALUES
        ('visualizacion', v_last_vis, now()),
        ('favorito',      v_last_fav, now()),
        ('documento',     v_last_doc, now())
    ON CONFLICT (tabla_origen) DO UPDATE SET
        ultimo_procesado = EXCLUDED.ultimo_procesado,
        ultima_corrida = EXCLUDED.ultima_corrida;

END;
$$ LANGUAGE plpgsql;
