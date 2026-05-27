import random
import pandas as pd
import joblib

from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report

random.seed(42)

datos = []

for i in range(10000):
    velocidad = random.randint(0, 130)
    impacto = round(random.uniform(0, 10), 2)
    cantidad_reportes_zona = random.randint(0, 15)
    usuario_verificado = random.choice([0, 1])
    hora = random.randint(0, 23)
    descripcion_larga = random.choice([0, 1])
    zona_riesgo = random.randint(0, 2)

    if impacto >= 8 or velocidad >= 80 or zona_riesgo == 2:
        gravedad = 2
    elif impacto >= 4 or velocidad >= 35 or zona_riesgo == 1:
        gravedad = 1
    else:
        gravedad = 0

    puntos_falso = 0

    if usuario_verificado == 0:
        puntos_falso += 1

    if cantidad_reportes_zona == 0:
        puntos_falso += 1

    if descripcion_larga == 0:
        puntos_falso += 1

    if velocidad < 10 and impacto < 2:
        puntos_falso += 1

    reporte_falso = 1 if puntos_falso >= 3 else 0

    datos.append({
        "velocidad": velocidad,
        "impacto": impacto,
        "cantidad_reportes_zona": cantidad_reportes_zona,
        "usuario_verificado": usuario_verificado,
        "hora": hora,
        "descripcion_larga": descripcion_larga,
        "zona_riesgo": zona_riesgo,
        "gravedad": gravedad,
        "reporte_falso": reporte_falso
    })

df = pd.DataFrame(datos)

X = df[[
    "velocidad",
    "impacto",
    "cantidad_reportes_zona",
    "usuario_verificado",
    "hora",
    "descripcion_larga",
    "zona_riesgo"
]]

y_gravedad = df["gravedad"]
y_falso = df["reporte_falso"]

X_train_g, X_test_g, y_train_g, y_test_g = train_test_split(
    X, y_gravedad, test_size=0.25, random_state=42
)

modelo_gravedad = RandomForestClassifier(
    n_estimators=400,
    max_depth=12,
    random_state=42
)

modelo_gravedad.fit(X_train_g, y_train_g)

pred_g = modelo_gravedad.predict(X_test_g)

metricas_gravedad = classification_report(y_test_g, pred_g)

X_train_f, X_test_f, y_train_f, y_test_f = train_test_split(
    X, y_falso, test_size=0.25, random_state=42
)

modelo_falso = RandomForestClassifier(
    n_estimators=400,
    max_depth=12,
    random_state=42
)

modelo_falso.fit(X_train_f, y_train_f)

pred_f = modelo_falso.predict(X_test_f)

metricas_falso = classification_report(y_test_f, pred_f)

df.to_csv("dataset_accidentes_sintetico.csv", index=False)

joblib.dump(modelo_gravedad, "modelo_gravedad.pkl")
joblib.dump(modelo_falso, "modelo_falso.pkl")

with open("metricas_modelo.txt", "w", encoding="utf-8") as archivo:
    archivo.write("MODELO DE GRAVEDAD\n")
    archivo.write(f"Accuracy: {accuracy_score(y_test_g, pred_g)}\n\n")
    archivo.write(metricas_gravedad)

    archivo.write("\n\nMODELO DE REPORTE FALSO\n")
    archivo.write(f"Accuracy: {accuracy_score(y_test_f, pred_f)}\n\n")
    archivo.write(metricas_falso)

print("Modelos entrenados correctamente.")
print("Archivos creados:")
print("- modelo_gravedad.pkl")
print("- modelo_falso.pkl")
print("- dataset_accidentes_sintetico.csv")
print("- metricas_modelo.txt")