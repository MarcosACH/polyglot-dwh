# Demo Redis — BUSCASAM (5 min)

> **Hilo conductor**: seguimos un día en BUSCASAM. Una estudiante busca papers, cierra sesión, y después un bot intenta saturar la API. Redis aparece en los tres momentos donde Postgres no llega.

---

## 0. Setup (antes de empezar)

Ya levantado y seedeado. Verificar:

```bash
cd nosql
docker compose ps              # buscasam-redis (healthy)
docker compose exec redis redis-cli DBSIZE   # -> 8
```

Abrir **RedisInsight** en <http://localhost:8001> en una pestaña (lo usamos para mostrar las claves en vivo).

Abrir también la CLI en otra terminal:

```bash
docker compose exec redis redis-cli
```

---

## 1. Ana tipea en el buscador (autocompletado) — ~90 s

> Ana entra a BUSCASAM. Quiere papers sobre redes neuronales. Empieza a tipear **"rede"**. Cada tecla es una request. Postgres con `ILIKE` puede tardar decenas de ms y bloquear el frontend — Redis devuelve en sub-milisegundo.

**Estructura**: un solo "suggestion dictionary" de RediSearch (`autocomplete:queries`).

```redis
FT.SUGLEN autocomplete:queries
```

→ `50` (sugerencias pre-cargadas).

```redis
FT.SUGGET autocomplete:queries "rede" MAX 5
```

→ devuelve **ordenado por popularidad**, no alfabéticamente:

```
1) "redes neuronales"
2) "redes neuronales convolucionales"
3) "redes neuronales recurrentes"
4) "redes sociales análisis"
5) "redes complejas"
```

**Qué decir**: el score interno (popularidad) decide el orden. Lo vemos:

```redis
FT.SUGGET autocomplete:queries "rede" MAX 5 WITHSCORES
```

**Bonus typo** — Ana se equivoca y tipea `"machne"`:

```redis
FT.SUGGET autocomplete:queries "machne" MAX 5            # vacío
FT.SUGGET autocomplete:queries "machne" MAX 5 FUZZY      # matchea "machine ..."
```

→ `FUZZY` permite 1 edit de Levenshtein. Resuelve typos sin código extra.

**Cierre de la demo**: cada vez que alguien hace click en una sugerencia, sumamos popularidad con `FT.SUGADD ... INCR`. Así el ranking aprende solo.

---

## 2. Ana cierra sesión (JWT blacklist) — ~90 s

> Ana termina y hace logout. Su JWT todavía es válido 30 min más (así se firmó). Hay que **invalidarlo ya**. La solución: una blacklist en Redis con TTL = lo que le quedaba al token.

**Estructura**: una clave por token revocado, con TTL.

```redis
KEYS jwt:blacklist:*
```

→ `jwt:blacklist:demo-jti-001` (cargado en el seed).

**Chequeo en cada request autenticado** (lo que hace la app antes de aceptar el JWT):

```redis
EXISTS jwt:blacklist:demo-jti-001    # 1 -> rechazar
EXISTS jwt:blacklist:cualquier-otro  # 0 -> aceptar
```

→ `EXISTS` es **O(1)**. No importa cuántos tokens haya en la lista.

**Cuánto le falta**:

```redis
TTL jwt:blacklist:demo-jti-001       # baja sola, segundo a segundo
```

**Demo de la autolimpieza** — creamos uno con TTL corto:

```redis
SET jwt:blacklist:efimero "demo" EX 5
EXISTS jwt:blacklist:efimero         # 1
```

Esperar 6 s.

```redis
EXISTS jwt:blacklist:efimero         # 0
```

→ **Redis borra solo**, sin cron, sin job. En Postgres habría que correr un cleanup periódico.

---

## 3. Llega un bot (rate limiting) — ~90 s

> Después entra un bot que dispara 100 búsquedas por segundo desde la cuenta de un usuario. Para frenarlo: **30 req/min por usuario**. El 31 se rechaza con HTTP 429.

**Estructura**: contador por `(usuario, minuto)`, con TTL 60 s.

```redis
KEYS rl:*
```

→ `rl:1002:<YYYYMMDDHHMM>` (seedeado en 28).

```redis
GET rl:1002:<minuto>     # 28
TTL rl:1002:<minuto>     # ~60
```

> En vivo: copiar la clave exacta que devuelve `KEYS`. Cambia cada minuto.

**Simular requests**:

```redis
INCR rl:1002:<minuto>    # 29  -> OK
INCR rl:1002:<minuto>    # 30  -> OK (límite inclusivo)
INCR rl:1002:<minuto>    # 31  -> la app responde 429
```

**Qué decir**: Redis no decide nada, solo cuenta. La app compara `count > 30` y rechaza. `INCR` es **atómico**: no hay race condition entre requests simultáneos.

**Por qué el minuto va en la clave**: cuando termina, la clave expira sola y el próximo request crea una clave nueva. **Cero código de reseteo**.

```redis
INCR rl:1003:<minuto>           # 1 -> primera request del user 1003
EXPIRE rl:1003:<minuto> 60 NX   # NX = solo si no tenía TTL ya
```

→ `NX` evita que el TTL se renueve en cada request (si no, la ventana nunca cerraría).

---

## 4. Cierre — ~30 s

| Caso              | Comando(s) Redis            | Comparación con Postgres                                       |
|-------------------|-----------------------------|----------------------------------------------------------------|
| Autocompletado    | `FT.SUGGET` (sub-ms)        | `ILIKE 'rede%' ORDER BY ...` (decenas de ms con tabla grande)  |
| JWT blacklist     | `SET ... EX` + `EXISTS`     | Tabla `revoked_tokens` + índice + cron de limpieza             |
| Rate limit        | `INCR` + `EXPIRE NX`        | `UPDATE ... SET count = count+1` con locks                     |

**Idea fuerza**: Redis no reemplaza a Postgres en BUSCASAM, lo **complementa** en los lugares donde el costo del round-trip a disco mata la UX (autocompletado) o donde el problema no es relacional (estado efímero con TTL).

---

## Apéndice — comandos de seguridad para la demo

Si algo se ensucia durante la presentación:

```bash
docker compose exec redis redis-cli FLUSHDB
seed/.venv/bin/python seed/seed.py
```

(re-seedea en 1 segundo, idempotente).

Para el contador del rate limit, el seed siempre lo deja en 28 en **el minuto actual**, así que es seguro re-correrlo si se pasó el minuto en medio de la demo.
