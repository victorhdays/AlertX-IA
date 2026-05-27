from fastapi import FastAPI, HTTPException, UploadFile, File
from pydantic import BaseModel, Field
from datetime import datetime
from supabase import create_client, Client
from dotenv import load_dotenv
from PIL import Image
import pandas as pd
import numpy as np
import joblib
import math
import os
import io
import cv2

load_dotenv()

app = FastAPI(title="VialAlert PR - IA API")

modelo_gravedad = joblib.load("modelo_gravedad.pkl")
modelo_falso = joblib.load("modelo_falso.pkl")

try:
    modelo_imagen = joblib.load("modelo_imagen.pkl")
except:
    modelo_imagen = None

SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

if not SUPABASE_URL or not SUPABASE_KEY:
    raise RuntimeError("Faltan SUPABASE_URL o SUPABASE_KEY en el archivo .env")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)


class ReporteAccidente(BaseModel):
    usuario_id: str = Field(..., min_length=3)
    latitud: float
    longitud: float
    velocidad: float = Field(..., ge=0, le=180)
    impacto: float = Field(..., ge=0, le=10)
    cantidad_reportes_zona: int = Field(..., ge=0, le=100)
    usuario_verificado: bool
    descripcion: str = Field(..., min_length=3)
    zona_riesgo: int | None = None


zonas_poza_rica = [
    {"nombre": "Boulevard Ruiz Cortines", "latitud": 20.5333, "longitud": -97.4595, "riesgo": 2},
    {"nombre": "Centro de Poza Rica", "latitud": 20.5347, "longitud": -97.4598, "riesgo": 2},
    {"nombre": "Avenida 20 de Noviembre", "latitud": 20.5298, "longitud": -97.4660, "riesgo": 1},
    {"nombre": "Zona Escolar / ITSPR", "latitud": 20.5520, "longitud": -97.4510, "riesgo": 1}
]


def calcular_distancia_km(lat1, lon1, lat2, lon2):
    radio = 6371
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)

    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(dlon / 2) ** 2
    )

    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return radio * c


def detectar_zona(latitud, longitud):
    zona_cercana = None
    distancia_menor = 999999

    for zona in zonas_poza_rica:
        distancia = calcular_distancia_km(
            latitud,
            longitud,
            zona["latitud"],
            zona["longitud"]
        )

        if distancia < distancia_menor:
            distancia_menor = distancia
            zona_cercana = zona

    if distancia_menor <= 2:
        return zona_cercana["nombre"], zona_cercana["riesgo"]

    return "Zona no clasificada", 0


def convertir_gravedad(valor):
    if valor == 0:
        return "BAJA"
    if valor == 1:
        return "MEDIA"
    return "ALTA"


def convertir_falso(valor):
    if valor == 1:
        return "SOSPECHOSO"
    return "CONFIABLE"


def explicar_decision(reporte, zona_riesgo):
    factores = []

    if reporte.velocidad >= 80:
        factores.append("velocidad elevada")

    if reporte.impacto >= 8:
        factores.append("impacto fuerte detectado")

    if zona_riesgo == 2:
        factores.append("zona con alto historial de riesgo")

    if reporte.cantidad_reportes_zona >= 3:
        factores.append("varios reportes en la misma zona")

    if not reporte.usuario_verificado:
        factores.append("usuario no verificado")

    if len(reporte.descripcion.strip()) < 15:
        factores.append("descripción limitada")

    if not factores:
        factores.append("sin factores críticos detectados")

    return factores


def calcular_prioridad(gravedad, confiabilidad):
    if confiabilidad == "SOSPECHOSO":
        return "VERIFICAR REPORTE ANTES DE ENVIAR UNIDAD"

    if gravedad == "ALTA":
        return "URGENTE: enviar ambulancia, policía municipal y protección civil"

    if gravedad == "MEDIA":
        return "MEDIA: enviar policía y valorar ambulancia"

    return "BAJA: monitorear reporte"


def guardar_reporte_supabase(data):
    try:
        respuesta = supabase.table("reportes").insert(data).execute()
        return respuesta
    except Exception as e:
        print("ERROR SUPABASE:", e)
        raise HTTPException(status_code=500, detail=str(e))


