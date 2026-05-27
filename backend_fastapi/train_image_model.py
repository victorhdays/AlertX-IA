import random
import pandas as pd
import joblib

from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report

random.seed(42)

datos = []

for i in range(12000):
    bordes = random.uniform(0, 1)
    oscuridad = random.uniform(0, 1)
    rojo = random.uniform(0, 1)
    brillo = random.uniform(0, 1)
    contraste = random.uniform(0, 1)

    if bordes > 0.65 or oscuridad > 0.70 or rojo > 0.55:
        gravedad = 2
    elif bordes > 0.35 or oscuridad > 0.40 or rojo > 0.25:
        gravedad = 1
    else:
        gravedad = 0

    datos.append({
        "bordes": bordes,
        "oscuridad": oscuridad,
        "rojo": rojo,
        "brillo": brillo,
        "contraste": contraste,
        "gravedad_imagen": gravedad
    })

df = pd.DataFrame(datos)

X = df[["bordes", "oscuridad", "rojo", "brillo", "contraste"]]
y = df["gravedad_imagen"]

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.25, random_state=42
)

modelo = RandomForestClassifier(
    n_estimators=400,
    max_depth=12,
    random_state=42
)

modelo.fit(X_train, y_train)

pred = modelo.predict(X_test)

print("Accuracy imagen:", accuracy_score(y_test, pred))
print(classification_report(y_test, pred))

joblib.dump(modelo, "modelo_imagen.pkl")

print("Modelo de imagen guardado como modelo_imagen.pkl")