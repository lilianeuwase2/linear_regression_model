# Maize Yield Prediction Under Climate Change

## Mission and problem

My mission is to help African farming communities protect their food supply from climate change.
Rising temperatures and less predictable rains are cutting maize harvests in Rwanda and the region, which leads to food shortages (Schlenker & Lobell, 2010; Abebaw, 2025).
Farmers cannot easily tell how much the climate and their own farming choices will change their harvest.
This project predicts the maize yield of a field (tonnes per hectare) from its climate and farming conditions.

## Dataset

*Maize management and yield of smallholder farmers in Sub-Saharan Africa between 2016 and 2022*, collected by One Acre Fund and the University of Nebraska–Lincoln. It has 14,773 real farm fields and 53 columns from Kenya, Tanzania, Rwanda, Burundi, Zambia, Uganda and Nigeria: hand-weighed maize yields, season rainfall, temperature, aridity, fertilizer use and farming practices. Licence: CC BY 4.0.

Source: [Zenodo record 11122388](https://zenodo.org/records/11122388) (DOI: [10.5281/zenodo.11115815](https://doi.org/10.5281/zenodo.11115815))

## API: public Swagger UI

**https://maize-yield-api-j1gx.onrender.com/docs**

- `POST /predict`: predicted maize yield for one field
- `POST /retrain`: upload a CSV of new fields to update the model
- The API runs on Render's free plan, which sleeps when unused: the first request can take up to a minute.

## Video demo

YouTube: 

## How to run the mobile app

1. Install [Flutter](https://docs.flutter.dev/get-started/install) and Android Studio, then create an Android emulator in Android Studio (**Device Manager → Create device**). You can also use an Android phone with USB debugging turned on.
2. Clone this repository:
   ```bash
   git clone https://github.com/lilianeuwase2/linear_regression_model.git
   ```
3. Go to the app folder:
   ```bash
   cd linear_regression_model/summative/FlutterApp
   ```
4. Install the app's packages:
   ```bash
   flutter pub get
   ```
5. Start the emulator (Android Studio → **Device Manager → ▶**) and check that Flutter sees it:
   ```bash
   flutter devices
   ```
6. Run the app:
   ```bash
   flutter run
   ```
7. Fill in the 10 fields, for example: country `Rwanda`, rainfall `900`, temperature `20`, aridity index `1.2`, nitrogen `40`, phosphorus `20`, fertilizer in the planting hole `yes`, hybrid seed `yes`, pest damage `no`, too much rain `no`. Then tap **Predict**. The predicted yield per hectare appears below the button. Invalid values show an error message in the same place.

The app calls the deployed API, so you do not need to run a server on your computer.

## Repository structure

```
linear_regression_model/
├── README.md
└── summative/
    ├── pyproject.toml, uv.lock        # uv project and pinned packages
    ├── linear_regression/
    │   ├── multivariate.ipynb         # data exploration, four models, best model
    │   ├── One_Acre_Fund_MEL_maize_survey_data_2016-2022.csv
    │   └── models/                    # all four trained models
    ├── API/
    │   ├── prediction.py              # FastAPI: /predict, /retrain route, CORS, input rules
    │   ├── retrain.py                 # retraining steps used by /retrain
    │   ├── pyproject.toml, uv.lock    # uv project for the API only
    │   ├── requirements.txt           # exported from uv, installed by Render
    │   ├── best_model.pkl             # random forest pipeline (lowest test MSE)
    │   └── data/                      # training, test and new-data CSV files for /retrain
    └── FlutterApp/                    # one-page Flutter mobile app
```

## References

- Abebaw, S. (2025). A global review of the impacts of climate change and variability on agricultural productivity and farmers' adaptation strategies. *Food Science & Nutrition*, 13(5), e70260. https://doi.org/10.1002/fsn3.70260
- Schlenker, W., & Lobell, D. B. (2010). Robust negative impacts of climate change on African agriculture. *Environmental Research Letters*, 5(1), 014010. https://doi.org/10.1088/1748-9326/5/1/014010
