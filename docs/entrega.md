## Presentación del Escenario
La comunidad universitaria de UNSAM no cuenta con una plataforma centralizada para acceder a su producción académica (tesis, papers, trabajos prácticos, proyectos de investigación, etc.). El material está disperso entre cátedras, carreras y repositorios personales, y los buscadores existentes solo encuentran coincidencias exactas de palabras, sin entender lo que el usuario realmente quiso buscar.

## Empresa
La Universidad Nacional de San Martín (UNSAM) es una institución académica pública organizada en Escuelas, Carreras y Materias. Los usuarios del sistema serán estudiantes y docentes de la institución, que ingresarán con su cuenta institucional, junto con invitados externos que podrán consultar contenido público sin registrarse.

## Situación a Implementar/Solucionar
Se desarrollará BUSCASAM, una aplicación web de búsqueda académica inspirada en Google Scholar Labs. El buscador entenderá el significado de la consulta y además detectará las palabras exactas que escribió el usuario, trabajando sobre un conjunto de documentos cargados por la propia comunidad. Incluirá un formulario guiado para publicar trabajos, donde el autor cargará algunos datos básicos y el sistema extraerá automáticamente el resumen, las palabras clave y la fecha, así también permitiendo sumar co-autores, mantener un historial de versiones del archivo y elegir quién puede ver cada trabajo (público, solo UNSAM o privado). Se sumarán filtros por fecha, área y tipo de documento, autocompletado, sugerencias cuando no haya resultados y la opción de ordenar por más recientes. Cada usuario verá recomendaciones personalizadas y trabajos relacionados en cada página de detalle, sin que esto afecte el orden de los resultados de búsqueda, para que dos personas distintas obtengan lo mismo ante la misma consulta. Finalmente, habrá favoritos, comentarios con respuestas, navegación por Escuela, tipo y autor y un sistema de reportes que cualquier docente puede revisar para ocultar contenido inadecuado, con registro de cada acción y posibilidad de apelar.

## Justificación
La iniciativa se justifica porque centralizar la producción académica reduce la dificultad para encontrarla y visibiliza trabajos que hoy quedan fuera del alcance de su cátedra de origen. Entender el significado de la consulta resuelve un problema real, ya que el usuario puede escribir "calentamiento global" y encontrar trabajos sobre "cambio climático", algo imposible con un buscador tradicional. A su vez, combinarlo con la coincidencia exacta de palabras mantiene la precisión cuando se buscan términos puntuales. Que el orden de los resultados sea igual para todos y las direcciones web sean estables permite citar y compartir búsquedas, algo necesario en un contexto académico. Publicar de forma inmediata y moderar después permite que la plataforma se llene rápido sin desalentar a quien quiere subir su trabajo, mientras que el ingreso con cuenta institucional asegura que los permisos reflejen la estructura real de la universidad sin configuración manual. En conjunto, BUSCASAM ofrece una plataforma única, pensada para el ámbito académico de UNSAM y operativa desde el primer día, que resuelve a la vez el problema de encontrar y el de difundir la producción interna.

## Motor SQL: PostgreSQL

**Empresa/organización que lo provee**
PostgreSQL es desarrollado por la PostgreSQL Global Development Group, una comunidad internacional de desarrolladores que sostiene el proyecto desde 1996. No depende de una sola empresa.

**Justificación de la elección**
Será el motor central del sistema y concentrará la mayor parte de la información. En sus tablas se guardarán los usuarios y sus perfiles, los documentos con sus metadatos (título, autores, visibilidad pública, interna o privada), los comentarios, los favoritos y el registro de las acciones de moderación. Es ideal para este caso porque maneja muy bien las relaciones entre tablas (un trabajo tiene varios autores, un usuario tiene muchos favoritos) y garantiza que los datos queden consistentes ante operaciones simultáneas. Además, gracias a sus extensiones cubre necesidades que normalmente requerirían motores adicionales:

- **pgvector**: permite guardar los vectores de los embeddings y resolver la mitad semántica del buscador y los "trabajos relacionados".
- **tsvector** (incluido de fábrica): implementa la búsqueda por palabras exactas o raíces, que aporta la otra mitad del ranking.
- **ltree**: modela la jerarquía Escuela → Carrera → Materia como un árbol, de modo que filtrar por una Escuela trae automáticamente todo lo que cuelga debajo.

Esto simplifica la arquitectura al evitar sumar un motor de búsqueda separado solo para eso.

**Tipo de licencia**
Libre y gratuito. Usa la PostgreSQL License, una licencia open source similar que permite uso comercial, modificación y redistribución sin costo. Las extensiones pgvector y ltree también son open source y gratuitas.

**Cómo conseguirlo**
Se descarga desde el sitio oficial: https://www.postgresql.org/download/. Hay instaladores para Windows, macOS y Linux, paquetes para las distribuciones más comunes (apt, yum, brew) e imágenes oficiales de Docker. Para uso local en desarrollo, lo más rápido es `docker run postgres` o instalar con el gestor de paquetes del sistema operativo. La extensión pgvector se descarga desde https://github.com/pgvector/pgvector y se habilita con un comando SQL (`CREATE EXTENSION vector`); ltree y tsvector ya vienen incluidas en la instalación estándar.

## Motor NoSQL: Redis

**Empresa/organización que lo provee**
Redis es desarrollado y mantenido por Redis Ltd., empresa fundada en 2011 con sede en Estados Unidos e Israel, junto con una amplia comunidad open source.

