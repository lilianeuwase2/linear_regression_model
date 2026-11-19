"""Maize Yield Prediction API.

Predicts maize yield (tonnes per hectare) for one farm field from climate and
farming conditions, using the best model from the notebook (a random forest).

Routes:
    POST /predict  -> predicted yield for one field
    POST /retrain  -> upload a CSV of new fields; the model learns from it and is used right away
    GET  /docs     -> Swagger UI (made automatically by FastAPI)
"""

import copy
import io
import os
from typing import Literal

import joblib
import pandas as pd
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict, Field, ValidationError
from sklearn.ensemble import RandomForestRegressor
from sklearn.linear_model import SGDRegressor
from sklearn.metrics import mean_squared_error

# setting and files
BASE_DIR = os.path.dirname(os.path.abspath(__file__))     
MODEL_PATH = os.path.join(BASE_DIR, "best_model.pkl")
TRAIN_PATH = os.path.join(BASE_DIR, "data", "train_data.csv")
TEST_PATH = os.path.join(BASE_DIR, "data", "test_data.csv")

FEATURES = [
    "rainfall_mm", "avg_temp_c", "aridity_index", "nitrogen_kg_ha", "phosphorus_kg_ha",
    "country", "hybrid_seed", "pest_damage", "excess_water", "fertilizer_in_hole",
]
NUMERIC_FEATURES = FEATURES[:5]
TARGET = "yield_t_ha"
TREES_TO_ADD = 50         

model = joblib.load(MODEL_PATH)  

# app and CORS

app = FastAPI(
    title="Maize Yield Prediction API",
    description="Predicts maize yield (t/ha) for a farm field in East and Southern Africa "
                "from rainfall, temperature, dryness, fertilizer and farming practices.",
    version="1.0.0",
)
#CORS controls which websites may call this API from a visitor's browser
# Allow origin 
# Allow methods: GET and POST
# Allow headers: Content-Type and Accept
# Restrict credentials From being sent (cookies,login) to the API


ALLOWED_ORIGINS = [
    "https://maize-yield-api.onrender.com",   
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


@app.get("/")
def home():
    return {"message": "Maize Yield Prediction API. Open /docs to try it."}


@app.post("/predict", response_model=PredictionOutput)
def predict(field: FieldInput):
    prediction = predict_yield(field.model_dump())
    return {
        "predicted_yield_t_ha": round(prediction, 2),
        "predicted_yield_kg_ha": round(prediction * 1000),
    }


# retraining the model with new data
def check_new_data(new_df: pd.DataFrame) -> pd.DataFrame:
    """Check that the uploaded CSV has the right columns and realistic values."""
    missing = [col for col in FEATURES + [TARGET] if col not in new_df.columns]
    if missing:
        raise HTTPException(status_code=400, detail=f"The CSV is missing these columns: {missing}")

    new_df = new_df[FEATURES + [TARGET]].dropna()
    if new_df.empty:
        raise HTTPException(status_code=400, detail="The CSV has no complete rows.")

    try:
        new_df[NUMERIC_FEATURES + [TARGET]] = new_df[NUMERIC_FEATURES + [TARGET]].astype(float)
    except ValueError:
        raise HTTPException(status_code=400, detail="Numeric columns must contain numbers only.")

    errors = []
    for i, row in enumerate(new_df.to_dict(orient="records"), start=2):   # row 1 is the header
        try:
            FieldInput(**{col: row[col] for col in FEATURES})   # same rules as /predict
        except ValidationError as e:
            errors.append(f"row {i}: {e.errors()[0]['loc'][0]} - {e.errors()[0]['msg']}")
        if not 0 <= row[TARGET] <= 15:
            errors.append(f"row {i}: {TARGET} must be between 0 and 15 t/ha")
    if errors:
        raise HTTPException(status_code=422, detail=errors[:10])
    return new_df


@app.post("/retrain")
async def retrain(file: UploadFile = File(..., description="CSV with the 10 input columns and yield_t_ha")):
    global model

    if not file.filename.lower().endswith(".csv"):
        raise HTTPException(status_code=400, detail="Please upload a .csv file.")
    try:
        new_df = pd.read_csv(io.BytesIO(await file.read()))
    except Exception:
        raise HTTPException(status_code=400, detail="The file could not be read as a CSV.")
    new_df = check_new_data(new_df)

    train_df = pd.read_csv(TRAIN_PATH)
    test_df = pd.read_csv(TEST_PATH)
    combined = pd.concat([train_df, new_df], ignore_index=True)  

    # Work on a copy, so the live model keeps working if anything fails
    new_model = copy.deepcopy(model)
    preprocess = new_model.named_steps["preprocess"]   
    estimator = new_model.named_steps["model"]
    mse_before = mean_squared_error(test_df[TARGET], model.predict(test_df[FEATURES]))

    if isinstance(estimator, SGDRegressor):
        # Gradient descent: continue training the saved model on the new rows only
        estimator.partial_fit(preprocess.transform(new_df[FEATURES]), new_df[TARGET])
        how = "SGDRegressor: continued training with partial_fit on the new rows"
    elif isinstance(estimator, RandomForestRegressor):
        # Random forest: keep all existing trees and grow new ones on original + new data
        trees_before = estimator.n_estimators
        estimator.set_params(warm_start=True, n_estimators=trees_before + TREES_TO_ADD)
        estimator.fit(preprocess.transform(combined[FEATURES]), combined[TARGET])
        how = (f"RandomForest: kept the {trees_before} existing trees and added {TREES_TO_ADD} "
               f"new trees trained on the original data plus the new rows")
    else:
        # Any other model: refit on the original data plus the new rows
        estimator.fit(preprocess.transform(combined[FEATURES]), combined[TARGET])
        how = f"{type(estimator).__name__}: refit on the original data plus the new rows"

    mse_after = mean_squared_error(test_df[TARGET], new_model.predict(test_df[FEATURES]))

    joblib.dump(new_model, MODEL_PATH, compress=3)   
    combined.to_csv(TRAIN_PATH, index=False)          
    model = new_model                                
    return {
        "message": "Model retrained and now in use.",
        "method": how,
        "new_rows_used": len(new_df),
        "total_training_rows": len(combined),
        "test_mse_before": round(mse_before, 4),
        "test_mse_after": round(mse_after, 4),
    }