from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import tensorflow as tf
import joblib
import numpy as np
import json
import requests
import time
import hashlib
import os

from fastapi import Header

from alert_monitor import run_alert_check
from pathlib import Path


# ============================================================
# FLOODWATCH AI BACKEND
# ============================================================

BASE_DIR = Path(__file__).resolve().parent

MODEL_FILE = BASE_DIR / "flood_model.keras"
SCALER_FILE = BASE_DIR / "scaler.pkl"
METADATA_FILE = BASE_DIR / "model_metadata.json"


# ============================================================
# LOAD MODEL
# ============================================================

print("Loading FloodWatch AI model...")

model = tf.keras.models.load_model(MODEL_FILE)

print("Loading scaler...")

scaler = joblib.load(SCALER_FILE)

print("Loading metadata...")

with open(METADATA_FILE, "r") as f:
    metadata = json.load(f)

print("FloodWatch AI loaded successfully.")


# ============================================================
# FASTAPI
# ============================================================

app = FastAPI(
    title="FloodWatch Karnataka AI API",
    version="1.0.0"
)


# Flutter Web needs CORS when the API is running on the local PC.
# Restrict this to known origins in production.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)
@app.middleware("http")
async def add_private_network_header(request, call_next):
    response = await call_next(request)

    if request.headers.get("access-control-request-private-network") == "true":
        response.headers["access-control-allow-private-network"] = "true"

    return response

# ============================================================
# FEATURES
# ============================================================

FEATURES = [
    "latitude",
    "longitude",
    "rainfall_1day",
    "rainfall_3day",
    "rainfall_7day",
    "ground_elevation_m",
    "river_distance_km",
]


# ============================================================
# REQUEST MODEL
# ============================================================

class FloodPredictionRequest(BaseModel):

    latitude: float = Field(...)

    longitude: float = Field(...)

    rainfall_1day: float = Field(..., ge=0)

    rainfall_3day: float = Field(..., ge=0)

    rainfall_7day: float = Field(..., ge=0)

    ground_elevation_m: float = Field(...)

    river_distance_km: float = Field(..., ge=0)


# ============================================================
# HEALTH CHECK
# ============================================================

@app.get("/")
def root():

    return {
        "app": "FloodWatch",
        "status": "running",
        "model": "FloodWatch Karnataka Flood Model"
    }


# ============================================================
# MODEL INFORMATION
# ============================================================

@app.get("/model-info")
def model_info():

    return {
        "model_name": metadata.get("model_name"),
        "region": metadata.get("region"),
        "features": FEATURES,
        "target": metadata.get("target"),
        "green_threshold": metadata.get("green_threshold"),
        "orange_threshold": metadata.get("orange_threshold"),
        "risk_levels": metadata.get("risk_levels"),
        "roc_auc": metadata.get("roc_auc")
    }


# ============================================================
# FLOOD PREDICTION
# ============================================================