**Justificación de la elección**
Se usará como base auxiliar en memoria para todo lo que necesita responder muy rápido y no requiere persistencia estricta. En particular, sostendrá el autocompletado del buscador, donde cada tecla del usuario debe responderse en menos de un milisegundo, una latencia que PostgreSQL no puede garantizar. También guardará en caché los resultados de las consultas más populares, de modo que la primera búsqueda toca PostgreSQL y las siguientes leen directamente de Redis, descargando al motor principal. Por último, permite implementar de manera simple el rate limiting (limitar la cantidad de consultas por usuario en una ventana de tiempo) usando contadores con expiración automática. Su modelo clave-valor en memoria lo hace ideal para estos usos, donde perder los datos no es crítico porque siempre se pueden reconstruir desde PostgreSQL.

**Tipo de licencia**
Libre. Las versiones recientes se distribuyen bajo licencia RSALv2 / SSPLv1 / AGPLv3, todas gratuitas para el uso que requiere BUSCASAM. Existe además Redis Enterprise, una versión paga con funciones avanzadas de clustering y soporte que no son necesarias en este proyecto.

**Cómo conseguirlo**
Se descarga desde el sitio oficial: https://redis.io/download/. Hay paquetes para Linux, instalación con Homebrew en macOS e imagen oficial de Docker. Para uso local, lo más simple es `docker run redis` o instalar con el gestor de paquetes del sistema operativo.

## Diseño del Datawarehouse

### Arquitectura BI
La base operativa de BUSCASAM (PostgreSQL) está optimizada para responder consultas individuales del usuario en tiempo real (ver un trabajo, comentar, hacer una búsqueda), pero no se quiere mezclar la carga operativa con las consultas analíticas pesadas del tipo "¿cuáles fueron las áreas más buscadas el último cuatrimestre?" o "¿cómo evolucionó la cantidad de publicaciones por Escuela?". Para eso se monta un datawarehouse en una **instancia separada de PostgreSQL** (mismo motor, distinto servidor), con una arquitectura clásica en cuatro capas:

1. **Origen**: PostgreSQL operativo, donde viven los datos del día a día.
2. **Proceso ETL**: una tarea programada que se ejecuta una vez por día (de madrugada) extrae los datos nuevos o modificados del PostgreSQL operativo, los transforma al modelo dimensional y los carga en el datawarehouse. Se implementa con dbt orquestado mediante cron, una herramienta estándar de Linux para programar tareas.
3. **Datawarehouse (OLAP)**: una segunda instancia de PostgreSQL dedicada al análisis, con un esquema dimensional propio (`dwh.fact_*` y `dwh.dim_*`).
4. **Visualización**: Power BI, que se conecta al datawarehouse y permite a docentes y autoridades armar tableros e informes interactivos.

El flujo queda así:

```{=latex}
\vspace{6pt}
\begin{center}
\begin{tikzpicture}[
  font=\small\sffamily,
  box/.style={rectangle, rounded corners=4pt, draw=unsamblue!70, line width=0.7pt,
              fill=unsamblue!8, align=center, text=unsamblue, inner sep=6pt,
              minimum width=2.7cm, minimum height=1.4cm},
  caption/.style={font=\scriptsize\sffamily\color{unsamgray}, align=center},
  arrow/.style={-{Latex[length=2.5mm]}, line width=0.8pt, draw=unsamblue!60}
]
\node[box] (app) {\textbf{App}\\BUSCASAM\\\scriptsize\textit{(uso real)}};
\node[box, right=10mm of app] (oltp) {\textbf{PostgreSQL}\\\scriptsize\textit{(operativo)}};
\node[box, right=18mm of oltp] (dwh) {\textbf{PostgreSQL}\\DWH\\\scriptsize\textit{(analítico)}};
\node[box, right=10mm of dwh] (bi) {\textbf{Power BI}\\\scriptsize\textit{(tableros)}};

\draw[arrow] (app) -- (oltp);
\draw[arrow] (oltp) -- node[above, caption]{ETL diario}
                       node[below, caption]{(dbt + cron)} (dwh);
\draw[arrow] (bi) -- (dwh);
\end{tikzpicture}
\end{center}
\vspace{4pt}
```

### Motor Seleccionado: PostgreSQL (instancia DWH)
Se eligió **PostgreSQL** también para el datawarehouse, en una instancia distinta de la operativa. La justificación es práctica: el equipo ya domina PostgreSQL, no hay que aprender otro dialecto SQL ni montar una infraestructura paralela, los backups y el monitoreo se hacen con las mismas herramientas, y a la escala que maneja BUSCASAM (decenas de miles de eventos diarios) PostgreSQL responde sin problemas las consultas analíticas. Si en el futuro el volumen creciera mucho, el modelo dimensional y el ETL son lo suficientemente estándar como para poder migrar el DWH a un motor especializado sin rehacer todo el trabajo.

Para la **visualización** se usa **Power BI**, desarrollado por Microsoft. Permite conectar directamente a PostgreSQL, modelar relaciones entre tablas, crear medidas con DAX y publicar tableros que docentes y autoridades pueden consultar desde el navegador o la app de escritorio. Se eligió por su amplio uso institucional, su curva de aprendizaje suave para usuarios no técnicos y la disponibilidad de licencias educativas a través del programa Microsoft for Education al que UNSAM tiene acceso. La licencia es **paga** (Power BI Pro, ~10 USD/usuario/mes; Power BI Desktop para autoría es gratuito), aunque las licencias educativas suelen estar incluidas en los acuerdos institucionales.

### Modelado de Datos: Copo de Nieve
Se usa un modelado en **copo de nieve (snowflake)** en lugar de estrella, porque el dominio de BUSCASAM tiene una jerarquía natural que conviene mantener normalizada: Escuela → Carrera → Materia. En un esquema estrella tendríamos una única tabla `dim_area` con esos tres campos repetidos, lo que generaría redundancia y complicaría mantener los nombres consistentes si cambian. En copo de nieve, esa dimensión se descompone en tres tablas relacionadas (`dim_escuela`, `dim_carrera`, `dim_materia`), reflejando la jerarquía real de la universidad.

