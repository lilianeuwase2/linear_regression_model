"""Maize Yield Prediction API.

Predicts maize yield (tonnes per hectare) for one farm field from climate and
farming conditions using the best model from the notebook which is random forest 

Routes:
    POST /predict  -> predicted yield for one field
    POST /retrain  -> upload a CSV of new fields; the model learns from it and is used right away
    GET  /docs     -> Swagger UI (made automatically by FastAPI)

The retraining steps live in retrain.py; the /retrain route below calls them.
"""

import io
from typing import Literal

import joblib
import pandas as pd
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict, Field

# settings and retraining steps shared with retrain.py
from retrain import FEATURES, MODEL_PATH, check_new_data, retrain_model

model = joblib.load(MODEL_PATH)   # load the saved model once, when the API starts

# app and CORS

app = FastAPI(
    title="Maize Yield Prediction API",
    description="Predicts maize yield (t/ha) for a farm field in East and Southern Africa "
                "from rainfall, temperature, dryness, fertilizer and farming practices.",
    version="1.0.0",
)
# CORS controls which WEBSITES may call this API from a visitor's browser.
# ALLOW:
#   - origins: only my own Render site (where Swagger UI runs) and the local address
#     of my Flutter app if I test it as a web page (flutter run -d chrome --web-port 8080).
#     No wildcard "*", so the browser blocks every other website.
#   - methods: GET (to open /docs) and POST (/predict and /retrain). PUT, PATCH and
#     DELETE are not needed, so they are blocked.
#   - headers: only Content-Type and Accept, the two headers a JSON request or a
#     file upload needs.
# RESTRICT:
#   - credentials: False. The API has no logins or cookies, so browsers must not send them.
# WHY: allowing only what the API needs stops unknown websites from using it.
# Note: my Flutter MOBILE app is not a browser, so CORS does not apply to it.

ALLOWED_ORIGINS = [
    "https://maize-yield-api-j1gx.onrender.com",   
    "http://localhost:8080",                  
    "http://127.0.0.1:8080",
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type", "Accept"],
    allow_credentials=False,
)



# input and output rules  
class FieldInput(BaseModel):
    """The 10 inputs for one farm field. Every field has a type and a realistic range."""

    model_config = ConfigDict(strict=True, extra="forbid")   # no type guessing, no unknown fields

    rainfall_mm: float = Field(ge=200, le=2500, description="Total rain during the season (mm)", examples=[900])
    avg_temp_c: float = Field(ge=10, le=30, description="Average temperature during the maize season (°C)", examples=[20.0])
    aridity_index: float = Field(ge=0.3, le=3.0, description="Wetness of the location: higher = wetter", examples=[1.2])
    nitrogen_kg_ha: float = Field(ge=0, le=350, description="Nitrogen fertilizer applied (kg per hectare)", examples=[40])
    phosphorus_kg_ha: float = Field(ge=0, le=150, description="Phosphorus fertilizer applied (kg per hectare)", examples=[20])
    country: Literal["Burundi", "Kenya", "Nigeria", "Rwanda", "Tanzania", "Uganda", "Zambia"] = Field(examples=["Rwanda"])
    hybrid_seed: Literal["yes", "no"] = Field(description="Was hybrid seed planted?", examples=["yes"])
    pest_damage: Literal["yes", "no"] = Field(description="Did pests damage the field?", examples=["no"])
    excess_water: Literal["yes", "no"] = Field(description="Did too much rain damage the field?", examples=["no"])
    fertilizer_in_hole: Literal["yes", "no"] = Field(description="Was fertilizer put in the planting hole?", examples=["yes"])


class PredictionOutput(BaseModel):
    predicted_yield_t_ha: float
    predicted_yield_kg_ha: float


#prediction 

def predict_yield(field: dict) -> float:
    """Same function as in the notebook: predict maize yield (t/ha) for one field.
    The notebook version loads the model from the file each time; here it is loaded
    once at startup, which is faster, and replaced after each retrain."""
    row = pd.DataFrame([field])[FEATURES]
    return float(model.predict(row)[0])


@app.api_route("/", methods=["GET", "HEAD"])
def home():
    return {"message": "Maize Yield Prediction API. Open /docs to try it."}


@app.post("/predict", response_model=PredictionOutput)
def predict(field: FieldInput):
    prediction = predict_yield(field.model_dump())
    return {
        "predicted_yield_t_ha": round(prediction, 2),
        "predicted_yield_kg_ha": round(prediction * 1000),
    }


# Retraining the model with new data (the steps are in retrain.py)
@app.post("/retrain")
async def retrain(file: UploadFile = File(..., description="CSV with the 10 input columns and yield_t_ha")):
    global model

    if not file.filename.lower().endswith(".csv"):
        raise HTTPException(status_code=400, detail="Please upload a .csv file.")
    try:
        new_df = pd.read_csv(io.BytesIO(await file.read()))
    except Exception:
        raise HTTPException(status_code=400, detail="The file could not be read as a CSV.")

    new_df = check_new_data(new_df, FieldInput)          # same rules as /predict
    model, summary = retrain_model(model, new_df)       # /predict uses the new model straight away
    return {"message": "Model retrained and now in use.", **summary}