def extraer_caracteristicas_imagen(imagen_bytes):
    imagen = Image.open(io.BytesIO(imagen_bytes)).convert("RGB")
    img = np.array(imagen)

    img_cv = cv2.cvtColor(img, cv2.COLOR_RGB2BGR)
    gris = cv2.cvtColor(img_cv, cv2.COLOR_BGR2GRAY)

    bordes = cv2.Canny(gris, 100, 200)
    nivel_bordes = float(np.mean(bordes > 0))

    brillo = float(np.mean(gris) / 255)
    oscuridad = float(1 - brillo)
    contraste = float(np.std(gris) / 255)

    rojo = img[:, :, 0]
    verde = img[:, :, 1]
    azul = img[:, :, 2]

    zonas_rojas = float(
        np.mean((rojo > 130) & (rojo > verde * 1.2) & (rojo > azul * 1.2))
    )

    return {
        "bordes": nivel_bordes,
        "oscuridad": oscuridad,
        "rojo": zonas_rojas,
        "brillo": brillo,
        "contraste": contraste
    }


@app.get("/")
def inicio():
    return {
        "sistema": "VialAlert PR",
        "mensaje": "API de IA activa"
    }


@app.get("/health")
def health():
    return {
        "estado": "activo",
        "modelo_gravedad": "cargado",
        "modelo_falso": "cargado",
        "modelo_imagen": "cargado" if modelo_imagen else "no cargado",
        "supabase": "conectado",
        "fecha_hora": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }


@app.get("/info_modelo")
def info_modelo():
    return {
        "algoritmo_datos": "RandomForestClassifier",
        "algoritmo_imagen": "RandomForestClassifier",
        "modelos": [
            "clasificación de gravedad por datos",
            "detección de reporte falso",
            "clasificación visual de accidente por imagen"
        ],
        "base_datos": "Supabase PostgreSQL"
    }


@app.get("/reportes")
def obtener_reportes():
    respuesta = (
        supabase
        .table("reportes")
        .select("*")
        .order("id", desc=True)
        .execute()
    )

    return respuesta.data


@app.get("/estadisticas")
def estadisticas():
    reportes = supabase.table("reportes").select("*").execute().data

    total_reportes = len(reportes)
    total_altas = len([r for r in reportes if r.get("gravedad") == "ALTA"])
    total_sospechosos = len([r for r in reportes if r.get("confiabilidad") == "SOSPECHOSO"])

    conteo_zonas = {}

    for r in reportes:
        zona = r.get("zona_detectada", "Sin zona")
        conteo_zonas[zona] = conteo_zonas.get(zona, 0) + 1

    zonas_mas_reportadas = sorted(
        conteo_zonas.items(),
        key=lambda x: x[1],
        reverse=True
    )[:5]

    return {
        "total_reportes": total_reportes,
        "accidentes_gravedad_alta": total_altas,
        "reportes_sospechosos": total_sospechosos,
        "zonas_mas_reportadas": [
            {"zona": zona, "total": total}
            for zona, total in zonas_mas_reportadas
        ]
    }


