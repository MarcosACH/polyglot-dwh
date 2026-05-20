# Dashboard BI — BUSCASAM

Cuatro elementos de información que se exponen en Power BI, alimentados por el DWH `dwh` (PostgreSQL) con fuentes polyglot: **PostgreSQL operativo** (dimensiones + `fact_interaccion_documento`) y **Redis** (`fact_query_popularity`).

| # | Elemento | Fact que usa | Fuente |
|---|---|---|---|
| 1 | Heatmap Escuela/Carrera × Tipo de documento | — (`dim_documento`) | PostgreSQL operativo |
| 2 | Top 20 queries más populares | `fact_query_popularity` | **Redis** |
| 3 | Top 10 autores más prolíficos | — (`bridge_documento_autor`) | PostgreSQL operativo |
| 4 | Top 10 documentos más vistos/favoriteados (últimos 30 días) | `fact_interaccion_documento` | PostgreSQL operativo |

---

## 1. Heatmap Escuela/Carrera × Tipo de documento

**Pregunta:** ¿Cómo se distribuye la producción académica de la facultad por unidad académica y formato?

**Visualización:** Matrix / Heatmap.
Filas = `nombre_escuela > nombre_carrera`, Columnas = `tipo_documento`, Valor = `cant_publicaciones`.

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
WHERE d.is_current = true
  AND d.is_deleted = false
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

## 3. Top 10 autores más prolíficos

**Pregunta:** ¿Quiénes son los referentes académicos de la facultad por volumen de producción?

**Visualización:** Bar chart horizontal. Eje Y = autor, Eje X = `cant_publicaciones`. Slicer por `nombre_escuela`.

**Query:**
```sql
SELECT
    u.nombre AS autor,
    u.nombre_escuela,
    u.nombre_carrera,
    COUNT(DISTINCT b.id_documento_bk) AS cant_publicaciones
FROM dwh.bridge_documento_autor b
JOIN dwh.dim_usuario u
    ON b.id_usuario_bk = u.id_usuario_bk
   AND u.is_current = true
JOIN dwh.dim_documento d
    ON b.id_documento_bk = d.id_documento_bk
   AND d.is_current = true
   AND d.is_deleted = false
GROUP BY u.nombre, u.nombre_escuela, u.nombre_carrera
ORDER BY cant_publicaciones DESC
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
        d.id_documento_bk,
        SUM(CASE WHEN ti.nombre = 'visualizacion'    THEN f.cant_interacciones ELSE 0 END) AS visualizaciones,
        SUM(CASE WHEN ti.nombre = 'favorito_agregar' THEN f.cant_interacciones ELSE 0 END) AS favoritos,
        SUM(f.cant_interacciones) AS total_interacciones
    FROM dwh.fact_interaccion_documento f
    JOIN dwh.dim_tipo_interaccion ti ON f.id_tipo_interaccion = ti.id_tipo_interaccion
    JOIN dwh.dim_documento d         ON f.id_documento_sk = d.id_documento_sk
    WHERE ti.nombre IN ('visualizacion', 'favorito_agregar')
      AND f.fecha >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY d.id_documento_bk
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
    ON i.id_documento_bk = d.id_documento_bk
   AND d.is_current = true
   AND d.is_deleted = false
JOIN dwh.dim_materia m ON d.id_materia = m.id_materia
ORDER BY i.total_interacciones DESC
LIMIT 10;
```
