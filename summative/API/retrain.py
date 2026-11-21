"""Retraining for the Maize Yield Prediction API.

prediction.py calls these two functions when a CSV is uploaded to POST /retrain:
    check_new_data(new_df, FieldInput) -> checks the CSV with the same rules as /predict
    retrain_model(model, new_df)       -> teaches a copy of the model the new rows, saves it
                                          and returns it, so /predict can use it right away

The shared settings (file paths and column names) also live here, so prediction.py and
this file always use the same ones.
"""

import copy
import os

import joblib
import pandas as pd
from fastapi import HTTPException
from pydantic import ValidationError
from sklearn.ensemble import RandomForestRegressor
from sklearn.linear_model import SGDRegressor
from sklearn.metrics import mean_squared_error

# settings and files
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


# checking the uploaded CSV
def check_new_data(new_df: pd.DataFrame, input_schema) -> pd.DataFrame:
    """Check that the uploaded CSV has the right columns and realistic values.
    input_schema is the FieldInput class from prediction.py, so every row is checked
    with exactly the same rules as /predict."""
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
            input_schema(**{col: row[col] for col in FEATURES})   # same rules as /predict
        except ValidationError as e:
            errors.append(f"row {i}: {e.errors()[0]['loc'][0]} - {e.errors()[0]['msg']}")
        if not 0 <= row[TARGET] <= 15:
            errors.append(f"row {i}: {TARGET} must be between 0 and 15 t/ha")
    if errors:
        raise HTTPException(status_code=422, detail=errors[:10])
    return new_df


# Retraining the model with new data
def retrain_model(model, new_df: pd.DataFrame):
    """Update the model with the new rows. Returns the updated model and a summary."""
    train_df = pd.read_csv(TRAIN_PATH)
    test_df = pd.read_csv(TEST_PATH)
    combined = pd.concat([train_df, new_df], ignore_index=True)

    # Work on a copy, so the live model keeps working if anything fails
    new_model = copy.deepcopy(model)
    preprocess = new_model.named_steps["preprocess"]
    estimator = new_model.named_steps["model"]
    mse_before = mean_squared_error(test_df[TARGET], model.predict(test_df[FEATURES]))

    if isinstance(estimator, SGDRegressor):
        # Gradient descent continuing training the saved model on the new rows only
        estimator.partial_fit(preprocess.transform(new_df[FEATURES]), new_df[TARGET])
        how = "SGDRegressor: continued training with partial_fit on the new rows"
    elif isinstance(estimator, RandomForestRegressor):
        # Random forest keep all existing trees and grow new ones on original and new data
        trees_before = estimator.n_estimators
        estimator.set_params(warm_start=True, n_estimators=trees_before + TREES_TO_ADD)
        estimator.fit(preprocess.transform(combined[FEATURES]), combined[TARGET])
        how = (f"RandomForest: kept the {trees_before} existing trees and added {TREES_TO_ADD} "
               f"new trees trained on the original data plus the new rows")
    else:
        # Any other model refit on the original data plus the new rows
        estimator.fit(preprocess.transform(combined[FEATURES]), combined[TARGET])
        how = f"{type(estimator).__name__}: refit on the original data plus the new rows"

    mse_after = mean_squared_error(test_df[TARGET], new_model.predict(test_df[FEATURES]))

    joblib.dump(new_model, MODEL_PATH, compress=3)   # save the updated model
    combined.to_csv(TRAIN_PATH, index=False)          # the next retrain starts from all rows so far
    summary = {
        "method": how,
        "new_rows_used": len(new_df),
        "total_training_rows": len(combined),
        "test_mse_before": round(mse_before, 4),
        "test_mse_after": round(mse_after, 4),
    }
    return new_model, summary
