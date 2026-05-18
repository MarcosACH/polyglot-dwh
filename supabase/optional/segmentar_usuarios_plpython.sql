-- =============================================================
-- BUSCASAM DWH - segmentar_usuarios (plpython3u)
-- =============================================================
-- IMPORTANTE: plpython3u NO esta disponible en Supabase Cloud.
-- Este archivo se aplica solo en instancias self-hosted de PostgreSQL
-- donde se haya instalado el lenguaje (paquete postgresql-plpython3-XX).
--
-- Requiere ademas las libs Python: scikit-learn y numpy en el host.
-- =============================================================

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
