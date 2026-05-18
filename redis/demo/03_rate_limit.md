# Demo 3 — Rate limiting (fixed window)

## El problema

Si un usuario (o un bot) hace muchas busquedas seguidas, puede saturar el motor de busqueda de BUSCASAM. Para evitarlo, se limita la cantidad de operaciones por unidad de tiempo. Para esta demo: **30 busquedas por minuto por usuario**. El minuto 31 se rechaza con HTTP 429.

PostgreSQL no es buen lugar para esto: cada request implicaria un `UPDATE ... SET count = count + 1 WHERE user_id = ... AND ventana = ...`, con bloqueos y latencia. Redis lo hace con dos comandos atomicos.

---

## Algoritmo: Fixed window

> Para cada `(usuario, minuto)` se mantiene un contador. Cuando entra un request:
>
> 1. Se incrementa el contador (`INCR`). Si la clave no existia, arranca en 1.
> 2. Si el contador era 1 (recien creado), se le pone un TTL de 60 segundos (`EXPIRE`).
> 3. Si el contador supera el limite, se rechaza el request.
>
> Cuando termina el minuto, el TTL hace expirar la clave y el contador "se resetea" para la proxima ventana.

Es el algoritmo mas simple. Otras variantes (sliding window, token bucket) son mas precisas pero requieren mas codigo o scripting Lua. Para el TP alcanza con esto.

---

## Estructura usada

```
rl:<user_id>:<YYYYMMDDHHMM>  ->  <contador>     TTL = 60s
```

El minuto se codifica en la clave. Asi dos minutos consecutivos tienen claves distintas y no hace falta resetear nada manualmente.

> Cargado por el seed: una clave para el usuario 1002 en el minuto actual con contador 28. Sirve para que en la demo el request 31 sea el que rechaza.

---

## Paso 1 — Ver el estado pre-cargado

```bash
docker compose exec redis redis-cli
```

```redis
KEYS rl:*
```

Resultado (el minuto depende del momento del seed):

```
1) "rl:1002:202605181418"
```

```redis
GET rl:1002:202605181418
TTL rl:1002:202605181418
```

```
"28"
(integer) 47
```

El usuario 1002 ya hizo 28 busquedas en este minuto, y a la ventana le quedan 47 segundos.

---

## Paso 2 — Hacer dos requests mas (29 y 30, todavia OK)

```redis
INCR rl:1002:202605181418
```

```
(integer) 29
```

```redis
INCR rl:1002:202605181418
```

```
(integer) 30
```

29 y 30: la app **acepta** ambos requests. El limite es 30 inclusivo.

---

## Paso 3 — Request 31: rechazo

```redis
INCR rl:1002:202605181418
```

```
(integer) 31
```

Redis no decide nada: simplemente incrementa. **Es la app la que compara**: si el valor retornado por `INCR` supera 30, devuelve HTTP 429 al cliente.

Pseudocodigo de la app:

```python
key = f"rl:{user_id}:{datetime.utcnow().strftime('%Y%m%d%H%M')}"
count = redis.incr(key)
if count == 1:
    redis.expire(key, 60)        # solo la primera vez, fija el TTL
if count > 30:
    raise HTTPException(429, "Demasiadas busquedas, intenta de nuevo en un minuto")
```

> **Observacion importante**: el `EXPIRE` se setea **solo cuando `count == 1`**, es decir cuando la clave recien se crea. Si lo setearamos en cada request, el TTL se renovaria y la ventana nunca terminaria.

---

## Paso 4 — Esperar a que pase la ventana

Mostrar que el reset es automatico:

```redis
TTL rl:1002:202605181418
```

Cuando llega a 0, la clave desaparece:

```redis
EXISTS rl:1002:202605181418
```

```
(integer) 0
```

El proximo `INCR` arranca de nuevo en 1 (en una clave nueva con minuto distinto):

```redis
INCR rl:1002:<nuevo_minuto>
```

```
(integer) 1
```

---

## Paso 5 — Crear el rate limit "desde cero" para otro usuario

Simular el primer request del usuario 1003 en el minuto actual:

```redis
SET rl:1003:202605181420 0 EX 60
INCR rl:1003:202605181420
```

```
OK
(integer) 1
```

Equivalente compacto (el que usaria la app de verdad), sin el `SET` previo:

```redis
INCR rl:1003:202605181420
EXPIRE rl:1003:202605181420 60 NX
```

```
(integer) 1
(integer) 1
```

`NX` en `EXPIRE` significa "solo si no tiene TTL todavia". Esto evita el efecto de renovar la ventana en cada request — aunque la app llame `EXPIRE` sin verificar, `NX` lo hace seguro.

---

## Paso 6 — Verlo en RedisInsight

1. Workbench -> `KEYS rl:*` muestra todas las ventanas activas.
2. Click en una clave -> muestra el valor (contador) y el TTL en vivo, con countdown grafico.
3. Util para mostrar que las claves **aparecen y desaparecen solas** al ritmo de los requests.

---

## Lo que se aprende

- `INCR` es **atomico**: dos requests simultaneos no pueden quedar con el mismo count, no hay race condition.
- Codificar el minuto en la clave evita logica de reseteo: cuando termina el minuto, la clave expira y se vuelve a crear con el primer request del minuto siguiente.
- El patron `INCR` + `EXPIRE NX` es el rate limit mas barato que existe (~2 comandos por request, microsegundos).
- Comparado con PostgreSQL: una solucion equivalente con una tabla `rate_limit` requiere `UPSERT` + indice + cleanup. Redis lo hace en dos comandos sin tocar disco.

---

## Comandos clave

| Comando             | Que hace                                                       |
|---------------------|----------------------------------------------------------------|
| `INCR k`            | Suma 1 al valor (crea la clave en 1 si no existe). Atomico.    |
| `EXPIRE k s [NX]`   | Pone TTL en segundos. `NX` = solo si no tenia TTL.             |
| `GET k`             | Lee el contador actual.                                        |
| `TTL k`             | Segundos restantes hasta que expire (-1 = sin TTL).            |

---

## Limitaciones del fixed window

Para el TP alcanza, pero vale aclarar:

- **Rafagas en el borde**: si un usuario hace 30 requests en el segundo 59 de un minuto y 30 mas en el segundo 0 del siguiente, hizo 60 en 2 segundos, sin pasar el limite. Es un problema conocido. Para resolverlo se usa **sliding window** (sorted set de timestamps) o **token bucket**.
- **Sincronizacion de reloj**: si la app y Redis estan en zonas distintas, las claves pueden no alinearse. Para esta demo no aplica: todo corre en el mismo Docker.