@app.post("/predict")
def predict_flood(request: FloodPredictionRequest):

    try:
        # ------------------------------------------------
        # CREATE FEATURE ARRAY
        # ------------------------------------------------

        input_data = np.array(
            [[
                request.latitude,
                request.longitude,
                request.rainfall_1day,
                request.rainfall_3day,
                request.rainfall_7day,
                request.ground_elevation_m,
                request.river_distance_km,
            ]],
            dtype=np.float32,
        )

        # ------------------------------------------------
        # APPLY TRAINING SCALER
        # ------------------------------------------------

        scaled_input = scaler.transform(input_data)

        # ------------------------------------------------
        # TENSORFLOW PREDICTION
        # ------------------------------------------------

        prediction = model.predict(
            scaled_input,
            verbose=0,
        )

        probability = float(prediction[0][0])

        if not np.isfinite(probability):
            raise ValueError("AI model returned an invalid probability.")

        probability = max(0.0, min(1.0, probability))

        # ------------------------------------------------
        # RISK CLASSIFICATION
        # ------------------------------------------------

        if probability < 0.40:
            risk_level = "LOW"
            risk_color = "green"

        elif probability < 0.70:
            risk_level = "MODERATE"
            risk_color = "orange"

        else:
            risk_level = "HIGH"
            risk_color = "red"

        risk_index = round(probability * 100)

        # ------------------------------------------------
        # RESPONSE
        # ------------------------------------------------

        return {
            "success": True,

            # AI prediction
            "probability": round(probability, 4),
            "risk_index": risk_index,
            "risk_level": risk_level,
            "risk_color": risk_color,

            # Location
            "latitude": request.latitude,
            "longitude": request.longitude,

            "location": {
                "latitude": request.latitude,
                "longitude": request.longitude,
            },

            # Rainfall values supplied to the model
            "rainfall": request.rainfall_1day,
            "rainfall_1day": request.rainfall_1day,
            "rainfall_3day": request.rainfall_3day,
            "rainfall_7day": request.rainfall_7day,

            # Environmental inputs
            "ground_elevation_m": request.ground_elevation_m,
            "river_distance_km": request.river_distance_km,

            # Keep the original inputs object for compatibility
            "inputs": {
                "rainfall_1day": request.rainfall_1day,
                "rainfall_3day": request.rainfall_3day,
                "rainfall_7day": request.rainfall_7day,
                "ground_elevation_m": request.ground_elevation_m,
                "river_distance_km": request.river_distance_km,
            },

            # These measurements are not produced by this model.
            "waterLevel": None,
            "dangerLevel": None,
            "ground_humidity": None,
            "rainfallTrend": None,

            "available_metrics": [
                "probability",
                "risk_index",
                "risk_level",
                "rainfall_1day",
                "rainfall_3day",
                "rainfall_7day",
                "ground_elevation_m",
                "river_distance_km",
            ],
        }

    except Exception as e:

        print("FLOOD PREDICTION ERROR:", str(e))

        raise HTTPException(
            status_code=500,
            detail=str(e),
        )
# ============================================================
# LIVE MAP RAINFALL + FLOOD RISK
# ============================================================

WEATHER_GRID_STEP = 0.25
WEATHER_BATCH_SIZE = 50
MAP_RISK_CACHE_SECONDS = 300  # 5 minutes

_map_risk_cache = {
    "key": None,
    "time": 0.0,
    "result": None,
}


class MapLocation(BaseModel):
    latitude: float
    longitude: float
    base_risk: str


class MapRiskRequest(BaseModel):
    locations: list[MapLocation]


def normalize_base_risk(base_risk: str) -> str:
    """
    Convert the flood-grid/model naming into:
    GREEN / ORANGE / RED
    """

    value = str(base_risk).strip().upper()

    if value in ("RED", "HIGH"):
        return "RED"

    if value in ("ORANGE", "MODERATE", "MEDIUM"):
        return "ORANGE"

    if value in ("GREEN", "LOW"):
        return "GREEN"

    # Unknown values are treated as LOW/GREEN
    return "GREEN"


def classify_rainfall(rainfall_mm: float):
    """
    Rainfall classification for the next 24 hours.
    """

    if rainfall_mm >= 30:
        return "HIGH"

    elif rainfall_mm >= 10:
        return "MEDIUM"

    else:
        return "LOW"


def calculate_final_risk(
    base_risk: str,
    rainfall_level: str,
):
    """
    Exact FloodWatch map rules:

    RED + HIGH   -> RED
    RED + MEDIUM -> ORANGE
    RED + LOW    -> GREEN

    ORANGE + HIGH        -> ORANGE
    ORANGE + MEDIUM/LOW  -> GREEN

    GREEN + anything     -> GREEN
    """

    base_risk = normalize_base_risk(base_risk)
    rainfall_level = rainfall_level.upper()

    # GREEN base risk always stays GREEN
    if base_risk == "GREEN":
        return "GREEN", "green"

    # RED base risk
    if base_risk == "RED":

        if rainfall_level == "HIGH":
            return "RED", "red"

        elif rainfall_level == "MEDIUM":
            return "ORANGE", "orange"

        else:
            return "GREEN", "green"

    # ORANGE base risk
    if base_risk == "ORANGE":

        if rainfall_level == "HIGH":
            return "ORANGE", "orange"

        else:
            return "GREEN", "green"

    return "GREEN", "green"


