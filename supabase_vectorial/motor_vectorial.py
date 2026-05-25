import os
import fitz
import psycopg2
from sentence_transformers import SentenceTransformer

def iniciar_modelo():
    return SentenceTransformer('all-MiniLM-L6-v2')

def extraer_texto_pdf(ruta_pdf):
    if not os.path.exists(ruta_pdf):
        raise FileNotFoundError(f"Archivo no encontrado: {ruta_pdf}")
    doc = fitz.open(ruta_pdf)
    texto = ""
    for pagina in doc:
        texto_pagina = pagina.get_text()
        if isinstance(texto_pagina, str):
            texto += texto_pagina
    doc.close()
    return texto.strip()

def generar_embedding(model, titulo, abstract):
    texto_combinado = f"Título: {titulo} | Abstract: {abstract}"
    return model.encode(texto_combinado).tolist()

def insertar_documento(db_url, datos):
    query = """
        INSERT INTO vectorial.documentos (
            id_documento_bk, id_escuela, id_carrera, id_materia, id_tipo,
            titulo, abstract, texto_completo, archivo_url, embedding
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s::vectorial.vector);
    """
    conn = None
    try:
        conn = psycopg2.connect(db_url)
        cursor = conn.cursor()
        cursor.execute(query, (
            datos['id_documento_bk'], datos['id_escuela'], datos['id_carrera'],
            datos['id_materia'], datos['id_tipo'], datos['titulo'],
            datos['abstract'], datos['texto_completo'], datos['archivo_url'],
            datos['embedding']
        ))
        conn.commit()
        print(f"Documento BK {datos['id_documento_bk']} guardado con exito.")
    except Exception as e:
        print(f"Error de base de datos: {e}")
        if conn:
            conn.rollback()
    finally:
        if conn:
            conn.close()

def buscar_documentos_semanticos(db_url, model, query_usuario, limite, umbral):
    query_vector = model.encode(query_usuario).tolist()
    query_sql = """
        WITH buscador AS (
            SELECT id_documento_bk, titulo, abstract, archivo_url,
                   (1 - (embedding <=> %s::vectorial.vector)) AS similitud
            FROM vectorial.documentos
        )
        SELECT id_documento_bk, titulo, abstract, archivo_url, similitud
        FROM buscador
        WHERE similitud >= %s
        ORDER BY similitud DESC
        LIMIT %s;
    """
    conn = None
    resultados = []
    try:
        conn = psycopg2.connect(db_url)
        cursor = conn.cursor()
        cursor.execute("SET search_path TO vectorial, public;")
        cursor.execute(query_sql, (query_vector, umbral, limite))
        resultados = cursor.fetchall()
    except Exception as e:
        print(f"Error en la busqueda: {e}")
    finally:
        if conn:
            conn.close()
    return resultados