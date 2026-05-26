# Comparativa de Enfoques DWH: Agregado vs. Transaccional

> [!NOTE]
> Este documento compara los dos enfoques de diseño propuestos para el Data Warehouse de Buscasam: el **Modelo Agregado** (`agregado.dbml`) y el **Modelo Transaccional / Atómico** (`transaccional.dbml`).

---

## Resumen Ejecutivo

- **Modelo Agregado:** Prioriza la simplicidad, el bajo volumen de almacenamiento y el rendimiento directo. Delega el trabajo pesado de agrupamiento al proceso ETL.
- **Modelo Transaccional:** Prioriza la retención de información histórica detallada (timestamp y usuario) y la flexibilidad para futuros casos de uso. Delega el rendimiento del dashboard a Vistas Materializadas.

---

## 1. Granularidad y Pérdida de Datos

| Característica | Modelo Agregado | Modelo Transaccional |
| :--- | :--- | :--- |
| **Grano (Grain)** | Resumido a nivel Día + Documento/Autor | Atómico. Un evento = Una fila |
| **Timestamp Exacto** | Se pierde. Solo queda la `fecha` (día) | Se conserva (`timestamp_evento`) |
| **Usuario que interactúa** | Se pierde. Solo se guarda "cuántos" | Se conserva (`id_usuario` en la fact) |

> [!WARNING]
> En el modelo agregado es imposible responder preguntas como *"¿A qué hora del día hay más tráfico?"* o *"¿Qué perfil de usuario descarga más papers?"* ya que esos datos se pierden irreversiblemente en el ETL.

## 2. Tratamiento de la Relación N:M (Documentos y Autores)

| Característica | Modelo Agregado | Modelo Transaccional |
| :--- | :--- | :--- |
| **Estrategia** | Resuelta por el ETL previo a la inserción | Resuelta en el DWH mediante un Bridge |
| **Tablas resultantes** | Dos Fact Tables separadas (`fact_interaccion_documento`, `fact_interaccion_autor`) | Una Fact atómica + Vista agregada + `bridge_documento_autor` |

- En el **Agregado**, el ETL se encarga de "dividir" los puntos. Si un documento con 2 autores se visualiza, el ETL inserta 1 fila en la fact de documentos y 2 filas (una por autor) en la fact de autores.
- En el **Transaccional**, el ETL inserta 1 sola fila en la tabla atómica. Es al momento de consultar (usando la vista materializada y la tabla bridge) que los puntos de impacto se asocian a los N autores.

## 3. Flexibilidad vs. Mantenimiento

| Característica | Modelo Agregado | Modelo Transaccional |
| :--- | :--- | :--- |
| **Flexibilidad Futura** | **Baja.** Optimizado exclusivamente para el dashboard actual. | **Alta.** Permite Machine Learning, análisis de sesiones, detección de fraude, etc. |
| **Mantenimiento Base** | **Bajo.** Los datos ya entran sumarizados. | **Medio/Alto.** Requiere truncar y refrescar Vistas Materializadas (`agg_interaccion_dia_documento`) diariamente. |
| **Volumen de Almacenamiento**| **Mínimo.** | **Mayor.** La tabla atómica crece con cada click. |

## 4. Patrón de Diseño (Kimball)

- **Agregado:** Es un modelo dimensional clásico y altamente desnormalizado, orientado 100% a la lectura rápida para un BI predecible.
- **Transaccional:** Sigue un **Patrón C** (Atómico + Agregado). Mantiene una capa fundacional atómica (fuente de la verdad inmutable) sobre la cual se construyen los *Data Marts* o Vistas Agregadas para el consumo final.

---

## Conclusión y Recomendación

**¿Cuál elegir?**

1. **Elegir el Modelo Agregado si:** 
   - El único objetivo de este DWH a corto y mediano plazo es alimentar los 4 gráficos del dashboard.
   - El almacenamiento es limitado.
   - Se quiere mantener la base de datos lo más ligera posible.

2. **Elegir el Modelo Transaccional si:**
   - La plataforma planea usar estos datos en un futuro para un sistema de **recomendación de documentos** o análisis de comportamiento de usuarios (ej: medir la retención intra-día).
   - Se valora la posibilidad de hacer preguntas "ad-hoc" que no estaban previstas originalmente en los requerimientos.

*(Generalmente, en el contexto de Data Warehousing moderno en la nube donde el almacenamiento es barato, se prefiere el **Modelo Transaccional (Patrón C)**, ya que el costo de perder datos históricos suele ser mayor que el costo de almacenarlos).*
