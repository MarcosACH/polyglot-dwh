# Dashboard BI — BUSCASAM

Cuatro elementos de información que se exponen en Power BI, alimentados por el DWH `dwh` (PostgreSQL) con fuentes polyglot: **PostgreSQL operativo** (dimensiones + `fact_interaccion_documento` + `fact_interaccion_autor`) y **Redis** (`fact_query_popularity`).

| # | Elemento | Fact que usa | Fuente |
|---|---|---|---|
| 1 | Heatmap Escuela/Carrera × Tipo de documento | — (`dim_documento`) | PostgreSQL operativo |
| 2 | Top 20 queries más populares | `fact_query_popularity` | **Redis** |
| 3 | Top 10 autores más vistos | `fact_interaccion_autor` | PostgreSQL operativo |
| 4 | Top 10 documentos más vistos/favoriteados (últimos 30 días) | `fact_interaccion_documento` | PostgreSQL operativo |

---

## 1. Heatmap Escuela/Carrera × Tipo de documento

**Pregunta:** ¿Cómo se distribuye la producción académica de la facultad por unidad académica y formato?

**Visualización:** Matrix / Heatmap.
Filas = `nombre_escuela > nombre_carrera`, Columnas = `tipo_documento`, Valor = `cant_publicaciones`.

**Nota de modelado:** es un conteo de catálogo (foto del estado actual, sin eje temporal), por lo que se cuenta directo sobre `dim_documento` filtrando `is_deleted = false`. No se usa el fact porque el evento `publicacion` persiste aunque el documento se borre, y como hay un solo evento de publicación por documento, `COUNT(*)` sobre la dimensión es equivalente y más simple.

**Query:**
```sql
SELECT
    m.nombre_escuela,
    m.nombre_carrera,
    td.nombre AS tipo_documento,
    COUNT(*) AS cant_publicaciones
FROM dwh.dim_documento d
JOIN dwh.dim_materia m         ON d.id_materia = m.id_materia
JOIN dwh.dim_tipo_documento td ON d.id_tipo    = td.id_tipo
WHERE d.is_deleted = false
GROUP BY m.nombre_escuela, m.nombre_carrera, td.nombre
ORDER BY m.nombre_escuela, m.nombre_carrera, td.nombre;
```

---

## 2. Top 20 queries más populares (Redis)

**Pregunta:** ¿Qué está buscando la comunidad en BUSCASAM ahora mismo?

**Visualización:** Tabla con barras inline, ordenada por `score` desc.

**Fuente polyglot:** el ETL diario hace `ZRANGE WITHSCORES` sobre el sorted set `autocomplete:queries` de Redis y graba un snapshot en `fact_query_popularity`. La misma estructura sirve para el autocompletado online y para el dashboard.

**Query (snapshot más reciente):**
```sql
SELECT query_texto, score, ranking
FROM dwh.fact_query_popularity
WHERE fecha = (SELECT MAX(fecha) FROM dwh.fact_query_popularity)
ORDER BY ranking
LIMIT 20;
```

**Query bonus — evolución de una query en el tiempo:**
```sql
SELECT fecha, score
FROM dwh.fact_query_popularity
WHERE query_texto = 'redes neuronales'
ORDER BY fecha;
```

---

## 3. Top 10 autores más vistos

**Pregunta:** ¿Quiénes son los referentes académicos de la facultad por alcance de su producción?

**Visualización:** Bar chart horizontal. Eje Y = autor, Eje X = `visualizaciones`. Slicer por `nombre_escuela`.

**Nota de modelado:** las visualizaciones se imputan al autor en `fact_interaccion_autor` (el ETL resuelve documento → autor(es) y agrega por día). Se rankea por visualizaciones recibidas, no por cantidad de publicaciones.

**Query:**
```sql
SELECT
    u.nombre AS autor,
    u.nombre_escuela,
    u.nombre_carrera,
    SUM(f.cant_interacciones) AS visualizaciones
FROM dwh.fact_interaccion_autor f
JOIN dwh.dim_usuario u
    ON f.id_usuario = u.id_usuario
JOIN dwh.dim_tipo_interaccion ti
    ON f.id_tipo_interaccion = ti.id_tipo_interaccion
WHERE ti.nombre = 'visualizacion'
GROUP BY u.nombre, u.nombre_escuela, u.nombre_carrera
ORDER BY visualizaciones DESC
LIMIT 10;
```

---

## 4. Top 10 documentos más vistos / favoriteados (últimos 30 días)

**Pregunta:** ¿Qué trabajos están traccionando en la plataforma últimamente?

**Visualización:** Tabla o bar chart apilado. Categoría = `titulo`, valores = `visualizaciones` + `favoritos` apilados, con su `nombre_escuela` como contexto.

**Query:**
```sql
WITH interaccion AS (
    SELECT
        f.id_documento,
        SUM(CASE WHEN ti.nombre = 'visualizacion'    THEN f.cant_interacciones ELSE 0 END) AS visualizaciones,
        SUM(CASE WHEN ti.nombre = 'favorito_agregar' THEN f.cant_interacciones ELSE 0 END) AS favoritos,
        SUM(f.cant_interacciones) AS total_interacciones
    FROM dwh.fact_interaccion_documento f
    JOIN dwh.dim_tipo_interaccion ti ON f.id_tipo_interaccion = ti.id_tipo_interaccion
    WHERE ti.nombre IN ('visualizacion', 'favorito_agregar')
      AND f.fecha >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY f.id_documento
)
SELECT
    d.titulo,
    m.nombre_escuela,
    m.nombre_carrera,
    i.visualizaciones,
    i.favoritos,
    i.total_interacciones
FROM interaccion i
JOIN dwh.dim_documento d
    ON i.id_documento = d.id_documento
   AND d.is_deleted = false
JOIN dwh.dim_materia m ON d.id_materia = m.id_materia
ORDER BY i.total_interacciones DESC
LIMIT 10;
```
