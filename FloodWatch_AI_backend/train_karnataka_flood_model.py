import json
import joblib
import numpy as np
import pandas as pd
import tensorflow as tf

from pathlib import Path

from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import (
    classification_report,
    confusion_matrix,
    roc_auc_score,
    precision_recall_fscore_support,
)

# ==========================================================
# FLOODWATCH - KARNATAKA FLOOD AI
# ==========================================================

CSV_FILE = "FloodSafe_FINAL_AI_Training_Dataset.csv"

MODEL_FILE = "flood_model.keras"
SCALER_FILE = "scaler.pkl"
METADATA_FILE = "model_metadata.json"

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

TARGET = "historical_flood"

# ==========================================================
# LOAD DATA
# ==========================================================

print("=" * 60)
print("FLOODWATCH KARNATAKA AI TRAINING")
print("=" * 60)

print("\nLoading dataset...")

df = pd.read_csv(CSV_FILE)

print(f"Dataset rows: {len(df)}")

# ==========================================================
# KEEP KARNATAKA GEOGRAPHIC REGION
# ==========================================================

print("\nFiltering Karnataka geographic region...")

# Approximate Karnataka bounding box.
# This prevents accidental records outside Karnataka.

KARNATAKA_LAT_MIN = 11.5
KARNATAKA_LAT_MAX = 18.5

KARNATAKA_LON_MIN = 74.0
KARNATAKA_LON_MAX = 78.7

df = df[
    (df["latitude"] >= KARNATAKA_LAT_MIN)
    & (df["latitude"] <= KARNATAKA_LAT_MAX)
    & (df["longitude"] >= KARNATAKA_LON_MIN)
    & (df["longitude"] <= KARNATAKA_LON_MAX)
].copy()

print(
    f"Karnataka-region records: {len(df)}"
)

# ==========================================================
# CHECK REQUIRED COLUMNS
# ==========================================================

required_columns = FEATURES + [TARGET]

missing_columns = [
    column
    for column in required_columns
    if column not in df.columns
]

if missing_columns:
    raise ValueError(
        f"Missing columns: {missing_columns}"
    )

# ==========================================================
# CLEAN DATA
# ==========================================================

print("\nCleaning data...")

df = df.dropna(
    subset=required_columns
)

# Remove invalid values

df = df[
    np.isfinite(
        df[FEATURES]
    ).all(axis=1)
]

df[TARGET] = df[TARGET].astype(int)

print(
    f"Records after cleaning: {len(df)}"
)

# ==========================================================
# SHOW TARGET DISTRIBUTION
# ==========================================================

print("\nFlood distribution:")

print(
    df[TARGET].value_counts()
)

# ==========================================================
# INPUT / OUTPUT
# ==========================================================

X = df[FEATURES].values.astype(
    np.float32
)

y = df[TARGET].values.astype(
    np.float32
)

# ==========================================================
# TRAIN / VALIDATION / TEST
# ==========================================================

print("\nSplitting dataset...")

X_train, X_temp, y_train, y_temp = train_test_split(
    X,
    y,
    test_size=0.30,
    random_state=42,
    stratify=y,
)

X_validation, X_test, y_validation, y_test = train_test_split(
    X_temp,
    y_temp,
    test_size=0.50,
    random_state=42,
    stratify=y_temp,
)

print(
    f"Training:   {len(X_train)}"
)

print(
    f"Validation: {len(X_validation)}"
)

print(
    f"Testing:    {len(X_test)}"
)

# ==========================================================
# SCALE FEATURES
# ==========================================================

print("\nScaling features...")

scaler = StandardScaler()

X_train = scaler.fit_transform(
    X_train
)

X_validation = scaler.transform(
    X_validation
)

X_test = scaler.transform(
    X_test
)

# ==========================================================
# CLASS WEIGHTS
# ==========================================================

negative_count = np.sum(
    y_train == 0
)

positive_count = np.sum(
    y_train == 1
)

total = negative_count + positive_count

class_weight = {
    0: total / (2 * negative_count),
    1: total / (2 * positive_count),
}

print("\nClass weights:")

print(class_weight)

# ==========================================================
# TENSORFLOW MODEL
# ==========================================================

print("\nCreating TensorFlow model...")