El modelo se compone de **tablas de hechos** (lo que se mide, eventos cuantificables) y **dimensiones** (el contexto que da sentido a esos hechos):

```{=latex}
\vspace{4pt}
\noindent\textbf{\color{factcolor}Tablas de hechos}\\[2pt]
\begin{tabularx}{\linewidth}{@{} >{\ttfamily\color{factcolor}}l X @{}}
\toprule
\normalfont\textbf{Tabla} & \textbf{Qué registra} \\
\midrule
fact\_busqueda      & Cada búsqueda realizada: query, usuario, fecha, área filtrada, cantidad de resultados y si el usuario hizo click. \\
fact\_visualizacion & Cada apertura de la página de detalle de un trabajo (usuario, documento, fecha). \\
fact\_publicacion   & Cada trabajo publicado en la plataforma (autor, fecha, tipo, área). \\
fact\_descarga      & Cada descarga de archivo (usuario, documento, fecha). \\
\bottomrule
\end{tabularx}

\vspace{14pt}
\noindent\textbf{\color{dimcolor}Dimensiones}\\[2pt]
\begin{tabularx}{\linewidth}{@{} >{\ttfamily\color{dimcolor}}l X @{}}
\toprule
\normalfont\textbf{Dimensión} & \textbf{Atributos / contexto que aporta} \\
\midrule
dim\_tiempo       & Granularidad temporal: día, mes, cuatrimestre y año. \\
dim\_usuario      & Datos del usuario; se enlaza con \texttt{dim\_rol} (estudiante / docente / invitado). Maneja historial con SCD~Tipo~2 cuando cambia el rol o la carrera. \\
dim\_documento    & Datos del trabajo; se enlaza con \texttt{dim\_tipo\_documento} (tesis, paper, TP, etc.). Maneja historial con SCD~Tipo~2 si cambia la materia del trabajo. \\
dim\_materia      & Materia donde se enmarca el trabajo, enlazada con \texttt{dim\_carrera} y ésta con \texttt{dim\_escuela}, formando la jerarquía académica normalizada. \\
\bottomrule
\end{tabularx}

\vspace{14pt}
\noindent\textbf{\color{unsamgray}Tabla puente}\\[2pt]
\begin{tabularx}{\linewidth}{@{} >{\ttfamily\color{unsamgray}}l X @{}}
\toprule
\normalfont\textbf{Tabla} & \textbf{Qué resuelve} \\
\midrule
bridge\_documento\_autor & Relación muchos-a-muchos entre documentos y autores (co-autoría). Cada fila lleva un \texttt{peso = 1/N} (N = cantidad de autores del documento) para que los análisis "publicaciones por usuario" no incurran en doble conteo. \\
\bottomrule
\end{tabularx}
\vspace{6pt}
```

Visualmente, el modelo en copo de nieve queda así (en rojo las tablas de hechos, en azul las dimensiones, en verde la jerarquía normalizada que le da el nombre, en gris la tabla puente para co-autoría):

```{=latex}
\vspace{4pt}
\begin{center}
\begin{tikzpicture}[
  font=\footnotesize\sffamily,
  fact/.style={rectangle, rounded corners=3pt, draw=factcolor, line width=0.7pt,
               fill=factcolor!10, align=center, text=factcolor, inner sep=4pt,
               minimum width=2.4cm, minimum height=0.9cm},
  dim/.style={rectangle, rounded corners=3pt, draw=dimcolor, line width=0.7pt,
              fill=dimcolor!10, align=center, text=dimcolor, inner sep=4pt,
              minimum width=2.4cm, minimum height=0.9cm},
  hier/.style={rectangle, rounded corners=3pt, draw=hierarchcolor, line width=0.7pt,
               fill=hierarchcolor!12, align=center, text=hierarchcolor!80!black, inner sep=4pt,
               minimum width=2.4cm, minimum height=0.9cm},
  bridge/.style={rectangle, rounded corners=3pt, draw=unsamgray, line width=0.7pt,
                 fill=unsamgray!10, align=center, text=unsamgray, inner sep=4pt,
                 minimum width=2.8cm, minimum height=0.9cm, dashed},
  link/.style={-, draw=gray!70, line width=0.5pt}
]
% Hechos (centro)
\node[fact] (fb) at (0, 1.4)   {fact\_busqueda};
\node[fact] (fv) at (0, 0.4)   {fact\_visualizacion};
\node[fact] (fp) at (0, -0.6)  {fact\_publicacion};
\node[fact] (fd) at (0, -1.6)  {fact\_descarga};

% Dimensiones (alrededor)
\node[dim]  (dt) at (-4.5, 1.4)   {dim\_tiempo};
\node[dim]  (du) at (-4.5, -0.6)  {dim\_usuario};
\node[dim]  (dr) at (-4.5, -1.8)  {dim\_rol};
\node[dim]  (dd) at ( 4.5, 1.0)   {dim\_documento};
\node[dim]  (dtd) at ( 4.5, -0.2) {dim\_tipo\_documento};

% Jerarquía (snowflake)
\node[hier] (dm) at ( 4.5, -1.4) {dim\_materia};
\node[hier] (dc) at ( 4.5, -2.5) {dim\_carrera};
\node[hier] (de) at ( 4.5, -3.6) {dim\_escuela};

% Bridge (co-autoría)
\node[bridge] (bda) at (0, -3.0) {bridge\_documento\_autor};

% Conexiones hecho-dim
\draw[link] (dt)  -- (fb);
\draw[link] (dt)  -- (fv);
\draw[link] (dt)  -- (fp);
\draw[link] (dt)  -- (fd);
\draw[link] (du)  -- (fb);
\draw[link] (du)  -- (fv);
\draw[link] (du)  -- (fd);
\draw[link] (dd)  -- (fv);
\draw[link] (dd)  -- (fd);
\draw[link] (dd)  -- (fp);
\draw[link] (dm)  -- (fp);
\draw[link] (dm)  -- (fb);

% Snowflake (jerarquía normalizada)
\draw[link] (du)  -- (dr);
\draw[link] (dd)  -- (dtd);
\draw[link] (dm)  -- (dc);
\draw[link] (dc)  -- (de);

% Bridge connections
\draw[link] (bda) -- (du);
\draw[link] (bda) -- (dd);

\end{tikzpicture}
\end{center}
\vspace{2pt}
```