def weather_grid_key(
    latitude: float,
    longitude: float,
):
    """
    Put every flood cell into a 0.25 degree weather grid.

    Example:

    13.07, 75.06
        ->
    one shared Open-Meteo weather point.

    This prevents thousands of duplicate weather requests.
    """

    lat_index = int(
        round(latitude / WEATHER_GRID_STEP)
    )

    lon_index = int(
        round(longitude / WEATHER_GRID_STEP)
    )

    return lat_index, lon_index


def weather_grid_coordinates(key):
    """
    Convert a weather-grid key back to coordinates.
    """

    lat_index, lon_index = key

    latitude = lat_index * WEATHER_GRID_STEP
    longitude = lon_index * WEATHER_GRID_STEP

    return latitude, longitude


def create_map_cache_key(
    locations: list[MapLocation],
):
    """
    Create a fingerprint for the current flood map.

    If Flutter sends the same 13,395 cells again,
    we can return the cached result.
    """

    text = "|".join(
        f"{location.latitude:.5f},"
        f"{location.longitude:.5f},"
        f"{location.base_risk}"
        for location in locations
    )

    return hashlib.sha1(
        text.encode("utf-8")
    ).hexdigest()


@app.post("/map-risk")
def map_risk(request: MapRiskRequest):

    global _map_risk_cache

    try:

        # --------------------------------------------------------
        # EMPTY REQUEST
        # --------------------------------------------------------

        if not request.locations:

            return {
                "success": True,
                "locations": [],
            }

        # --------------------------------------------------------
        # CACHE CHECK
        # --------------------------------------------------------

        cache_key = create_map_cache_key(
            request.locations
        )

        current_time = time.time()

        if (
            _map_risk_cache["key"] == cache_key
            and
            _map_risk_cache["result"] is not None
            and
            current_time - _map_risk_cache["time"]
            < MAP_RISK_CACHE_SECONDS
        ):

            print(
                "MAP RISK CACHE HIT:",
                len(request.locations),
                "locations"
            )

            return _map_risk_cache["result"]

        print(
            "MAP RISK REQUEST:",
            len(request.locations),
            "flood cells"
        )

        # --------------------------------------------------------
        # STEP 1
        # CREATE UNIQUE WEATHER GRID
        # --------------------------------------------------------

        weather_points = {}

        for location in request.locations:

            key = weather_grid_key(
                location.latitude,
                location.longitude,
            )

            if key not in weather_points:

                weather_points[key] = (
                    location.latitude,
                    location.longitude,
                )

        print(
            "UNIQUE WEATHER GRID POINTS:",
            len(weather_points)
        )

        # --------------------------------------------------------
        # STEP 2
        # REQUEST OPEN-METEO ONLY FOR UNIQUE POINTS
        # --------------------------------------------------------

        weather_items = list(
            weather_points.items()
        )

        rainfall_by_grid = {}

        open_meteo_request_count = 0

        url = (
            "https://api.open-meteo.com/v1/forecast"
        )

        for start in range(
            0,
            len(weather_items),
            WEATHER_BATCH_SIZE,
        ):

            batch = weather_items[
                start:
                start + WEATHER_BATCH_SIZE
            ]

            coordinates = [
                weather_grid_coordinates(key)
                for key, _ in batch
            ]

            latitudes = ",".join(
                str(round(latitude, 4))
                for latitude, longitude
                in coordinates
            )

            longitudes = ",".join(
                str(round(longitude, 4))
                for latitude, longitude
                in coordinates
            )

            params = {
                "latitude": latitudes,
                "longitude": longitudes,
                "hourly": "rain",
                "forecast_days": 1,
                "timezone": "auto",
            }

            open_meteo_request_count += 1

            print(
                "OPEN-METEO REQUEST:",
                open_meteo_request_count,
                "| points:",
                len(batch)
            )

            response = requests.get(
                url,
                params=params,
                timeout=30,
            )

            response.raise_for_status()

            weather_data = response.json()

            # Multiple coordinates return a list.
            if isinstance(weather_data, dict):
                weather_data = [
                    weather_data
                ]

            # ----------------------------------------------------
            # READ RAINFALL FOR EACH WEATHER GRID POINT
            # ----------------------------------------------------

            for index, (key, _) in enumerate(batch):

                if index >= len(weather_data):
                    continue

                weather = weather_data[index]

                hourly = weather.get(
                    "hourly",
                    {}
                )

                rainfall_values = hourly.get(
                    "rain",
                    []
                )

                rainfall_mm = sum(
                    float(value or 0)
                    for value in rainfall_values
                )

                rainfall_by_grid[key] = round(
                    rainfall_mm,
                    2,
                )

        print(
            "OPEN-METEO REQUESTS TOTAL:",
            open_meteo_request_count
        )

        # --------------------------------------------------------
        # STEP 3
        # CREATE FINAL RESULT FOR ALL FLOOD CELLS
        # --------------------------------------------------------

        results = []

        for location in request.locations:

            key = weather_grid_key(
                location.latitude,
                location.longitude,
            )

            rainfall_mm = rainfall_by_grid.get(
                key,
                0.0,
            )

            rainfall_level = classify_rainfall(
                rainfall_mm
            )

            base_risk = normalize_base_risk(
                location.base_risk
            )

            final_risk, final_color = (
                calculate_final_risk(
                    base_risk,
                    rainfall_level,
                )
            )

            results.append({

                # Original flood-cell location
                "latitude":
                    location.latitude,

                "longitude":
                    location.longitude,

                # Base model/grid risk
                "base_risk":
                    base_risk,

                # Live Open-Meteo rainfall
                "rainfall_mm":
                    rainfall_mm,

                "rainfall_level":
                    rainfall_level,

                # Final combined result
                "final_risk":
                    final_risk,

                "final_color":
                    final_color,
            })

        # --------------------------------------------------------
        # STEP 4
        # FINAL RESPONSE
        # --------------------------------------------------------

        result = {
            "success": True,
            "locations": results,
        }

        # --------------------------------------------------------
        # SAVE CACHE
        # --------------------------------------------------------

        _map_risk_cache = {
            "key": cache_key,
            "time": time.time(),
            "result": result,
        }

        print(
            "MAP RISK COMPLETE:",
            len(results),
            "locations"
        )

        return result

    except requests.RequestException as e:

        print(
            "OPEN-METEO ERROR:",
            e
        )

        raise HTTPException(
            status_code=502,
            detail=(
                "Open-Meteo request failed: "
                f"{str(e)}"
            ),
        )

    except Exception as e:

        print(
            "MAP RISK ERROR:",
            e
        )

        raise HTTPException(
            status_code=500,
            detail=str(e),
        )
    # ============================================================
