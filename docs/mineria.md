# Minería de Datos — BUSCASAM

Dos funciones dinámicas sobre el DWH `dwh`, implementadas en **SQL nativo de PostgreSQL** (sin extensiones de ML). Se definen en [`supabase/migrations/20260530100300_dwh_mineria.sql`](../supabase/migrations/20260530100300_dwh_mineria.sql). Son *dinámicas* porque recalculan sobre los datos actuales del DWH según los parámetros que reciben.

| # | Técnica | Función | Fact que usa |
|---|---|---|---|
| 1 | Segmentación | `dwh.segmentar_autores(desde, hasta, escuela)` | `fact_interaccion_autor` |
| 2 | Predicción | `dwh.predecir_interacciones_documento(id_doc, horizonte)` | `fact_interaccion_documento` |

---

## 1. Segmentación — autores en matriz volumen × impacto

**Pregunta:** ¿Cómo se distribuyen los autores según cuánto producen y cuánto impacto genera lo que producen?

**Técnica:** segmentación bidimensional tipo RFM. Por cada autor se calculan dos ejes en el rango de fechas:

- **Volumen** = publicaciones (`fact_interaccion_autor`, tipo `publicacion`)
- **Impacto** = visualizaciones + favoritos recibidos (tipos `visualizacion` + `favorito_agregar`)

`NTILE(2)` parte cada eje por su mediana (mitad alta / mitad baja). El cruce de ambos define 4 segmentos:

| | Impacto bajo | Impacto alto |
|---|---|---|
| **Volumen alto** | Prolífico sin alcance | **Referente** |
| **Volumen bajo** | Periférico | Joya oculta |

- **Referente:** mucha producción y mucho consumo → cara visible del área.
- **Joya oculta:** pocos trabajos pero muy consumidos → talento subexpuesto para potenciar.
- **Prolífico sin alcance:** mucha producción que no tracciona → revisar difusión/calidad.
- **Periférico:** baja actividad.

**Firma:**
```sql
dwh.segmentar_autores(
    p_fecha_desde DATE    DEFAULT '2024-01-01',
    p_fecha_hasta DATE    DEFAULT CURRENT_DATE,
    p_escuela     VARCHAR DEFAULT NULL   -- NULL = todas las escuelas
)
```

**Uso — distribución global de segmentos:**
```sql
SELECT segmento, count(*)
FROM   dwh.segmentar_autores()
GROUP  BY segmento
ORDER  BY 2 DESC;
```
```
       segmento        | count
-----------------------+-------
 Periferico            |   960
 Referente             |   960
 Prolifico sin alcance |    40
 Joya oculta           |    40
```
Volumen e impacto correlacionan fuerte, así que la mayoría cae en la diagonal (Periférico / Referente); los pocos casos off-diagonal (Joya oculta, Prolífico sin alcance) son los más interesantes para accionar.

**Uso — referentes de una escuela en un período:**
```sql
SELECT id_usuario, nombre_escuela, n_publicaciones, impacto, segmento
FROM   dwh.segmentar_autores('2024-01-01', '2026-12-31', 'Escuela de Humanidades')
LIMIT  5;
```

**Dinamismo:** al pasar otro rango de fechas o escuela, las medianas (`NTILE`) se recalculan **sobre ese subconjunto** — un autor puede ser Referente en su escuela pero Periférico a nivel global.

---

## 2. Predicción — forecast de visualizaciones de un documento

**Pregunta:** ¿Las visualizaciones de un documento vienen creciendo o cayendo, y qué nivel se espera el mes próximo?

**Técnica:** regresión lineal por mínimos cuadrados con los agregados nativos `regr_slope` / `regr_intercept` / `regr_r2`. Se arma la serie mensual de visualizaciones del documento y se ajusta la recta `total = a + b·mes`:

- **pendiente (`b`)** → ritmo de cambio mensual; su signo clasifica la tendencia (`creciente` / `estable` / `decreciente`).
- **`r2`** → qué tan bien la recta explica la serie (0 = ruido, 1 = lineal perfecta).
- **proyección** = `a + b·(último_mes + horizonte)`.

**Firma:**
```sql
dwh.predecir_interacciones_documento(
    p_id_documento    INTEGER,
    p_horizonte_meses INTEGER DEFAULT 3
)
```

**Uso:**
```sql
SELECT * FROM dwh.predecir_interacciones_documento(1, 3);
```
```
 id_documento |                  titulo                   | meses_con_datos | pendiente_mensual |  r2   | prom_mensual | proyeccion | tendencia
--------------+-------------------------------------------+-----------------+-------------------+-------+--------------+------------+-----------
            1 | Documento 1: estudio sobre redes neuronales |              36 |             1.000 | 1.000 |        23.50 |      44.00 | creciente
```

Comparando varios documentos (1 creciente, 2 decreciente, 3 estable):
```sql
SELECT * FROM dwh.predecir_interacciones_documento(1)
UNION ALL SELECT * FROM dwh.predecir_interacciones_documento(2)
UNION ALL SELECT * FROM dwh.predecir_interacciones_documento(3);
```
```
 id_documento | ... | pendiente_mensual |  r2   | prom_mensual | proyeccion |  tendencia
--------------+-----+-------------------+-------+--------------+------------+-------------
            1 | ... |             1.000 | 1.000 |        23.50 |      44.00 | creciente
            2 | ... |            -1.003 | 0.997 |        23.67 |       3.10 | decreciente
            3 | ... |             0.002 | 0.003 |        22.28 |      22.33 | estable
```
El `r2` distingue la señal del ruido: ~1.0 en las series con tendencia real, ~0 en la plana.

**Dinamismo:** la regresión se reajusta por documento y por horizonte en cada llamada; sirve como insumo para alertas ("este trabajo se está apagando") o para priorizar contenido en alza.

> **Nota sobre los datos:** las interacciones del seed son uniformes en el tiempo, por lo que un documento cualquiera da pendiente ≈ 0 (la regresión es correcta, pero no hay tendencia que mostrar). Para ilustrar la función, el seed inyecta una serie mensual marcada en los documentos **1 (creciente), 2 (decreciente) y 3 (estable)**.