Con este modelo se pueden responder preguntas como "trabajos publicados por Escuela en el último año", "queries más frecuentes por carrera" o "tasa de descarga por tipo de documento".

### Infraestructura usada: Diagramas y Máquinas
La separación física entre el sistema operativo y el analítico evita que las consultas pesadas de BI afecten la experiencia del usuario final. La arquitectura de máquinas queda:

```{=latex}
\vspace{6pt}
\begin{center}
\begin{tikzpicture}[
  font=\small\sffamily,
  box/.style={rectangle, rounded corners=4pt, draw=unsamblue!70, line width=0.7pt,
              fill=unsamblue!8, align=center, text=unsamblue, inner sep=5pt,
              minimum width=3cm, minimum height=1.1cm},
  user/.style={ellipse, draw=unsamgray, line width=0.7pt, fill=gray!10, align=center,
               inner sep=5pt, minimum width=3.4cm, minimum height=0.9cm},
  bi/.style={rectangle, rounded corners=4pt, draw=hierarchcolor!80, line width=0.7pt,
             fill=hierarchcolor!10, align=center, text=hierarchcolor!80!black, inner sep=5pt,
             minimum width=3cm, minimum height=1.1cm},
  arrow/.style={-{Latex[length=2.5mm]}, line width=0.7pt, draw=unsamblue!60},
  arrowlabel/.style={font=\scriptsize\sffamily\color{unsamgray}, align=center}
]

\node[user] (users) {Usuarios (web / mobile)};
\node[box, below=10mm of users] (app)
     {\textbf{VPS App}\\\scriptsize Nginx + backend BUSCASAM};

\node[box, below=18mm of app, xshift=-4.6cm] (oltp)
     {\textbf{PostgreSQL operativo}\\\scriptsize (+ pgvector) --- \textit{VPS Datos}};
\node[box, below=18mm of app] (redis)
     {\textbf{Redis}\\\scriptsize cache + autocomplete};
\node[box, below=18mm of app, xshift=4.6cm] (fs)
     {\textbf{Filesystem}\\\scriptsize PDFs / DOCX / ODT};

\node[box, below=22mm of oltp] (dwh)
     {\textbf{PostgreSQL DWH}\\\scriptsize \textit{VPS DWH}};
\node[bi, right=14mm of dwh] (bi)
     {\textbf{Power BI}\\\scriptsize Desktop / Service};

\draw[arrow] (users) -- node[arrowlabel, right]{HTTPS} (app);
\draw[arrow] (app.south) -- (oltp.north);
\draw[arrow] (app.south) -- (redis.north);
\draw[arrow] (app.south) -- (fs.north);
\draw[arrow] (oltp.south) -- node[arrowlabel, right, xshift=2pt]{ETL diario\\(dbt + cron)} (dwh.north);
\draw[arrow] (bi) -- node[arrowlabel, above]{queries\\analíticas} (dwh);

\end{tikzpicture}
\end{center}
\vspace{4pt}
```

**Máquinas necesarias** (mínimo viable):
- **VPS App** (4 vCPU, 8 GB RAM): corre Nginx, el backend de la aplicación y sirve los archivos.
- **VPS Datos** (4 vCPU, 16 GB RAM, SSD): corre el PostgreSQL operativo (con pgvector) y Redis. Se separa de la app para aislar el uso de recursos.
- **VPS DWH** (2 vCPU, 8 GB RAM): corre la segunda instancia de PostgreSQL dedicada al datawarehouse y el ETL programado con cron. Como las cargas se ejecutan una vez por día y las consultas son acotadas, no necesita gran capacidad sostenida.
- **Power BI**: no requiere VPS propio. Los analistas usan **Power BI Desktop** (Windows) para diseñar los tableros y los publican en **Power BI Service** (cloud de Microsoft), donde docentes y autoridades los consultan desde el navegador. La conexión al PostgreSQL DWH se hace mediante el **Power BI Gateway** instalado en una máquina con acceso al VPS DWH.

## Operaciones sobre el Datawarehouse

A continuación se ejemplifican las operaciones más relevantes sobre el datawarehouse de BUSCASAM, usando sintaxis estándar de PostgreSQL y el modelado en copo de nieve descrito antes. Todas las tablas se ubican en un esquema dedicado (`dwh`) dentro de la instancia DWH para mantenerlas separadas de cualquier otro objeto.

### Creación
La creación del esquema se ejecuta una sola vez, al desplegar el datawarehouse. Define las tablas de hechos y dimensiones con sus tipos, claves primarias, claves foráneas para garantizar consistencia y los índices que aceleran las consultas analíticas. Las dimensiones donde importa el historial (`dim_usuario`, `dim_documento`) llevan **clave subrogada** (`_sk`) además de la natural del operativo (`_bk`) y los campos `valid_from`, `valid_to`, `is_current` que sostienen la mecánica SCD Tipo 2.

