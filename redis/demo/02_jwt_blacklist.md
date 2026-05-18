# Demo 2 — Blacklist de JWT (logout)

## El problema

BUSCASAM usa **JWT** para autenticar a estudiantes y docentes. Un JWT es un token firmado que el cliente manda en cada request; el servidor lo valida con la firma sin tocar la base. Eso lo hace rapido, pero genera un problema:

> Una vez firmado, el JWT es valido hasta que expira (por ejemplo, 30 minutos). Si el usuario hace **logout**, no hay forma "natural" de invalidarlo.

La solucion estandar es mantener una **blacklist** de tokens revocados y chequearla en cada request. Redis es ideal: la blacklist es solo lectura/escritura por clave, no necesita relaciones, y los tokens **expiran solos** (TTL = lo que falta para que el JWT venza). Una vez expirado, la entrada se borra sola y no acumula basura.

---

## Estructura usada

Una clave string por token revocado:

```
jwt:blacklist:<jti>  ->  "<razon>"     TTL = expiracion del token
```

Donde `<jti>` es el **JWT ID** (campo `jti` dentro del payload, identificador unico de cada token).

> Cargado por el seed: una entrada de ejemplo (`demo-jti-001`) con razon "logout manual del usuario" y TTL ~1800s.

---

## Paso 1 — Ver que esta revocado

```bash
docker compose exec redis redis-cli
```

```redis
KEYS jwt:blacklist:*
```

Resultado:

```
1) "jwt:blacklist:demo-jti-001"
```

---

## Paso 2 — Chequear si un token esta blacklisteado

Es el comando que la app ejecuta **en cada request autenticado**, antes de aceptar el JWT:

```redis
EXISTS jwt:blacklist:demo-jti-001
```

Resultado:

```
(integer) 1
```

`1` = esta blacklisteado, rechazar. `0` = OK, dejar pasar.

Comparar con un token que **nunca** estuvo en la blacklist:

```redis
EXISTS jwt:blacklist:cualquier-otro-jti
```

```
(integer) 0
```

`EXISTS` es **O(1)**. No importa cuantos tokens tengamos blacklisteados, la respuesta es siempre inmediata.

---

## Paso 3 — Ver cuanto le falta para expirar

```redis
TTL jwt:blacklist:demo-jti-001
```

Resultado (varia segun cuanto pase desde el seed):

```
(integer) 1793
```

1793 segundos = ~30 minutos. Cuando llegue a 0, Redis borra la clave automaticamente y deja de aparecer en la blacklist (porque ya no hace falta: el token original tambien expiro).

Para verlo claro, ejecutar:

```redis
TTL jwt:blacklist:demo-jti-001
```

de nuevo despues de unos segundos. El numero baja solo.

---

## Paso 4 — Simular un logout

Cuando un usuario hace click en "Cerrar sesion", la app extrae el `jti` del JWT, calcula cuanto le falta para expirar y lo agrega a la blacklist:

```redis
SET jwt:blacklist:nuevo-jti-002 "logout manual del usuario" EX 1800
```

Donde:

- `SET` crea la clave.
- `EX 1800` define el TTL (1800 segundos = 30 min, lo que le quedaba al token).
- El valor (`"logout manual..."`) es solo para auditoria: lo importante es que la **clave exista**.

Verificar:

```redis
EXISTS jwt:blacklist:nuevo-jti-002
TTL    jwt:blacklist:nuevo-jti-002
GET    jwt:blacklist:nuevo-jti-002
```

```
(integer) 1
(integer) 1800
"logout manual del usuario"
```

---

## Paso 5 — Ver la expiracion en accion

Para mostrar en vivo el self-cleanup, crear una entrada con TTL muy corto:

```redis
SET jwt:blacklist:efimero "demo" EX 5
EXISTS jwt:blacklist:efimero
```

Esperar 6 segundos y volver a chequear:

```redis
EXISTS jwt:blacklist:efimero
```

```
(integer) 0
```

Sin codigo de cleanup, sin cron, sin overhead: **Redis se encarga**. Esto es la ventaja clave sobre implementar la blacklist en PostgreSQL, donde habria que correr una tarea programada que borre tokens expirados.

---

## Paso 6 — Revocar todos los tokens de un usuario (caso "cambio de contrasena")

Si el usuario cambia su contrasena o se detecta una cuenta comprometida, hay que **revocar todos sus tokens activos**, no solo uno. Como no sabemos cuales son sus `jti`, la convencion es guardar tambien una marca por usuario:

```redis
SET user:1002:tokens_revocados_antes "2026-05-18T14:25:00Z" EX 1800
```

La app, al validar el JWT, compara la fecha de emision (`iat`) del token contra esta marca:

```redis
GET user:1002:tokens_revocados_antes
```

Si la marca existe y `iat < marca`, el token se rechaza. Esto invalida en masa sin tener que iterar tokens.

---

## Lo que se aprende

- `SET ... EX` resuelve la blacklist en una sola operacion, con autolimpieza por TTL.
- `EXISTS` es O(1): el chequeo en cada request no es un cuello de botella.
- Redis pasa de "ayuda" a "habilitador" en este caso: sin Redis, el equivalente en PostgreSQL requeriria una tabla `revoked_tokens` con indice por `jti`, un job que limpie expirados, y mas latencia por consulta.
- El mismo patron (clave + TTL) sirve para password reset tokens, magic links, verificacion de email, etc.

---

## Comandos clave

| Comando         | Que hace                                                  |
|-----------------|-----------------------------------------------------------|
| `SET k v EX t`  | Crear clave con TTL en segundos                           |
| `EXISTS k`      | Chequeo O(1) de existencia                                |
| `TTL k`         | Segundos restantes (-1 = sin TTL, -2 = no existe)         |
| `DEL k`         | Borrar (si el usuario "des-revoca" un token, raro pero posible) |
