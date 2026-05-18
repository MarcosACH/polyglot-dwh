# Setup Supabase - Guia operativa

Esta guia describe como **desplegar y mantener** el DWH de BUSCASAM sobre Supabase.
Cubre desde la instalacion de la CLI hasta el flujo diario de migraciones y carga de datos.

---

## 1. Pre-requisitos

### 1.1 Supabase CLI

**Windows** (PowerShell):

```powershell
# Opcion A - scoop (recomendado)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
irm get.scoop.sh | iex
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase

# Opcion B - winget
winget install Supabase.CLI

# Opcion C - binario directo
# Descargar desde https://github.com/supabase/cli/releases y agregar al PATH
```

**macOS / Linux**:

```bash
brew install supabase/tap/supabase            # macOS
# o
curl -fsSL https://supabase.com/install.sh | sh   # Linux
```

Verificar:

```powershell
supabase --version
```

### 1.2 Datos del proyecto Supabase

- **project-ref**: ultimo segmento de la URL del dashboard.
  `https://supabase.com/dashboard/project/<PROJECT-REF>`

---

## 2. Setup inicial (una sola vez por persona)

```powershell
# Posicionarse en la raiz del repo
cd "C:\ruta\al\repo\Bases de Datos"

# Autenticarse (abre navegador)
supabase login

# Vincular al proyecto remoto (te va a pedir la DB password)
supabase link --project-ref <PROJECT-REF>
```

Despues del `link`, la CLI guarda el estado en `supabase/.temp/` (ignorado por git).
Cada miembro del equipo corre `supabase link` una vez en su maquina.

---

## 3. Aplicar migrations al remoto

```powershell
# Ver migrations pendientes
supabase migration list

# Aplicar todas las pendientes
supabase db push
```

`db push` aplica solo las migrations que aun no estan en la tabla `supabase_migrations.schema_migrations` del remoto. Es seguro correrlo multiples veces.

### Migrations incluidas

| Archivo                                  | Contenido                                                 |
|------------------------------------------|-----------------------------------------------------------|
| `supabase/migrations/0001_dwh_schema.sql` | Schema `dwh` completo: 16 tablas + indices                |
| `supabase/migrations/0002_dwh_functions.sql` | Funcion `predecir_descargas` (plpgsql, Supabase-compatible) |

---

## 4. Cargar datos sinteticos (seed)

> **Importante**: `supabase db push` **NO** ejecuta `seed.sql`. La CLI solo lo corre automaticamente con `supabase db reset` (modo local). Para el remoto hay que cargarlo manualmente.

### Opcion A - SQL Editor del dashboard (la mas simple)

1. Abrir `supabase/seed.sql` en el editor local, copiar todo el contenido.
2. Dashboard -> SQL Editor -> New query -> pegar -> Run.
3. Esperar ~30-60s.

### Opcion B - psql (si esta instalado)

```powershell
# Connection string: Dashboard -> Project Settings -> Database -> Connection string (URI)
psql "postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres" `
    -f supabase/seed.sql
```

### Verificacion

```sql
SELECT
  (SELECT count(*) FROM dwh.dim_escuela)        AS escuelas,
  (SELECT count(*) FROM dwh.dim_carrera)        AS carreras,
  (SELECT count(*) FROM dwh.dim_materia)        AS materias,
  (SELECT count(*) FROM dwh.dim_tiempo)         AS dias,
  (SELECT count(*) FROM dwh.dim_usuario)        AS usuarios,
  (SELECT count(*) FROM dwh.dim_documento)      AS documentos,
  (SELECT count(*) FROM dwh.fact_busqueda)      AS busquedas,
  (SELECT count(*) FROM dwh.fact_visualizacion) AS visualizaciones,
  (SELECT count(*) FROM dwh.fact_publicacion)   AS publicaciones,
  (SELECT count(*) FROM dwh.fact_descarga)      AS descargas,
  (SELECT count(*) FROM dwh.fact_favorito)      AS favoritos,
  (SELECT count(*) FROM dwh.fact_comentario)    AS comentarios;
```

Volumenes esperados:

| Tabla                 | Filas  |
|-----------------------|--------|
| dim_escuela           | 5      |
| dim_carrera           | 30     |
| dim_materia           | 300    |
| dim_tiempo            | 1096   |
| dim_usuario           | 2051   |
| dim_documento         | 5100   |
| fact_busqueda         | 50000  |
| fact_visualizacion    | 30000  |
| fact_publicacion      | 5000   |
| fact_descarga         | 10000  |
| fact_favorito         | 8000   |
| fact_comentario       | 4000   |

---

## 5. Workflow: agregar una nueva migration

```powershell
# 1. Crear archivo vacio (genera supabase/migrations/<timestamp>_<nombre>.sql)
supabase migration new agregar_dim_X

# 2. Editar el archivo recien creado y escribir el SQL
code supabase/migrations/<timestamp>_agregar_dim_X.sql

# 3. (Opcional) Revisar pendientes
supabase migration list

# 4. Aplicar al remoto
supabase db push

# 5. Commit + push a GitHub
git add supabase/migrations/
git commit -m "agregar dim X"
git push
```

### Convenciones

- **Nombres descriptivos** en snake_case: `agregar_indice_visualizacion`, `corregir_fk_documento`.
- **Una migration = un cambio logico**. Mas chicas son mas faciles de revertir y revisar.
- **No editar migrations ya aplicadas en el remoto**. Si necesitas corregir algo, crea una nueva migration que arregle el problema.
- Si la migration falla, el push aborta y la migration **no** queda marcada como aplicada. Se corrige el archivo y se vuelve a correr `supabase db push`.

---

## 6. Funcion opcional: segmentacion de usuarios

`supabase/optional/segmentar_usuarios_plpython.sql` implementa K-means sobre el perfil de uso de cada usuario. Requiere la extension `plpython3u`, **no disponible en Supabase Cloud**.

Solo aplicable en una instancia self-hosted de PostgreSQL con `postgresql-plpython3-XX` y scikit-learn instalados. Para correrla:

```bash
psql "postgresql://<user>:<pass>@<host>:5432/<db>" -f supabase/optional/segmentar_usuarios_plpython.sql
```

Para el TP alcanza con `predecir_descargas` (que si esta desplegada en Supabase).

---

## Referencias

- Supabase CLI: <https://supabase.com/docs/guides/cli>
- Supabase migrations: <https://supabase.com/docs/guides/cli/local-development#database-migrations>
- DBML syntax: <https://dbml.dbdiagram.io/docs>