```sql
CREATE SCHEMA IF NOT EXISTS dwh;

-- Jerarquía académica (snowflake)
CREATE TABLE dwh.dim_escuela (
    id_escuela INTEGER PRIMARY KEY,
    nombre     VARCHAR(200) NOT NULL
);

CREATE TABLE dwh.dim_carrera (
    id_carrera INTEGER PRIMARY KEY,
    id_escuela INTEGER NOT NULL REFERENCES dwh.dim_escuela(id_escuela),
    nombre     VARCHAR(200) NOT NULL
);

CREATE TABLE dwh.dim_materia (
    id_materia INTEGER PRIMARY KEY,
    id_carrera INTEGER NOT NULL REFERENCES dwh.dim_carrera(id_carrera),
    nombre     VARCHAR(200) NOT NULL
);

-- Tiempo
CREATE TABLE dwh.dim_tiempo (
    fecha        DATE PRIMARY KEY,
    dia          SMALLINT NOT NULL,
    mes          SMALLINT NOT NULL,
    cuatrimestre SMALLINT NOT NULL,
    anio         SMALLINT NOT NULL
);

-- Rol y usuario (SCD2 en id_rol e id_carrera)
CREATE TABLE dwh.dim_rol (
    id_rol INTEGER PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL  -- estudiante | docente | invitado
);

CREATE TABLE dwh.dim_usuario (
    id_usuario_sk INTEGER PRIMARY KEY,           -- surrogate (SCD2)
    id_usuario_bk INTEGER NOT NULL,              -- natural key del operativo; 0 = invitado
    id_rol        INTEGER NOT NULL REFERENCES dwh.dim_rol(id_rol),
    id_carrera    INTEGER REFERENCES dwh.dim_carrera(id_carrera),
    nombre        VARCHAR(200),
    email_hash    VARCHAR(64),
    valid_from    DATE NOT NULL,
    valid_to      DATE,
    is_current    BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX idx_dim_usuario_bk_current
    ON dwh.dim_usuario(id_usuario_bk, is_current);

-- Documento (SCD2 en id_materia)
CREATE TABLE dwh.dim_tipo_documento (
    id_tipo INTEGER PRIMARY KEY,
    nombre  VARCHAR(50) NOT NULL  -- tesis | paper | trabajo_practico | ...
);

CREATE TABLE dwh.dim_documento (
    id_documento_sk INTEGER PRIMARY KEY,         -- surrogate (SCD2)
    id_documento_bk INTEGER NOT NULL,            -- natural key del operativo
    id_tipo         INTEGER NOT NULL REFERENCES dwh.dim_tipo_documento(id_tipo),
    id_materia      INTEGER NOT NULL REFERENCES dwh.dim_materia(id_materia),
    titulo          VARCHAR(500) NOT NULL,
    fecha_alta      DATE NOT NULL,
    visibilidad     VARCHAR(20) NOT NULL,        -- publico | interno | privado
    valid_from      DATE NOT NULL,
    valid_to        DATE,
    is_current      BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX idx_dim_documento_bk_current
    ON dwh.dim_documento(id_documento_bk, is_current);

-- Bridge para co-autoría (resuelve M:N documento↔autor con peso = 1/N)
CREATE TABLE dwh.bridge_documento_autor (
    id_documento_sk INTEGER NOT NULL REFERENCES dwh.dim_documento(id_documento_sk),
    id_usuario_sk   INTEGER NOT NULL REFERENCES dwh.dim_usuario(id_usuario_sk),
    orden           SMALLINT NOT NULL,           -- 1 = autor principal
    peso            NUMERIC(5,4) NOT NULL,       -- 1/N evita doble conteo
    PRIMARY KEY (id_documento_sk, id_usuario_sk)
);

-- Hechos
CREATE TABLE dwh.fact_busqueda (
    id_busqueda              BIGSERIAL PRIMARY KEY,
    fecha                    DATE    NOT NULL REFERENCES dwh.dim_tiempo(fecha),
    id_usuario_sk            INTEGER NOT NULL REFERENCES dwh.dim_usuario(id_usuario_sk),
    -- Filtros aplicados por el usuario (nullables: solo se llena el nivel filtrado)
    id_escuela_filtro        INTEGER REFERENCES dwh.dim_escuela(id_escuela),
    id_carrera_filtro        INTEGER REFERENCES dwh.dim_carrera(id_carrera),
    id_materia_filtro        INTEGER REFERENCES dwh.dim_materia(id_materia),
    id_tipo_documento_filtro INTEGER REFERENCES dwh.dim_tipo_documento(id_tipo),
    fecha_desde_filtro       DATE,
    fecha_hasta_filtro       DATE,
    -- Medidas y atributos del hecho
    query_texto              TEXT    NOT NULL,
    cant_resultados          INTEGER NOT NULL,
    hizo_click               BOOLEAN NOT NULL,
    session_hash             VARCHAR(64)         -- segmenta sesiones anónimas
);

CREATE INDEX idx_fact_busqueda_fecha   ON dwh.fact_busqueda(fecha);
CREATE INDEX idx_fact_busqueda_materia ON dwh.fact_busqueda(id_materia_filtro);

CREATE TABLE dwh.fact_visualizacion (
    id_visualizacion BIGSERIAL PRIMARY KEY,
    fecha            DATE    NOT NULL REFERENCES dwh.dim_tiempo(fecha),
    id_usuario_sk    INTEGER NOT NULL REFERENCES dwh.dim_usuario(id_usuario_sk),
    id_documento_sk  INTEGER NOT NULL REFERENCES dwh.dim_documento(id_documento_sk)
);

CREATE INDEX idx_fact_visualizacion_fecha ON dwh.fact_visualizacion(fecha);
CREATE INDEX idx_fact_visualizacion_doc   ON dwh.fact_visualizacion(id_documento_sk);

CREATE TABLE dwh.fact_publicacion (
    id_publicacion  BIGSERIAL PRIMARY KEY,
    fecha           DATE    NOT NULL REFERENCES dwh.dim_tiempo(fecha),
    id_usuario_sk   INTEGER NOT NULL REFERENCES dwh.dim_usuario(id_usuario_sk),  -- uploader
    id_documento_sk INTEGER NOT NULL REFERENCES dwh.dim_documento(id_documento_sk),
    id_materia      INTEGER NOT NULL REFERENCES dwh.dim_materia(id_materia)
);

CREATE INDEX idx_fact_publicacion_fecha   ON dwh.fact_publicacion(fecha);
CREATE INDEX idx_fact_publicacion_materia ON dwh.fact_publicacion(id_materia);

CREATE TABLE dwh.fact_descarga (
    id_descarga     BIGSERIAL PRIMARY KEY,
    fecha           DATE    NOT NULL REFERENCES dwh.dim_tiempo(fecha),
    id_usuario_sk   INTEGER NOT NULL REFERENCES dwh.dim_usuario(id_usuario_sk),
    id_documento_sk INTEGER NOT NULL REFERENCES dwh.dim_documento(id_documento_sk)
);

CREATE INDEX idx_fact_descarga_fecha ON dwh.fact_descarga(fecha);
CREATE INDEX idx_fact_descarga_doc   ON dwh.fact_descarga(id_documento_sk);

-- Control ETL
CREATE TABLE dwh.etl_watermark (
    tabla_origen     VARCHAR(100) PRIMARY KEY,
    ultimo_procesado TIMESTAMP NOT NULL,
    ultima_corrida   TIMESTAMP NOT NULL
);
```

