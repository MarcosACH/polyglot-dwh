-- Live Demo (End-to-End Integration)

--  1: Pre-chequeo (DWH debe estar vacío para estos datos)

SELECT * FROM dwh.dim_materia WHERE nombre_materia = 'Demo SQL en Vivo';
SELECT * FROM dwh.fact_interaccion_documento WHERE id_documento = 9999;
SELECT * FROM dwh.fact_query_popularity WHERE query_texto = 'busqueda redis demo en vivo';


--  2: Inserciones en el esquema Operativo (OLTP)

-- 1. Crear carrera y materia exclusivas para la demo
INSERT INTO operativo.carrera (id, id_escuela, nombre, created_at, updated_at) 
VALUES (999, 1, 'Carrera Demo', NOW(), NOW());

INSERT INTO operativo.materia (id, id_carrera, nombre, created_at, updated_at) 
VALUES (9999, 999, 'Demo SQL en Vivo', NOW(), NOW());

-- 2. Insertar un documento (paper) en esta materia (creado hace 2 meses)
INSERT INTO operativo.documento (id, titulo, abstract, texto_completo, visibilidad, id_tipo, id_materia, id_uploader, archivo_url, created_at, updated_at)
VALUES (9999, 'Investigación SQL en la Nube', 'Abstract de demo', 'Contenido completo', 'publico', 2, 9999, 1, 'url', NOW() - INTERVAL '2 months', NOW() - INTERVAL '2 months');

-- 3. Simular visualizaciones para los últimos 3 meses (2 -> 4 -> 6)
INSERT INTO operativo.evento_visualizacion (id_usuario, id_documento, created_at)
SELECT 1, 9999, NOW() - INTERVAL '2 months' FROM generate_series(1, 2);

INSERT INTO operativo.evento_visualizacion (id_usuario, id_documento, created_at)
SELECT 1, 9999, NOW() - INTERVAL '1 month' FROM generate_series(1, 4);

INSERT INTO operativo.evento_visualizacion (id_usuario, id_documento, created_at)
SELECT 1, 9999, NOW() FROM generate_series(1, 6);


-- >>> NOTA: Asegurarse de insertar nuevos datos en Redis y correr el ETL antes de continuar con la Fase 3.


--  3: Verificación Post-ETL en el DWH

-- 1. Comprobar que la materia y el documento se sincronizaron al DWH
SELECT * FROM dwh.dim_materia WHERE nombre_materia = 'Demo SQL en Vivo';
SELECT * FROM dwh.dim_documento WHERE id_documento = 9999;

-- 2. Comprobar las interacciones consolidadas (hechos)
SELECT 
    d.titulo, 
    ti.nombre AS tipo_evento,
    SUM(f.cant_interacciones) AS total_interacciones
FROM dwh.fact_interaccion_documento f
JOIN dwh.dim_documento d ON f.id_documento = d.id_documento
JOIN dwh.dim_tipo_interaccion ti ON f.id_tipo_interaccion = ti.id_tipo_interaccion
WHERE d.id_documento = 9999
GROUP BY d.titulo, ti.nombre;

-- 3. Verificación de popularidad de queries (Redis -> DWH)
SELECT query_texto, score, ranking
FROM dwh.fact_query_popularity
WHERE fecha = (SELECT MAX(fecha) FROM dwh.fact_query_popularity)
ORDER BY ranking ASC
LIMIT 5;


--  4: Consultas de Minería de Datos (Analytics)

-- 1. Segmentación de autores
SELECT segmento, count(*) FROM dwh.segmentar_autores() GROUP BY segmento;

-- 2. Predicción a 3 meses para el nuevo documento (ID 9999)
SELECT * FROM dwh.predecir_interacciones_documento(9999, 3);


-- SCRIPT DE LIMPIEZA (Ejecutar al finalizar la demo para dejar la DB limpia)

DELETE FROM operativo.evento_visualizacion WHERE id_documento = 9999;
DELETE FROM operativo.documento WHERE id = 9999;
DELETE FROM operativo.materia WHERE id = 9999;
DELETE FROM operativo.carrera WHERE id = 999;
DELETE FROM dwh.fact_interaccion_documento WHERE id_documento = 9999;
DELETE FROM dwh.dim_documento WHERE id_documento = 9999;
DELETE FROM dwh.dim_materia WHERE id_materia = 9999;