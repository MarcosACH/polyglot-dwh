import os
from dotenv import load_dotenv
import motor_vectorial as mv

# 1. Configurar entorno y ocultar warnings
load_dotenv()
os.environ["HF_HUB_DISABLE_SYMLINKS_WARNING"] = "1"

# 2. Leer credenciales de forma segura desde el .env
DATABASE_URL = os.environ.get("DATABASE_URL")

if __name__ == "__main__":
    print("Inicializando modelo de IA...")
    modelo = mv.iniciar_modelo()
    
# =========================================================
    # ACCION A: INDEXAR UN DOCUMENTO (Simulando request de la App)
    # =========================================================
    print("\n--- EJECUTANDO INDEXACION ---")
    
    archivo_entrada = "paper_prueba.pdf"
    payload_formulario = {
        "id_documento_bk": 501,
        "id_escuela": 3,
        "id_carrera": 8,
        "id_materia": 50,
        "id_tipo": 1,
        "titulo": "Algoritmos de Clustering en Mineria de Datos Masivos",
        "abstract": "Un analisis comparativo entre K-Means y DBSCAN para el descubrimiento de patrones anomalos en grandes volumenes de informacion.",
        "archivo_url": "papers/501/clustering_mineria.pdf"
    }
    
    try:
        # Pasamos las variables explicitamente a las funciones
        payload_formulario["texto_completo"] = mv.extraer_texto_pdf(archivo_entrada)
        payload_formulario["embedding"] = mv.generar_embedding(
            modelo, 
            payload_formulario["titulo"], 
            payload_formulario["abstract"]
        )
        
        # Le inyectamos la URL de la base de datos obtenida del entorno
        mv.insertar_documento(DATABASE_URL, payload_formulario)
    except FileNotFoundError as e:
        print(f"Indexacion salteada en el test: {e}")

    # =========================================================
    # ACCION B: BUSQUEDA SEMANTICA (Simulando input de la App)
    # =========================================================
    print("\n--- EJECUTANDO BUSQUEDA ---")
    
    # Parametros de busqueda controlados desde el main
    busqueda_usuario = "agrupamiento de datos y patrones anomalos"
    limite_ui = 3
    umbral_cercania = 0.35
    
    print(f"Buscando: '{busqueda_usuario}'...")
    resultados = mv.buscar_documentos_semanticos(
        DATABASE_URL, 
        modelo, 
        busqueda_usuario, 
        limite=limite_ui, 
        umbral=umbral_cercania
    )
    
    # Mostrar resultados mapeados
    for res in resultados:
        id_bk, titulo, abstract, url, score = res
        print(f"[{score:.4f}] ID BK: {id_bk} - Titulo: {titulo}")