**ETL — Creación**: el script de inicialización del ETL se ejecuta una única vez en el despliegue. Lo primero que hace es conectarse a la instancia DWH de PostgreSQL y correr todos los `CREATE TABLE` (idempotentes con `CREATE TABLE IF NOT EXISTS`) para dejar el esquema vacío listo. A continuación realiza una **carga inicial completa**: extrae todos los datos históricos del PostgreSQL operativo (búsquedas, publicaciones, descargas, visualizaciones, usuarios, documentos y el árbol de áreas), los transforma al modelo dimensional (genera las claves subrogadas, arma `dim_tiempo` con un rango de fechas, calcula `peso = 1/N` para el bridge de co-autoría, inserta la fila sentinel `id_usuario_bk = 0` que registrará las búsquedas de invitados anónimos) y los inserta en bloque en las tablas recién creadas. Desde ese momento, el ETL pasa a modo incremental.

### Eliminación
La eliminación es poco frecuente en un datawarehouse porque el principio general es preservar el histórico. Solo se borran datos cuando un trabajo es eliminado por moderación o por pedido del autor (cumplimiento legal, derecho al olvido), o cuando se purgan datos muy antiguos por política de retención. Como las dimensiones SCD2 trabajan con clave subrogada, las eliminaciones puntuales se resuelven contra `id_documento_sk` o vía lookup desde la natural key (`id_documento_bk`).

```sql
-- Borrar hechos de un documento específico (resolviendo desde la natural key)
DELETE FROM dwh.fact_publicacion
WHERE id_documento_sk IN (
    SELECT id_documento_sk
    FROM dwh.dim_documento
    WHERE id_documento_bk = 4521
);

-- Purgar búsquedas antiguas por política de retención
DELETE FROM dwh.fact_busqueda
WHERE fecha < '2020-01-01';
```

En PostgreSQL `DELETE` es una operación rápida y transaccional, por lo que puede ejecutarse cuando haga falta sin precauciones especiales más allá de envolverlo en una transacción.

### Inserción
La inserción ocurre todos los días con la corrida del ETL. Se agregan al datawarehouse las filas nuevas que aparecieron en el PostgreSQL operativo desde la última corrida.

```sql
INSERT INTO dwh.fact_busqueda
    (fecha, id_usuario_sk, id_materia_filtro,
     query_texto, cant_resultados, hizo_click)
VALUES
    ('2026-05-04', 8102, 318, 'redes neuronales medicina', 27, TRUE),
    ('2026-05-04', 8102, 318, 'deep learning diagnóstico', 19, TRUE),
    ('2026-05-04', 5471,  45, 'foucault biopolitica',       8, FALSE);
```

**ETL — Inserción**: el ETL guarda en una tabla de control (`dwh.etl_watermark`) la fecha/hora del último registro procesado por cada tabla. En cada corrida, **extrae** del PostgreSQL operativo solo las filas con `created_at > watermark` (carga incremental, mucho más liviana que una carga completa). **Transforma** cada fila: traduce IDs, normaliza textos, calcula campos derivados (por ejemplo `hizo_click` se deriva de si la búsqueda generó algún registro en la tabla de clicks del operativo) y **resuelve las claves subrogadas vigentes** para las dimensiones SCD2, buscando en `dim_usuario` y `dim_documento` la fila con `is_current = TRUE` que corresponde a la natural key del operativo. Para los documentos nuevos también recalcula `bridge_documento_autor` con `peso = 1/N` según la cantidad de co-autores. Finalmente, **carga** las filas en el DWH con un `INSERT` en bloque dentro de una transacción, lo que garantiza que si algo falla a mitad de la carga el datawarehouse queda en su estado anterior. Al terminar, actualiza el watermark con la fecha del último registro insertado, dejando todo listo para la corrida del día siguiente.