model = tf.keras.Sequential([
    tf.keras.layers.Input(
        shape=(len(FEATURES),)
    ),

    tf.keras.layers.Dense(
        64,
        activation="relu"
    ),

    tf.keras.layers.BatchNormalization(),

    tf.keras.layers.Dropout(
        0.30
    ),

    tf.keras.layers.Dense(
        32,
        activation="relu"
    ),

    tf.keras.layers.Dropout(
        0.20
    ),

    tf.keras.layers.Dense(
        16,
        activation="relu"
    ),

    tf.keras.layers.Dense(
        1,
        activation="sigmoid"
    ),
])

# ==========================================================
# COMPILE
# ==========================================================

model.compile(
    optimizer=tf.keras.optimizers.Adam(
        learning_rate=0.001
    ),

    loss="binary_crossentropy",

    metrics=[
        tf.keras.metrics.BinaryAccuracy(
            name="accuracy"
        ),

        tf.keras.metrics.Precision(
            name="precision"
        ),

        tf.keras.metrics.Recall(
            name="recall"
        ),

        tf.keras.metrics.AUC(
            name="auc"
        ),
    ],
)

model.summary()

# ==========================================================
# CALLBACKS
# ==========================================================

callbacks = [

    tf.keras.callbacks.EarlyStopping(
        monitor="val_auc",
        mode="max",
        patience=10,
        restore_best_weights=True,
    ),

    tf.keras.callbacks.ReduceLROnPlateau(
        monitor="val_auc",
        mode="max",
        factor=0.5,
        patience=4,
        min_lr=0.00001,
    ),
]

# ==========================================================
# TRAIN
# ==========================================================

print("\nStarting training...")

history = model.fit(
    X_train,
    y_train,

    validation_data=(
        X_validation,
        y_validation,
    ),

    epochs=100,

    batch_size=64,

    class_weight=class_weight,

    callbacks=callbacks,

    verbose=1,
)

# ==========================================================
# TEST MODEL
# ==========================================================

print("\nEvaluating model...")

results = model.evaluate(
    X_test,
    y_test,
    verbose=0,
)

for name, value in zip(
    model.metrics_names,
    results,
):
    print(
        f"{name}: {value:.4f}"
    )

# ==========================================================
# PREDICTIONS
# ==========================================================

probabilities = model.predict(
    X_test,
    verbose=0,
).flatten()

# ==========================================================
# FLOOD CLASSIFICATION
# ==========================================================

predictions = (
    probabilities >= 0.5
).astype(int)

# ==========================================================
# CLASSIFICATION REPORT
# ==========================================================

print("\nClassification report:")

print(
    classification_report(
        y_test,
        predictions,
        digits=4,
        zero_division=0,
    )
)

# ==========================================================
# CONFUSION MATRIX
# ==========================================================

matrix = confusion_matrix(
    y_test,
    predictions,
)

print("\nConfusion matrix:")

print(matrix)

# ==========================================================
# ROC AUC
# ==========================================================

auc = roc_auc_score(
    y_test,
    probabilities,
)

print(
    f"\nROC-AUC: {auc:.4f}"
)

# ==========================================================
# SAVE MODEL
# ==========================================================

print("\nSaving TensorFlow model...")

model.save(
    MODEL_FILE
)

# ==========================================================
# SAVE SCALER
# ==========================================================

print("Saving scaler...")

joblib.dump(
    scaler,
    SCALER_FILE
)

# ==========================================================
# SAVE METADATA
# ==========================================================

metadata = {

    "model_name":
        "FloodWatch Karnataka Flood Model",

    "region":
        "Karnataka, India",

    "features":
        FEATURES,

    "target":
        TARGET,

    "model_type":
        "TensorFlow binary flood probability model",

    "green_threshold":
        0.40,

    "orange_threshold":
        0.70,

    "risk_levels": {

        "green":
            "probability < 0.40",

        "orange":
            "0.40 <= probability < 0.70",

        "red":
            "probability >= 0.70",
    },

    "training_records":
        int(len(X_train)),

    "validation_records":
        int(len(X_validation)),

    "testing_records":
        int(len(X_test)),

    "roc_auc":
        float(auc),
}

with open(
    METADATA_FILE,
    "w"
) as file:

    json.dump(
        metadata,
        file,
        indent=4,
    )

# ==========================================================
# COMPLETE
# ==========================================================

print("\n" + "=" * 60)

print(
    "TRAINING COMPLETE"
)

print("=" * 60)

print(
    f"\nModel: {MODEL_FILE}"
)

print(
    f"Scaler: {SCALER_FILE}"
)

print(
    f"Metadata: {METADATA_FILE}"
)

print(
    "\nFloodWatch Karnataka AI model is ready."
)