# SCHEDULED FLOODGUARD ALERT MONITOR
# ============================================================

@app.post("/internal/run-alert-check")
def run_scheduled_alert_check(
    x_alert_secret: str | None = Header(default=None),
):

    expected_secret = os.getenv("ALERT_SCHEDULER_SECRET")

    if not expected_secret or x_alert_secret != expected_secret:

        raise HTTPException(
            status_code=403,
            detail="Forbidden",
        )

    try:

        return run_alert_check()

    except Exception:

        print("FloodGuard alert monitoring failed.")

        raise HTTPException(
            status_code=500,
            detail="Alert monitoring failed.",
        )


# ============================================================
# DAMAGE ASSESSMENT API ROUTE INTEGRATION
# ============================================================

try:
    import damage_assessment_api as damage_api

    app.mount("/uploads", StaticFiles(directory=str(damage_api.UPLOAD_DIR)), name="uploads")
    app.post("/assessments")(damage_api.create_assessment)
    app.get("/assessments")(damage_api.get_assessments)
    app.get("/assessments/{assessment_id}")(damage_api.get_assessment)
    app.delete("/assessments/{assessment_id}")(damage_api.delete_assessment)
    print("Damage Assessment API routes integrated into main backend.")
except Exception as e:
    print(f"Damage Assessment API integration notice: {e}")