@app.post("/analizar_accidente")
def analizar_accidente(reporte: ReporteAccidente):

    if not (-90 <= reporte.latitud <= 90):
        raise HTTPException(status_code=400, detail="Latitud inválida")

    if not (-180 <= reporte.longitud <= 180):
        raise HTTPException(status_code=400, detail="Longitud inválida")

    zona_detectada, zona_riesgo_detectada = detectar_zona(
        reporte.latitud,
        reporte.longitud
    )

    zona_riesgo = reporte.zona_riesgo if reporte.zona_riesgo is not None else zona_riesgo_detectada

    hora_actual = datetime.now().hour
    descripcion_larga = 1 if len(reporte.descripcion.strip()) >= 15 else 0
    usuario_verificado_num = 1 if reporte.usuario_verificado else 0

    columnas_modelo = [
        "velocidad",
        "impacto",
        "cantidad_reportes_zona",
        "usuario_verificado",
        "hora",
        "descripcion_larga",
        "zona_riesgo"
    ]

    datos_entrada = pd.DataFrame([[
        reporte.velocidad,
        reporte.impacto,
        reporte.cantidad_reportes_zona,
        usuario_verificado_num,
        hora_actual,
        descripcion_larga,
        zona_riesgo
    ]], columns=columnas_modelo)

    pred_gravedad = modelo_gravedad.predict(datos_entrada)[0]
    pred_falso = modelo_falso.predict(datos_entrada)[0]

    gravedad = convertir_gravedad(pred_gravedad)
    confiabilidad = convertir_falso(pred_falso)

    prob_gravedad = modelo_gravedad.predict_proba(datos_entrada)[0]
    prob_falso = modelo_falso.predict_proba(datos_entrada)[0]

    prioridad = calcular_prioridad(gravedad, confiabilidad)
    factores = explicar_decision(reporte, zona_riesgo)

    fecha_hora = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    data_supabase = {
        "fecha_hora": fecha_hora,
        "usuario_id": reporte.usuario_id,
        "latitud": reporte.latitud,
        "longitud": reporte.longitud,
        "zona_detectada": zona_detectada,
        "zona_riesgo": zona_riesgo,
        "velocidad": reporte.velocidad,
        "impacto": reporte.impacto,
        "cantidad_reportes_zona": reporte.cantidad_reportes_zona,
        "usuario_verificado": reporte.usuario_verificado,
        "descripcion": reporte.descripcion,
        "gravedad": gravedad,
        "confiabilidad": confiabilidad,
        "prioridad_c4": prioridad,
        "factores": ", ".join(factores)
    }

    guardar_reporte_supabase(data_supabase)

    return {
        "fecha_hora": fecha_hora,
        "usuario": reporte.usuario_id,
        "ubicacion_gps": {
            "latitud": reporte.latitud,
            "longitud": reporte.longitud
        },
        "zona": {
            "zona_detectada": zona_detectada,
            "zona_riesgo": zona_riesgo
        },
        "machine_learning": {
            "modelo_gravedad": "RandomForestClassifier",
            "gravedad_predicha": gravedad,
            "probabilidad_baja": f"{prob_gravedad[0] * 100:.2f}%",
            "probabilidad_media": f"{prob_gravedad[1] * 100:.2f}%",
            "probabilidad_alta": f"{prob_gravedad[2] * 100:.2f}%"
        },
        "deteccion_reporte_falso": {
            "modelo_falso": "RandomForestClassifier",
            "confiabilidad": confiabilidad,
            "probabilidad_confiable": f"{prob_falso[0] * 100:.2f}%",
            "probabilidad_sospechoso": f"{prob_falso[1] * 100:.2f}%"
        },
        "decision_c4": {
            "prioridad": prioridad,
            "factores_detectados": factores
        },
        "almacenamiento": {
            "guardado_en_supabase": True
        }
    }


@app.post("/analizar_imagen_accidente")
async def analizar_imagen_accidente(
    usuario_id: str,
    imagen: UploadFile = File(...)
):
    if modelo_imagen is None:
        raise HTTPException(
            status_code=500,
            detail="No existe modelo_imagen.pkl. Primero ejecuta train_image_model.py"
        )

    contenido = await imagen.read()
    caracteristicas = extraer_caracteristicas_imagen(contenido)

    columnas_imagen = [
        "bordes",
        "oscuridad",
        "rojo",
        "brillo",
        "contraste"
    ]

    datos_imagen = pd.DataFrame([[
        caracteristicas["bordes"],
        caracteristicas["oscuridad"],
        caracteristicas["rojo"],
        caracteristicas["brillo"],
        caracteristicas["contraste"]
    ]], columns=columnas_imagen)

    prediccion = modelo_imagen.predict(datos_imagen)[0]
    probabilidades = modelo_imagen.predict_proba(datos_imagen)[0]

    gravedad_visual = convertir_gravedad(prediccion)

    return {
        "usuario": usuario_id,
        "archivo": imagen.filename,
        "vision_artificial": {
            "modelo": "RandomForestClassifier",
            "gravedad_visual": gravedad_visual,
            "probabilidad_baja": f"{probabilidades[0] * 100:.2f}%",
            "probabilidad_media": f"{probabilidades[1] * 100:.2f}%",
            "probabilidad_alta": f"{probabilidades[2] * 100:.2f}%"
        },
        "caracteristicas_detectadas": {
            "bordes": f"{caracteristicas['bordes']:.4f}",
            "oscuridad": f"{caracteristicas['oscuridad']:.4f}",
            "rojo": f"{caracteristicas['rojo']:.4f}",
            "brillo": f"{caracteristicas['brillo']:.4f}",
            "contraste": f"{caracteristicas['contraste']:.4f}"
        }
    }