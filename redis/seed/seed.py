"""Carga datos sinteticos en Redis para la demo de BUSCASAM.

Popula cinco estructuras:
  - autocomplete:queries     suggestion dict de RediSearch (FT.SUGADD)
  - queries:popularity     zset con popularidad de queries (ZADD)
  - session:<sid>            hash con datos del usuario logueado (HSET + EXPIRE)
  - jwt:blacklist:<jti>      flag de revocacion con TTL (SET ... EX)
  - rl:<user_id>:<minuto>    contador de rate limit (INCR + EXPIRE)

Uso:
    pip install -r requirements.txt
    python seed.py                       # localhost:6379
    REDIS_HOST=otro REDIS_PORT=6380 python seed.py
"""
from __future__ import annotations

import datetime as dt
import json
import os
import sys
from pathlib import Path

import jwt
import redis

JWT_SECRET = "demo-secret-no-usar-en-produccion"  # solo para la demo
DATA_FILE = Path(__file__).parent / "data.json"


STOP_WORDS = {"de", "en", "la", "el", "a", "para", "con", "y", "o", "del", "al", "los", "las", "un", "una", "por", "como"}


def extraer_subqueries_validas(texto: str) -> list[str]:
    words = texto.strip().lower().split()
    if not words:
        return []
    if len(words) == 1:
        return [words[0]]
    subqueries = []
    for i in range(2, len(words) + 1):
        last_word = words[i - 1]
        if last_word not in STOP_WORDS:
            subqueries.append(" ".join(words[:i]))
    if not subqueries:
        subqueries.append(" ".join(words))
    return list(dict.fromkeys(subqueries))


def connect() -> redis.Redis:
    url = os.environ.get("REDIS_URL", "")
    if url:
        client = redis.Redis.from_url(url, decode_responses=True)
        clean_url = url.split("@")[-1] if "@" in url else url
        print(f"[ok] conectado a Redis via URL: {clean_url}")
    else:
        host = os.environ.get("REDIS_HOST", "localhost")
        port = int(os.environ.get("REDIS_PORT", "6379"))
        client = redis.Redis(host=host, port=port, decode_responses=True)
        print(f"[ok] conectado a redis://{host}:{port}")
    client.ping()
    return client


def seed_autocomplete(client: redis.Redis, cfg: dict) -> None:
    key = cfg["key"]
    client.delete(key)
    
    zset_key = "queries:popularity"
    client.delete(zset_key)
    
    subquery_scores = {}
    for q in cfg["queries"]:
        text = q["text"].strip().lower()
        score = int(q["score"])
        subqs = extraer_subqueries_validas(text)
        for subq in subqs:
            subquery_scores[subq] = subquery_scores.get(subq, 0) + score
            
    # Verificar si el proveedor soporta RediSearch (FT.SUGADD)
    redisearch_supported = True
    try:
        client.execute_command("FT.SUGADD", "temp:test:dict", "test", 1)
        client.execute_command("FT.SUGDEL", "temp:test:dict", "test")
    except redis.exceptions.ResponseError as e:
        if "unknown command" in str(e).lower():
            redisearch_supported = False
            print("[warn] RediSearch no esta disponible en este servidor Redis (ej: Upstash).")
            print("       Se omitira el autocompletado en RediSearch, pero se creara el ZSET para el ETL.")
            
    pipe = client.pipeline()
    for subq, score in subquery_scores.items():
        if redisearch_supported:
            pipe.execute_command("FT.SUGADD", key, subq, score)
        pipe.zadd(zset_key, {subq: score})
    pipe.execute()
    
    if redisearch_supported:
        total = client.execute_command("FT.SUGLEN", key)
        print(f"[autocomplete] {total} sugerencias cargadas en RediSearch '{key}'")
    else:
        print(f"[autocomplete] Trie de autocompletado RediSearch OMITIDO (no soportado).")
        
    print(f"[autocomplete] {client.zcard(zset_key)} queries cargadas en el ZSET '{zset_key}'")


def seed_sessions(client: redis.Redis, cfg: dict) -> None:
    ttl = cfg["ttl_seconds"]
    for user in cfg["users"]:
        sid = user["session_id"]
        key = f"session:{sid}"
        client.hset(key, mapping={
            "user_id": user["user_id"],
            "nombre": user["nombre"],
            "rol": user["rol"],
            "carrera": user["carrera"],
            "created_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        })
        client.expire(key, ttl)
    print(f"[sessions] {len(cfg['users'])} sesiones activas (TTL {ttl}s)")


def seed_jwt_blacklist(client: redis.Redis, cfg: dict) -> None:
    prefix = cfg["key_prefix"]
    for entry in cfg["revoked"]:
        ttl = entry["ttl_seconds"]
        token = jwt.encode(
            {
                "sub": entry["user_id"],
                "jti": entry["jti"],
                "exp": dt.datetime.now(dt.timezone.utc) + dt.timedelta(seconds=ttl),
            },
            JWT_SECRET,
            algorithm="HS256",
        )
        client.set(f"{prefix}{entry['jti']}", entry["reason"], ex=ttl)
        print(f"[jwt] revocado jti={entry['jti']} (TTL {ttl}s)  token={token[:32]}...")


def seed_rate_limit(client: redis.Redis, cfg: dict) -> None:
    prefix = cfg["key_prefix"]
    window = cfg["window_seconds"]
    bucket = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M")
    for entry in cfg["preloaded"]:
        key = f"{prefix}{entry['user_id']}:{bucket}"
        client.set(key, entry["count"], ex=window)
        print(f"[ratelimit] {key} = {entry['count']} (limite {cfg['limit_per_minute']}/min, TTL {window}s)")


def main() -> int:
    if not DATA_FILE.exists():
        print(f"[error] no se encuentra {DATA_FILE}", file=sys.stderr)
        return 1
    with DATA_FILE.open(encoding="utf-8") as f:
        data = json.load(f)

    client = connect()
    seed_autocomplete(client, data["autocomplete"])
    seed_sessions(client, data["sessions"])
    seed_jwt_blacklist(client, data["jwt_blacklist"])
    seed_rate_limit(client, data["rate_limit"])
    print(f"[done] total de claves en la base: {client.dbsize()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