### Actualización
Las actualizaciones son raras en un datawarehouse, pero existen casos válidos: corregir una dimensión cuando cambia un dato (por ejemplo, una carrera que se renombra) o reflejar correcciones tardías sobre los hechos (un documento cuyo área fue cambiada por el autor después de cargado).

```sql
UPDATE dwh.dim_carrera
SET nombre = 'Licenciatura en Ciencias de Datos'
WHERE id_carrera = 27;

UPDATE dwh.fact_publicacion
SET id_materia = 412
WHERE id_documento = 8891;
```

**ETL — Actualización**: el ETL detecta cambios en el PostgreSQL operativo comparando la columna `updated_at` de cada tabla contra el watermark. Cuando encuentra una fila modificada, decide cómo aplicarla según la política definida para ese campo:

- **SCD Tipo 1** (pisar sin historial): cuando el cambio no afecta análisis histórico, se ejecuta un `UPDATE` que sobrescribe el valor anterior. Aplica a `dim_escuela.nombre`, `dim_carrera.nombre`, `dim_materia.nombre`, `dim_tipo_documento.nombre` y `dim_documento.visibilidad` — son cambios cosméticos o no analíticos.
- **SCD Tipo 2** (insertar versión nueva, marcar la anterior como histórica): cuando importa preservar a qué valor pertenecía la fila en el momento del hecho. Aplica a `dim_documento.id_materia` (si un trabajo cambia de área, queremos saber a qué área pertenecía cuando fue buscado o descargado), `dim_usuario.id_carrera` (un estudiante puede cambiar de carrera) y `dim_usuario.id_rol` (un estudiante que se gradúa y vuelve como docente). La operación es: `UPDATE` cerrando la fila vigente (`valid_to = hoy`, `is_current = FALSE`) seguido de `INSERT` de la nueva versión con un `id_subrogado` nuevo. Los hechos previos siguen apuntando al subrogado anterior y los nuevos al actual.
- **Para hechos**: solo se actualizan si hubo una corrección genuina; en general se prefieren *contra-asientos* (insertar una fila que cancela la anterior) para preservar la trazabilidad.

PostgreSQL aplica los `UPDATE` de forma transaccional e inmediata, por lo que el ETL puede confirmar el resultado en la misma operación y avanzar.

### Búsquedas
Las consultas analíticas son lo que finalmente justifica todo el pipeline. Se ejecutan desde Power BI (que las traduce a SQL al conectar al DWH) o directamente con SQL.

**Búsqueda por una clave** (filtra por una sola dimensión):

```sql
SELECT count(*) AS total_busquedas
FROM dwh.fact_busqueda
WHERE fecha BETWEEN '2026-03-01' AND '2026-07-31';
```

Devuelve cuántas búsquedas hubo durante el primer cuatrimestre de 2026. PostgreSQL aprovecha el índice `idx_fact_busqueda_fecha` para leer solo el rango de fechas relevante, sin escanear toda la tabla.

**Búsqueda por dos claves** (cruza dos dimensiones, típico caso BI):

```sql
SELECT
    e.nombre AS escuela,
    t.cuatrimestre,
    count(*) AS total_publicaciones
FROM dwh.fact_publicacion f
JOIN dwh.dim_materia  m ON f.id_materia  = m.id_materia
JOIN dwh.dim_carrera  c ON m.id_carrera  = c.id_carrera
JOIN dwh.dim_escuela  e ON c.id_escuela  = e.id_escuela
JOIN dwh.dim_tiempo   t ON f.fecha       = t.fecha
WHERE t.anio = 2026
GROUP BY e.nombre, t.cuatrimestre
ORDER BY e.nombre, t.cuatrimestre;
```

Devuelve la cantidad de trabajos publicados por Escuela y por cuatrimestre durante 2026. Los `JOIN` en cascada recorren la jerarquía del copo de nieve (materia → carrera → escuela), y el `GROUP BY` agrega los hechos por las dos claves elegidas. PostgreSQL resuelve este tipo de consulta usando los índices de las claves foráneas y los planes de ejecución optimizados para joins en estrella/copo, devolviendo el resultado en tiempo aceptable para los volúmenes de BUSCASAM.

## Minería de Datos

Sobre el datawarehouse se montan dos funciones de minería de datos implementadas como funciones almacenadas (`CREATE FUNCTION`) en PostgreSQL: una de **segmentación** (no supervisada, agrupa usuarios por su comportamiento) y otra de **predicción** (supervisada, estima descargas futuras de un documento). Ambas son "dinámicas" en el sentido de que reciben parámetros por consulta (período, cantidad de clusters, horizonte de predicción) y se recalculan en el momento, sin depender de tablas pre-computadas. Esto permite que Power BI las invoque como cualquier otra consulta SQL y que el resultado refleje siempre el estado más reciente del DWH.

### Función Dinámica de Segmentación

Agrupa a los usuarios en `k` clusters según su patrón de uso de la plataforma (búsquedas, visualizaciones, descargas y publicaciones) durante un período dado. Permite responder preguntas como "¿qué perfiles de uso existen entre los estudiantes?" o "¿hay un grupo muy activo que descarga mucho pero nunca publica?". Internamente aplica **K-means** ejecutado vía `plpython3u` con scikit-learn, una combinación habitual cuando se quiere acceder a algoritmos de ML sin sacar los datos de PostgreSQL.

