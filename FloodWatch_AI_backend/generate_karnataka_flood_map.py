import json
import joblib
import numpy as np
import pandas as pd
import tensorflow as tf

# ==========================================================
# FLOODWATCH - KARNATAKA FLOOD RISK GRID
# ==========================================================

CSV_FILE = "FloodSafe_FINAL_AI_Training_Dataset.csv"
MODEL_FILE = "flood_model.keras"
SCALER_FILE = "scaler.pkl"

OUTPUT_FILE = "karnataka_flood_risk_grid.json"

# ==========================================================
# KARNATAKA BOUNDARY
# ==========================================================

LAT_MIN = 11.5
LAT_MAX = 18.5

LON_MIN = 74.0
LON_MAX = 78.7

# Grid resolution.
#
# 0.05 degrees gives a reasonably detailed prototype.
#
# Smaller value = more cells and slower processing.
#
GRID_STEP = 0.05

# ==========================================================
# LOAD MODEL
# ==========================================================

print("=" * 60)
print("FLOODWATCH KARNATAKA FLOOD-RISK GRID")
print("=" * 60)

print("\nLoading TensorFlow model...")

model = tf.keras.models.load_model(
    MODEL_FILE
)

print("Model loaded.")

# ==========================================================
# LOAD SCALER
# ==========================================================

print("\nLoading scaler...")

scaler = joblib.load(
    SCALER_FILE
)

print("Scaler loaded.")

# ==========================================================
# LOAD DATASET
# ==========================================================

print("\nLoading training dataset...")

df = pd.read_csv(
    CSV_FILE
)

# ==========================================================
# FILTER KARNATAKA
# ==========================================================

df = df[
    (df["latitude"] >= LAT_MIN)
    & (df["latitude"] <= LAT_MAX)
    & (df["longitude"] >= LON_MIN)
    & (df["longitude"] <= LON_MAX)
].copy()

print(
    f"Karnataka records: {len(df)}"
)

# ==========================================================
# FEATURES
# ==========================================================

FEATURES = [
    "latitude",
    "longitude",
    "rainfall_1day",
    "rainfall_3day",
    "rainfall_7day",
    "ground_elevation_m",
    "river_distance_km",
]

df = df.dropna(
    subset=FEATURES
)

# ==========================================================
# CREATE GRID
# ==========================================================

print("\nCreating Karnataka prediction grid...")

latitudes = np.arange(
    LAT_MIN,
    LAT_MAX + GRID_STEP,
    GRID_STEP
)

longitudes = np.arange(
    LON_MIN,
    LON_MAX + GRID_STEP,
    GRID_STEP
)

print(
    f"Latitude cells: {len(latitudes)}"
)

print(
    f"Longitude cells: {len(longitudes)}"
)

print(
    f"Total cells: "
    f"{len(latitudes) * len(longitudes)}"
)

# ==========================================================
# FIND NEAREST DATA RECORD
# ==========================================================

def nearest_record(
    latitude,
    longitude
):
    distance = (
        (df["latitude"] - latitude) ** 2
        +
        (df["longitude"] - longitude) ** 2
    )

    index = distance.idxmin()

    return df.loc[index]


# ==========================================================
# GENERATE GRID PREDICTIONS
# ==========================================================

grid = []

total = (
    len(latitudes)
    *
    len(longitudes)
)

counter = 0

for latitude in latitudes:

    for longitude in longitudes:

        counter += 1

        nearest = nearest_record(
            latitude,
            longitude
        )

        # --------------------------------------------------
        # IMPORTANT
        # --------------------------------------------------
        # We use the grid coordinate for latitude/longitude.
        #
        # Environmental variables come from the nearest
        # available record in your dataset.
        # --------------------------------------------------

        values = [[

            latitude,

            longitude,

            nearest[
                "rainfall_1day"
            ],

            nearest[
                "rainfall_3day"
            ],

            nearest[
                "rainfall_7day"
            ],

            nearest[
                "ground_elevation_m"
            ],

            nearest[
                "river_distance_km"
            ],

        ]]

        values = np.array(
            values,
            dtype=np.float32
        )

        scaled_values = scaler.transform(
            values
        )

        probability = float(
            model.predict(
                scaled_values,
                verbose=0
            )[0][0]
        )

        # --------------------------------------------------
        # RISK LEVEL
        # --------------------------------------------------

        if probability < 0.40:

            risk = "green"

        elif probability < 0.70:

            risk = "orange"

        else:

            risk = "red"

        # --------------------------------------------------
        # CELL BOUNDARY
        # --------------------------------------------------

        lat2 = latitude + GRID_STEP
        lon2 = longitude + GRID_STEP

        grid.append({

            "latitude": round(
                float(latitude),
                5
            ),

            "longitude": round(
                float(longitude),
                5
            ),

            "latitude2": round(
                float(lat2),
                5
            ),

            "longitude2": round(
                float(lon2),
                5
            ),

            "probability": round(
                probability,
                5
            ),

            "risk": risk,

        })

        if counter % 500 == 0:

            print(
                f"Processed "
                f"{counter}/{total}"
            )

# ==========================================================
# SAVE JSON
# ==========================================================

print("\nSaving flood-risk grid...")

output = {

    "region":
        "Karnataka, India",

    "model":
        "FloodWatch Karnataka Flood Model",

    "grid_step":
        GRID_STEP,

    "thresholds": {

        "green":
            0.40,

        "orange":
            0.70,

    },

    "risk_definition": {

        "green":
            "probability < 0.40",

        "orange":
            "0.40 <= probability < 0.70",

        "red":
            "probability >= 0.70",

    },

    "cells":
        grid,

}

with open(
    OUTPUT_FILE,
    "w"
) as file:

    json.dump(
        output,
        file,
        indent=2
    )

# ==========================================================
# SUMMARY
# ==========================================================

green_count = sum(
    1
    for cell in grid
    if cell["risk"] == "green"
)

orange_count = sum(
    1
    for cell in grid
    if cell["risk"] == "orange"
)

red_count = sum(
    1
    for cell in grid
    if cell["risk"] == "red"
)

print("\n" + "=" * 60)

print("KARNATAKA FLOOD GRID COMPLETE")

print("=" * 60)

print(
    f"\nTotal cells: "
    f"{len(grid)}"
)

print(
    f"GREEN cells: "
    f"{green_count}"
)

print(
    f"ORANGE cells: "
    f"{orange_count}"
)

print(
    f"RED cells: "
    f"{red_count}"
)

print(
    f"\nOutput: "
    f"{OUTPUT_FILE}"
)

print(
    "\nDone."
)