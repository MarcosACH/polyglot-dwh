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
    # Insertar en operativo.documento
    # Usamos public.vector para el tipo de datos ya que la extensión pgvector se reubicó en el esquema public.
    query_doc = """
        INSERT INTO operativo.documento (
            titulo, abstract, texto_completo, visibilidad,
            id_tipo, id_materia, id_uploader, archivo_url, embedding
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s::public.vector)
        RETURNING id;
    """
    
    # Insertar al uploader como autor principal (orden = 1) en operativo.documento_autor
    query_autor = """
        INSERT INTO operativo.documento_autor (
            id_documento, id_usuario, orden
        ) VALUES (%s, %s, 1);
    """
    
    conn = None
    try:
        conn = psycopg2.connect(db_url)
        cursor = conn.cursor()
        
        # 1. Insertar el documento y obtener el ID autogenerado
        cursor.execute(query_doc, (
            datos['titulo'], datos['abstract'], datos['texto_completo'], datos['visibilidad'],
            datos['id_tipo'], datos['id_materia'], datos['id_uploader'], datos['archivo_url'],
            datos['embedding']
        ))
        row = cursor.fetchone()
        if row is None:
            raise ValueError("No se pudo obtener el ID del documento insertado")
        id_documento = row[0]
        
        # 2. Insertar la co-autoría principal para el uploader
        cursor.execute(query_autor, (id_documento, datos['id_uploader']))
        
        conn.commit()
        print(f"Documento insertado con éxito en el esquema operativo (ID: {id_documento}).")
        print(f"Autor principal (ID Usuario: {datos['id_uploader']}) asociado en operativo.documento_autor.")
        return id_documento
    except Exception as e:
        print(f"Error de base de datos en inserción: {e}")
        if conn:
            conn.rollback()
        raise e
    finally:
        if conn:
            conn.close()

def buscar_documentos_semanticos(db_url, model, query_usuario, limite, umbral):
    query_vector = model.encode(query_usuario).tolist()
    query_sql = """
        WITH buscador AS (
            SELECT id, titulo, abstract, archivo_url,
                   (1 - (embedding <=> %s::public.vector)) AS similitud
            FROM operativo.documento
            WHERE deleted_at IS NULL -- Excluir documentos con soft delete
        )
        SELECT id, titulo, abstract, archivo_url, similitud
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
        cursor.execute(query_sql, (query_vector, umbral, limite))
        resultados = cursor.fetchall()
    except Exception as e:
        print(f"Error en la búsqueda semántica: {e}")
    finally:
        if conn:
            conn.close()
    return resultados
