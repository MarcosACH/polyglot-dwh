# Redis - Demo NoSQL de BUSCASAM

Demo del motor NoSQL del TP. Levanta una instancia local de **Redis Stack** (Redis + RediSearch + RedisInsight) en Docker y muestra tres casos de uso del sistema BUSCASAM:

1. **Autocompletado** del buscador (`FT.SUGADD` / `FT.SUGGET`).
2. **Blacklist de JWT** para logout (`SET` con TTL).
3. **Rate limiting** por usuario (`INCR` + `EXPIRE`, fixed window).

> La demo es independiente del DWH de Supabase: los datos son sinteticos y viven solo en Redis. No requiere conexion al PostgreSQL operativo ni al DWH.

---

## 1. Pre-requisitos

- **Docker Desktop** (Windows / macOS) o **Docker Engine + Compose plugin** (Linux). Probado con Docker 24+.
- Puertos libres en `localhost`: **6379** (Redis) y **8001** (RedisInsight).
- (Opcional, para el seed) **Python 3.10+** con `pip install redis`.

Verificar:

```bash
docker --version
docker compose version
```

---

## 2. Levantar la instancia

Desde la raiz del repo:

```bash
cd nosql
docker compose up -d
```

Compose levanta un solo servicio (`redis`) basado en la imagen `redis/redis-stack:latest`. La imagen ya incluye:

- **Redis 7** como motor base.
- **RediSearch** (modulo con `FT.SUGGET` y full-text).
- **RedisInsight** embebido (UI web en el puerto 8001).

Configuracion aplicada via `REDIS_ARGS`:

| Flag                              | Que hace                                              |
|-----------------------------------|-------------------------------------------------------|
| `--appendonly yes`                | Persistencia AOF para que la demo sobreviva reinicios |
| `--maxmemory 256mb`               | Limite de memoria (la demo no llega ni cerca)         |
| `--maxmemory-policy allkeys-lru`  | Si se llena, evicta las claves menos usadas           |

Verificar que arranco bien:

```bash
docker compose ps
docker compose logs redis | tail -20
docker compose exec redis redis-cli ping     # -> PONG
```

---

## 3. Abrir RedisInsight (visualizador)

1. Abrir <http://localhost:8001> en el navegador.
2. La primera vez pide aceptar terminos; aceptar y seguir.
3. Agregar una base con estos datos (`+ Add Redis database` -> `Add Database Manually`):

   | Campo          | Valor              |
   |----------------|--------------------|
   | Host           | `127.0.0.1`        |
   | Port           | `6379`             |
   | Database Alias | `buscasam-demo`    |
   | Username       | (vacio)            |
   | Password       | (vacio)            |

4. Click en `Add Database` -> abrir la base.

Desde la UI se pueden explorar las claves, ejecutar comandos en el `Workbench` y ver el grafico de uso de memoria. Util para mostrar en clase.

---

## 4. Conectarse por CLI

Equivalente a `psql` para PostgreSQL. Util para ejecutar los pasos de las demos:

```bash
docker compose exec redis redis-cli
```

Dentro del prompt `127.0.0.1:6379>`:

```redis
PING
INFO server
DBSIZE
KEYS *
```

Salir con `exit`.

---

## 5. Cargar datos sinteticos (seed)

El script de seed vive en `seed/` y depende de `redis-py` y `PyJWT`. Recomendado correrlo en un virtualenv para no tocar el Python del sistema:

```bash
# Desde redis/
cd seed
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python seed.py
```

Salida esperada:

```
[ok] conectado a redis://localhost:6379
[autocomplete] 50 sugerencias cargadas en 'autocomplete:queries'
[sessions] 5 sesiones activas (TTL 3600s)
[jwt] revocado jti=demo-jti-001 (TTL 1800s)  token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpX...
[ratelimit] rl:1002:YYYYMMDDHHMM = 28 (limite 30/min, TTL 60s)
[done] total de claves en la base: 8
```

El script carga:

- **50 queries** para el autocompletado (con scores reflejando popularidad).
- **5 sesiones** activas (hashes con TTL de 1 hora).
- **1 JWT pre-revocado** para demostrar la blacklist (TTL 30 min).
- **1 contador de rate limit** pre-cargado a 28/30 para que en la demo el request 31 sea el bloqueado.

> Si Redis corre en otra maquina o puerto, el script toma `REDIS_HOST` y `REDIS_PORT` del entorno:
> `REDIS_HOST=otro REDIS_PORT=6380 .venv/bin/python seed.py`

Verificacion rapida (en `redis-cli`):

```redis
FT.SUGGET autocomplete:queries "rede" MAX 5
EXISTS jwt:blacklist:demo-jti-001
KEYS rl:*
DBSIZE
```

`DBSIZE` deberia devolver `8` (1 suggestion dict + 5 sesiones + 1 blacklist + 1 rate limit).

El seed es **idempotente**: se puede correr varias veces y siempre deja el mismo estado (el contador de rate limit se recalcula con el minuto actual).

---

## 6. Demos

Cada demo tiene su propio paso a paso:

| Demo                | Archivo                                  | Comandos clave                              |
|---------------------|------------------------------------------|---------------------------------------------|
| Autocompletado      | [`demo/01_autocomplete.md`](demo/01_autocomplete.md) | `FT.SUGADD`, `FT.SUGGET`              |
| JWT blacklist       | [`demo/02_jwt_blacklist.md`](demo/02_jwt_blacklist.md) | `SET ... EX`, `EXISTS`, `TTL`        |
| Rate limiting       | [`demo/03_rate_limit.md`](demo/03_rate_limit.md)       | `INCR`, `EXPIRE`, `TTL`              |

Todos los pasos se pueden ejecutar tanto desde `redis-cli` como desde el Workbench de RedisInsight (recomendado para presentar en pantalla, porque resalta sintaxis y muestra el resultado formateado).

---

## 7. Apagar y limpiar

```bash
# Apagar sin perder datos (vuelve a arrancar con todo)
docker compose down

# Apagar y borrar todo (estado, AOF, etc.)
docker compose down -v
```

El volumen `redis-data` guarda el AOF, asi que parar y arrancar de nuevo conserva las claves cargadas por el seed.

---

## 8. Resolucion de problemas

| Sintoma                                    | Causa probable                                    | Solucion                                                  |
|--------------------------------------------|---------------------------------------------------|-----------------------------------------------------------|
| `Error: bind: address already in use`      | Hay otro Redis o algo en 6379/8001                | Cambiar el puerto en `docker-compose.yml` o parar el otro |
| RedisInsight no abre en 8001               | El healthcheck aun no dio OK                      | Esperar 10-20s y reintentar; ver `docker compose logs`    |
| `FT.SUGGET` -> `unknown command`           | La imagen no es Redis Stack                       | Verificar `image: redis/redis-stack:latest` en compose    |
| Las claves desaparecen tras `compose down` | Volumen no montado / corrieron `down -v`          | Verificar `volumes:` en compose y no usar `-v` para parar |

---

## Referencias

- Redis Stack: <https://redis.io/docs/latest/operate/oss_and_stack/install/install-stack/docker/>
- RediSearch (autocompletado): <https://redis.io/docs/latest/commands/ft.sugget/>
- RedisInsight: <https://redis.io/docs/latest/operate/redisinsight/>
- Cliente Python: <https://redis.readthedocs.io/>
