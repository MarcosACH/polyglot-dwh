# Métricas Adicionales — Dashboard BI Buscasam

> Este documento lista métricas adicionales que se podrían incorporar al dashboard BI
> sin modificar el esquema actual del DWH. Se indica para cada una las tablas
> involucradas y si es posible en ambas versiones del modelo (agregado y transaccional)
> o solo en la transaccional.

---

## Métricas posibles en ambas versiones

### Análisis temporal / estacionalidad

| Métrica | Descripción | Tablas involucradas |
|---|---|---|
| **Tendencia de actividad por mes/cuatrimestre** | Línea de tiempo mostrando el volumen total de interacciones a lo largo del tiempo. Permite detectar si la plataforma está creciendo o estancada. | `fact_interaccion_documento` / `agg_interaccion_dia_documento` + `dim_tiempo` |
| **Estacionalidad cuatrimestral** | Comparar actividad entre cuatrimestre 1 vs. 2 vs. verano. ¿Cuándo se usa más la plataforma? | Idem, agrupando por `cuatrimestre` |
| **Ritmo de publicación** | ¿Se publican más documentos al final del cuatrimestre (entregas)? Filtrar `tipo = publicacion` y graficar por mes. | `fact_interaccion_documento` + `dim_tiempo` |
| **Evolución de una query específica** | Graficar el `score` o `ranking` de una query a lo largo del tiempo. | `fact_query_popularity` |

### Análisis de documentos

| Métrica | Descripción | Tablas involucradas |
|---|---|---|
| **Distribución por tipo de documento** | ¿Qué porcentaje son tesis, apuntes, TPs, etc.? Visualización en pie/donut chart. | `dim_documento` + `dim_tipo_documento` |
| **Ratio views / favoritos (engagement)** | De todos los que ven un documento, ¿qué fracción lo favoritea? Permite detectar documentos de nicho con alta conversión. | `fact_interaccion_documento`, pivoteando por `tipo_interaccion` |
| **Documentos sin actividad** | Documentos con 0 o muy pocas interacciones desde su publicación. Cruce de `dim_documento.fecha_alta` con la fact table. | `dim_documento` LEFT JOIN `fact_interaccion_documento` |
| **Tasa de eliminación** | Porcentaje de documentos eliminados (`is_deleted`) por escuela, carrera o tipo. ¿Hay alguna carrera que elimina mucho contenido? | `dim_documento` + `dim_materia` |
| **Antigüedad vs. popularidad** | ¿Los documentos más viejos acumulan más views por efecto del tiempo, o los recientes son más populares? | `dim_documento.fecha_alta` + `fact_interaccion_documento` |
| **Documentos por visibilidad** | Distribución público / interno / privado, segmentada por escuela o carrera. | `dim_documento` + `dim_materia` |

### Análisis por estructura académica

| Métrica | Descripción | Tablas involucradas |
|---|---|---|
| **Escuelas más activas (por consumo)** | Ranking de escuelas por total de views + favoritos recibidos, no solo por publicaciones. | `fact_interaccion_documento` + `dim_documento` + `dim_materia` |
| **Materias con más documentos** | ¿Qué materias generan más contenido? | `dim_documento` + `dim_materia` |
| **Diversidad de tipos por carrera** | ¿Hay carreras que solo publican TPs y otras que publican tesis y papers? | `dim_documento` + `dim_tipo_documento` + `dim_materia` |

### Análisis de autores

| Métrica | Descripción | Tablas involucradas |
|---|---|---|
| **Autores "one-hit wonder"** | Autores con un solo documento pero alto impacto vs. autores prolíficos con bajo impacto por documento. | `fact_interaccion_autor` + `dim_usuario` |
| **Concentración de impacto (Pareto)** | ¿Los top 10 autores concentran el 80% de las views? | `fact_interaccion_autor` |
| **Autores por escuela** | ¿Qué escuela tiene los autores con más engagement? | `fact_interaccion_autor` + `dim_usuario` |

---

## Métricas exclusivas de la versión transaccional

Estas métricas requieren el `timestamp_evento` o el `id_usuario` que solo existen en
`fact_interaccion_atomico`, y por lo tanto **no son posibles con la versión agregada**.

| Métrica | Descripción | Por qué no se puede en la versión agregada |
|---|---|---|
| **Horas pico de actividad** | ¿A qué hora del día se usa más la plataforma? | No tiene `timestamp_evento`, solo `fecha` |
| **Usuarios más activos (consumidores)** | Ranking de los usuarios que más ven y favoritean documentos — el opuesto a "top autores". | `fact_interaccion_documento` no tiene `id_usuario` |
| **Segmentación consumidor vs. productor** | Usuarios que solo consumen contenido vs. los que también publican. | Requiere `id_usuario` en los hechos atómicos |
| **Secuencia de eventos por sesión** | ¿Un usuario primero busca, luego ve, luego favoritea? Análisis de embudo de conversión. | Requiere eventos individuales con timestamp |
| **Correlación búsquedas → documentos vistos** | Cruzar queries populares con documentos vistos en la misma ventana temporal para entender qué contenido se descubre tras una búsqueda. | Requiere cruce temporal fino entre `fact_query_popularity` y la tabla atómica |