```sql
CREATE EXTENSION IF NOT EXISTS plpython3u;

CREATE OR REPLACE FUNCTION dwh.segmentar_usuarios(
    p_fecha_desde DATE,
    p_fecha_hasta DATE,
    p_k           INTEGER DEFAULT 4
)
RETURNS TABLE (
    id_usuario_sk      INTEGER,
    cluster_id         INTEGER,
    n_busquedas        INTEGER,
    n_visualizaciones  INTEGER,
    n_descargas        INTEGER,
    n_publicaciones    INTEGER
)
LANGUAGE plpython3u AS $$
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler
import numpy as np

q = plpy.prepare("""
    SELECT u.id_usuario_sk,
           COALESCE(b.n, 0) AS nb,
           COALESCE(v.n, 0) AS nv,
           COALESCE(d.n, 0) AS nd,
           COALESCE(p.n, 0) AS np_pub
    FROM dwh.dim_usuario u
    LEFT JOIN (SELECT id_usuario_sk, count(*) n FROM dwh.fact_busqueda
               WHERE fecha BETWEEN $1 AND $2 GROUP BY 1) b USING (id_usuario_sk)
    LEFT JOIN (SELECT id_usuario_sk, count(*) n FROM dwh.fact_visualizacion
               WHERE fecha BETWEEN $1 AND $2 GROUP BY 1) v USING (id_usuario_sk)
    LEFT JOIN (SELECT id_usuario_sk, count(*) n FROM dwh.fact_descarga
               WHERE fecha BETWEEN $1 AND $2 GROUP BY 1) d USING (id_usuario_sk)
    LEFT JOIN (SELECT id_usuario_sk, count(*) n FROM dwh.fact_publicacion
               WHERE fecha BETWEEN $1 AND $2 GROUP BY 1) p USING (id_usuario_sk)
    WHERE u.is_current AND u.id_usuario_bk <> 0
""", ["date", "date"])
rows = plpy.execute(q, [p_fecha_desde, p_fecha_hasta])

if len(rows) < p_k:
    plpy.error("usuarios activos insuficientes en el periodo para %d clusters" % p_k)

ids = [r["id_usuario_sk"] for r in rows]
X   = np.array([[r["nb"], r["nv"], r["nd"], r["np_pub"]] for r in rows], dtype=float)
X_std  = StandardScaler().fit_transform(X)
labels = KMeans(n_clusters=p_k, n_init=10, random_state=42).fit_predict(X_std)

return [
    {"id_usuario_sk":     ids[i],
     "cluster_id":        int(labels[i]),
     "n_busquedas":       int(X[i, 0]),
     "n_visualizaciones": int(X[i, 1]),
     "n_descargas":       int(X[i, 2]),
     "n_publicaciones":   int(X[i, 3])}
    for i in range(len(rows))
]
$$;
```

**Uso**: la función devuelve una tabla, así que se invoca como cualquier otra fuente de datos y se puede cruzar con las dimensiones del DWH. Por ejemplo, para ver el perfil promedio de cada cluster durante el primer cuatrimestre de 2026:

```sql
SELECT
    cluster_id,
    count(*)                      AS usuarios,
    round(avg(n_busquedas))       AS busquedas_prom,
    round(avg(n_visualizaciones)) AS visualizaciones_prom,
    round(avg(n_descargas))       AS descargas_prom,
    round(avg(n_publicaciones))   AS publicaciones_prom
FROM dwh.segmentar_usuarios('2026-03-01', '2026-07-31', 4)
GROUP BY cluster_id
ORDER BY cluster_id;
```

Un resultado típico identifica perfiles como **"lectores pasivos"** (muchas visualizaciones, pocas descargas, cero publicaciones), **"investigadores activos"** (alto en todas las métricas), **"buscadores ocasionales"** (búsquedas esporádicas sin acción posterior) y **"autores"** (al menos una publicación). Estos segmentos alimentan tableros de Power BI con la evolución de cada grupo y permiten al equipo de la plataforma decidir, por ejemplo, dónde invertir esfuerzo de UX (¿convertir más "lectores pasivos" en "autores"?). Cambiando `p_k` o la ventana de fechas, la misma función sirve para explorar segmentaciones más finas (k=6) o comparar cuatrimestres entre sí sin tocar el código.

### Función Dinámica de Predicción

Predice cuántas descargas recibirá un documento en los próximos `p_dias_horizonte` días, a partir de la serie histórica de descargas acumuladas. Se implementa con **regresión lineal** sobre la curva acumulada usando los agregados estadísticos nativos de PostgreSQL (`regr_slope`, `regr_intercept`, `regr_r2`), sin extensiones adicionales. La regresión lineal alcanza para esta tarea porque, en el ámbito académico, la curva de descargas de un trabajo tiende a ser aproximadamente lineal después del pico inicial de visibilidad.

```sql
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
        RAISE EXCEPTION 'historia insuficiente: se requieren al menos 7 días con descargas (hay %)', COALESCE(v_dias, 0);
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
```

**Uso**: se llama indicando la clave natural del documento (la del operativo) y el horizonte en días. Por ejemplo, para estimar cuántas descargas tendrá el trabajo `id_documento_bk = 8891` al cabo de 60 días:

```sql
SELECT *
FROM dwh.predecir_descargas(8891, 60);
```

Devuelve cuatro columnas: las descargas acumuladas hasta hoy, las descargas estimadas al cabo del horizonte, el coeficiente de determinación `r²` (qué tan bien la recta ajusta la serie, entre 0 y 1) y los días de historia disponibles. Un `r²` cercano a 1 indica que el ritmo de descargas es estable y la predicción es confiable; uno bajo indica que el documento tiene un patrón irregular y la estimación debe tomarse con cautela. La función se expone en el perfil del autor ("este trabajo proyecta ~120 descargas el próximo mes") y la usa el equipo de comunicación de la plataforma para detectar trabajos con tendencia creciente que conviene destacar en la página principal. Variando `p_dias_horizonte` se obtienen estimaciones a corto, mediano o largo plazo sin modificar la función.
