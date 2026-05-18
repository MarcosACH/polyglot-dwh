# Demo 1 — Autocompletado del buscador

## Que hace BUSCASAM

Mientras el usuario tipea en la caja de busqueda, la app le muestra sugerencias en menos de un milisegundo. PostgreSQL no es lo suficientemente rapido para eso (cada tecla es una consulta nueva), asi que se delega a Redis.

Para esta demo usamos el modulo **RediSearch** (incluido en Redis Stack) y su comando `FT.SUGGET`, que esta hecho a medida para autocompletado.

---

## Estructura usada

Un unico **suggestion dictionary** llamado `autocomplete:queries`. Cada entrada es:

```
<texto sugerido>  ->  <score numerico>
```

El score representa popularidad. Cuando alguien ejecuta `FT.SUGGET` con un prefijo, RediSearch devuelve los matches ordenados por score descendente.

> Cargado por el seed: 50 queries reales del dominio academico (ver `seed/data.json`).

---

## Paso 1 — Verificar el contenido

```bash
docker compose exec redis redis-cli
```

```redis
FT.SUGLEN autocomplete:queries
```

Devuelve `50`: las 50 sugerencias del seed.

---

## Paso 2 — Tipear "rede" (caso clasico)

Simula al usuario escribiendo "rede":

```redis
FT.SUGGET autocomplete:queries "rede" MAX 5
```

Resultado:

```
1) "redes neuronales"
2) "redes neuronales convolucionales"
3) "redes neuronales recurrentes"
4) "redes sociales analisis"
5) "redes complejas"
```

Notar que **estan ordenados por popularidad**, no alfabeticamente: "redes neuronales" tiene score 187 y aparece primero.

---

## Paso 3 — Ver los scores

```redis
FT.SUGGET autocomplete:queries "rede" MAX 5 WITHSCORES
```

Resultado (los numeros pueden diferir levemente):

```
 1) "redes neuronales"
 2) "51.86446762084961"
 3) "redes neuronales convolucionales"
 4) "26.368738174438477"
 5) "redes neuronales recurrentes"
 6) "19.200000762939453"
 7) "redes sociales analisis"
 8) "16.32329559326172"
 9) "redes complejas"
10) "11.835680961608887"
```

> **Importante**: el score devuelto **no** es el valor crudo que cargo el seed (187, 142, 96, ...). RediSearch combina dos cosas: la popularidad almacenada y la calidad del match del prefijo (que tan unica es la sugerencia respecto del termino tipeado). El orden relativo se conserva, pero los numeros estan normalizados internamente.

Util para explicar como funciona el ranking. En un escenario real, el score crudo se actualiza con `FT.SUGADD ... INCR` cada vez que alguien hace click en una sugerencia o ejecuta esa busqueda (ver Paso 5).

---

## Paso 4 — Match con tipeo (FUZZY)

El usuario escribe **"machne"** (le falto la `i`):

```redis
FT.SUGGET autocomplete:queries "machne" MAX 5 FUZZY
```

Resultado:

```
1) "machine learning supervisado"
2) "machine learning no supervisado"
3) "machine learning aplicado a salud"
```

`FUZZY` permite **una distancia de Levenshtein de 1**, asi que `machne` matchea `machine`. Resuelve typos sin codigo extra.

Sin `FUZZY` el mismo comando no devuelve nada:

```redis
FT.SUGGET autocomplete:queries "machne" MAX 5
(empty list or set)
```

---

## Paso 5 — Sumar popularidad in vivo

Cuando alguien ejecuta una busqueda nueva (o re-ejecuta una popular), la app suma al score. `FT.SUGADD` con `INCR` lo hace en una sola operacion (la crea si no existia, le suma si si):

```redis
FT.SUGADD autocomplete:queries "redes neuronales" 1 INCR
```

Devuelve el **tamano del diccionario** (`50`), no el nuevo score del termino. Es una particularidad de la API: la confirmacion del incremento se verifica re-consultando con `FT.SUGGET`. El cambio se nota cuando se compara la posicion / score de "redes neuronales" frente a otros antes y despues de varios `INCR`.

> Para una demo en vivo se puede ejecutar `FT.SUGADD ... INCR` varias veces sobre una query baja (por ejemplo "robotica educativa") y mostrar como sube de posicion en `FT.SUGGET "rob" WITHSCORES`.

---

## Paso 6 — Borrar una sugerencia (moderacion)

Si una query queda obsoleta o es ruido, se borra con `FT.SUGDEL`:

```redis
FT.SUGDEL autocomplete:queries "robotica educativa"
```

Devuelve `1` (borrada). Volver a buscar:

```redis
FT.SUGGET autocomplete:queries "rob" MAX 3
(empty list or set)
```

---

## Paso 7 — Mostrarlo en RedisInsight

1. Abrir <http://localhost:8001>.
2. Browser -> filtrar por `autocomplete:*`: aparece **una sola clave** (`autocomplete:queries`) del tipo `TRIE-SUFFIX`. Es la estructura interna del suggestion dictionary.
3. Workbench -> pegar `FT.SUGGET autocomplete:queries "deep" MAX 5 WITHSCORES`: muestra los resultados con sintaxis resaltada, util para presentar.

---

## Lo que se aprende

- Una sola estructura (suggestion dictionary) resuelve un caso de uso que en SQL requiere full-text search + ranking + indices + tuning.
- El score es **mutable**: se actualiza con `INCR` a medida que la app aprende que es popular.
- `FUZZY` cubre typos sin que el desarrollador tenga que implementar Levenshtein a mano.
- Latencia tipica: sub-milisegundo. Comparable: una consulta equivalente con `ILIKE 'rede%'` + `ORDER BY` sobre PostgreSQL puede tardar decenas de milisegundos si la tabla es grande.

---

## Comandos clave

| Comando        | Que hace                                          |
|----------------|---------------------------------------------------|
| `FT.SUGADD`    | Agregar/actualizar una sugerencia (`INCR` opcional) |
| `FT.SUGGET`    | Buscar por prefijo (con `FUZZY`, `MAX`, `WITHSCORES`) |
| `FT.SUGDEL`    | Borrar una sugerencia                             |
| `FT.SUGLEN`    | Contar las sugerencias del diccionario            |
