import os
import time
import json
import logging
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo
import requests
import firebase_admin
from firebase_admin import credentials, firestore, messaging


# ============================================================
# CONFIGURATION
# ============================================================

BASE_DIR = Path(__file__).resolve().parent
GRID_FILE = BASE_DIR / "karnataka_flood_risk_grid.json"

WEATHER_GRID_STEP = 0.25
WEATHER_BATCH_SIZE = 50
TIMEZONE = ZoneInfo("Asia/Kolkata")

# WEATHER REPORT & FORECAST HOURS (IST)
WEATHER_REPORT_START_HOUR = int(os.getenv("WEATHER_REPORT_START_HOUR", "6"))
WEATHER_REPORT_END_HOUR = int(os.getenv("WEATHER_REPORT_END_HOUR", "22"))

MORNING_FORECAST_HOUR = int(os.getenv("MORNING_FORECAST_HOUR", "7"))
EVENING_FORECAST_HOUR = int(os.getenv("EVENING_FORECAST_HOUR", "19"))

# MONITOR INTERVAL (Minutes)
FLOOD_CHECK_INTERVAL_MINUTES = int(
    os.getenv("FLOOD_CHECK_INTERVAL_MINUTES", "15")
)

# TWO-HOUR FLOOD RISK THRESHOLDS (mm)
FLOOD_2H_MODERATE_RAIN_MM = float(
    os.getenv("FLOOD_2H_MODERATE_RAIN_MM", "10")
)

FLOOD_2H_HIGH_RAIN_MM = float(
    os.getenv("FLOOD_2H_HIGH_RAIN_MM", "20")
)

MIN_ESCALATED_CELLS = int(
    os.getenv("MIN_ESCALATED_CELLS", "5")
)


# ============================================================
# FIREBASE INITIALIZATION
# ============================================================

def get_firestore():
    if not firebase_admin._apps:
        service_account_json = os.environ.get("FIREBASE_SERVICE_ACCOUNT")

        if not service_account_json:
            # Check local file fallback if available
            local_key = BASE_DIR / "floodwatch-karnataka-2026-firebase-adminsdk-fbsvc-f01e0f4be9.json"
            if local_key.exists():
                cred = credentials.Certificate(str(local_key))
                firebase_admin.initialize_app(cred)
                return firestore.client()
            raise RuntimeError("FIREBASE_SERVICE_ACCOUNT environment variable or local key is missing.")

        try:
            service_account_info = json.loads(service_account_json)
        except json.JSONDecodeError as exc:
            raise RuntimeError("FIREBASE_SERVICE_ACCOUNT does not contain valid JSON.") from exc

        cred = credentials.Certificate(service_account_info)
        firebase_admin.initialize_app(cred)

    return firestore.client()


# ============================================================
# LOAD KARNATAKA FLOOD GRID
# ============================================================

with open(GRID_FILE, "r", encoding="utf-8") as file:
    GRID_DATA = json.load(file)

GRID_CELLS = GRID_DATA["cells"]


# ============================================================
# LOCATION & COORDINATE HELPERS
# ============================================================

def get_user_coordinates(data):
    location = data.get("location")

    latitude = None
    longitude = None

    if isinstance(location, dict):
        latitude = location.get("latitude")
        longitude = location.get("longitude")
    elif location is not None:
        latitude = getattr(location, "latitude", None)
        longitude = getattr(location, "longitude", None)

    if latitude is None:
        latitude = data.get("latitude")
    if longitude is None:
        longitude = data.get("longitude")

    try:
        latitude = float(latitude)
        longitude = float(longitude)

        if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
            return None

        return latitude, longitude
    except (TypeError, ValueError):
        return None


def weather_grid_key(latitude, longitude):
    return (
        round(latitude / WEATHER_GRID_STEP),
        round(longitude / WEATHER_GRID_STEP),
    )


def weather_grid_coordinates(key):
    return (
        key[0] * WEATHER_GRID_STEP,
        key[1] * WEATHER_GRID_STEP,
    )


def find_nearest_cell_index(latitude, longitude):
    if not (11.5 <= latitude <= 18.5 and 74.0 <= longitude <= 78.7):
        return None

    return min(
        range(len(GRID_CELLS)),
        key=lambda index: (
            (float(GRID_CELLS[index]["latitude"]) - latitude) ** 2
            + (float(GRID_CELLS[index]["longitude"]) - longitude) ** 2
        ),
    )


# ============================================================
# WEATHER CODE DESCRIPTIONS
# ============================================================

def describe_weather_code(code):
    """Convert an Open-Meteo WMO weather code into human-readable description."""
    try:
        code = int(code)
    except (TypeError, ValueError):
        return "Unknown weather"

    if code == 0:
        return "Sunny / Clear sky"
    if code == 1:
        return "Mainly clear"
    if code == 2:
        return "Partly cloudy"
    if code == 3:
        return "Overcast / Cloudy"
    if code in (45, 48):
        return "Foggy conditions"
    if code in (51, 53, 55, 56, 57):
        return "Light drizzle"
    if code in (61, 63, 65, 66, 67):
        return "Rainy"
    if code in (71, 73, 75, 77, 85, 86):
        return "Snow showers"
    if code in (80, 81, 82):
        return "Heavy rain showers"
    if code in (95, 96, 99):
        return "Thunderstorm with severe weather"
    return "Cloudy"


# ============================================================
# FETCH OPEN-METEO WEATHER & FORECAST DATA
# ============================================================

def fetch_forecast_data(weather_keys):
    """
    Fetch comprehensive hourly and daily weather metrics from Open-Meteo API.
    """
    weather_keys = list(weather_keys)
    weather_by_key = {}

    if not weather_keys:
        return weather_by_key

    now = datetime.now(TIMEZONE)
    current_hour = now.replace(minute=0, second=0, microsecond=0)
    end_2h = current_hour + timedelta(hours=2)
    end_3h = current_hour + timedelta(hours=3)
    end_24h = current_hour + timedelta(hours=24)

    url = "https://api.open-meteo.com/v1/forecast"

    for start in range(0, len(weather_keys), WEATHER_BATCH_SIZE):
        batch = weather_keys[start:start + WEATHER_BATCH_SIZE]
        coordinates = [weather_grid_coordinates(key) for key in batch]

        params = {
            "latitude": ",".join(str(round(lat, 4)) for lat, lon in coordinates),
            "longitude": ",".join(str(round(lon, 4)) for lat, lon in coordinates),
            "hourly": "rain,temperature_2m,precipitation_probability,weather_code,wind_speed_10m",
            "daily": "temperature_2m_max,temperature_2m_min,precipitation_probability_max,rain_sum,weather_code",
            "forecast_days": 2,
            "timezone": "Asia/Kolkata",
        }

        try:
            response = requests.get(url, params=params, timeout=30)
            response.raise_for_status()
            result = response.json()

            if isinstance(result, dict):
                result = [result]

            for index, key in enumerate(batch):
                if index >= len(result):
                    continue

                item = result[index]
                hourly = item.get("hourly", {})
                daily = item.get("daily", {})

                times = hourly.get("time", [])
                rain_values = hourly.get("rain", [])
                temperatures = hourly.get("temperature_2m", [])
                probabilities = hourly.get("precipitation_probability", [])
                weather_codes = hourly.get("weather_code", [])
                wind_speeds = hourly.get("wind_speed_10m", [])

                rain_2h = 0.0
                rain_24h = 0.0
                valid_24h_hours = 0

                curr_temp = None
                curr_prob = None
                curr_code = None
                curr_wind = None

                max_rain_1h_3h = 0.0
                max_wind_3h = 0.0
                has_thunderstorm_3h = False
                min_temp_3h = 999.0

                for h_idx, (t_str, r_val) in enumerate(zip(times, rain_values)):
                    try:
                        f_time = datetime.fromisoformat(t_str)
                        if f_time.tzinfo is None:
                            f_time = f_time.replace(tzinfo=TIMEZONE)
                        f_time = f_time.astimezone(TIMEZONE)

                        r_val = max(0.0, float(r_val or 0.0))

                        # Current hour metrics
                        if f_time == current_hour:
                            curr_temp = float(temperatures[h_idx]) if temperatures[h_idx] is not None else 25.0
                            curr_prob = int(probabilities[h_idx]) if probabilities[h_idx] is not None else 0
                            curr_code = int(weather_codes[h_idx]) if weather_codes[h_idx] is not None else 0
                            curr_wind = float(wind_speeds[h_idx]) if wind_speeds[h_idx] is not None else 0.0

                        # Short-term 2-hour cumulative rainfall
                        if current_hour <= f_time < end_2h:
                            rain_2h += r_val

                        # 3-hour window severe weather analysis
                        if current_hour <= f_time < end_3h:
                            if r_val > max_rain_1h_3h:
                                max_rain_1h_3h = r_val
                            w_spd = float(wind_speeds[h_idx] or 0.0)
                            if w_spd > max_wind_3h:
                                max_wind_3h = w_spd
                            w_code = int(weather_codes[h_idx] or 0)
                            if w_code in (95, 96, 99):
                                has_thunderstorm_3h = True
                            t_val = float(temperatures[h_idx] or 25.0)
                            if t_val < min_temp_3h:
                                min_temp_3h = t_val

                        # 24-hour window
                        if current_hour <= f_time < end_24h:
                            rain_24h += r_val
                            valid_24h_hours += 1

                    except (TypeError, ValueError):
                        continue

                # Daily metrics
                today_max_temp = float(daily.get("temperature_2m_max", [30.0])[0] or 30.0)
                today_min_temp = float(daily.get("temperature_2m_min", [20.0])[0] or 20.0)
                today_max_prob = int(daily.get("precipitation_probability_max", [0])[0] or 0)
                today_rain_sum = float(daily.get("rain_sum", [0.0])[0] or 0.0)

                temp_drop = 0.0
                if curr_temp is not None and min_temp_3h < 900:
                    temp_drop = max(0.0, curr_temp - min_temp_3h)

                if valid_24h_hours:
                    weather_by_key[key] = {
                        "rain_2h": round(rain_2h, 2),
                        "rain_24h": round(rain_24h, 2),
                        "temperature": curr_temp,
                        "precipitation_probability": curr_prob,
                        "weather_code": curr_code,
                        "wind_speed": curr_wind,
                        "max_rain_1h_3h": round(max_rain_1h_3h, 2),
                        "max_wind_3h": round(max_wind_3h, 1),
                        "has_thunderstorm": has_thunderstorm_3h,
                        "temp_drop_3h": round(temp_drop, 1),
                        "today_max_temp": round(today_max_temp, 1),
                        "today_min_temp": round(today_min_temp, 1),
                        "today_max_prob": today_max_prob,
                        "today_rain_sum": round(today_rain_sum, 1),
                    }
        except Exception as err:
            print(f"[ERROR] Failed fetching Open-Meteo weather batch: {err}")

        time.sleep(0.1)

    return weather_by_key


# ============================================================
# CLASSIFICATION & RISK RULES
# ============================================================

def classify_rainfall(rainfall_mm):
    if rainfall_mm >= 30:
        return "HIGH"
    if rainfall_mm >= 10:
        return "MODERATE"
    return "LOW"


def classify_2h_rainfall(rainfall_mm):
    if rainfall_mm >= FLOOD_2H_HIGH_RAIN_MM:
        return "HIGH"
    if rainfall_mm >= FLOOD_2H_MODERATE_RAIN_MM:
        return "MODERATE"
    return "LOW"


def normalize_base_risk(value):
    value = str(value).strip().upper()
    if value in ("RED", "HIGH"):
        return "RED"
    if value in ("ORANGE", "MODERATE", "MEDIUM"):
        return "ORANGE"
    return "GREEN"


def calculate_final_risk(base_risk, rainfall_level):
    base_risk = normalize_base_risk(base_risk)
    if base_risk == "GREEN":
        return "GREEN"
    if base_risk == "RED":
        if rainfall_level == "HIGH":
            return "RED"
        if rainfall_level == "MODERATE":
            return "ORANGE"
        return "GREEN"
    if base_risk == "ORANGE":
        if rainfall_level == "HIGH":
            return "ORANGE"
        return "GREEN"
    return "GREEN"


def calculate_2h_flood_risk(base_risk, rainfall_2h):
    base_risk = normalize_base_risk(base_risk)
    rain_level = classify_2h_rainfall(rainfall_2h)

    if rain_level == "LOW":
        return "GREEN"
    if rain_level == "MODERATE":
        return "ORANGE"
    if rain_level == "HIGH":
        if base_risk in ("ORANGE", "RED"):
            return "RED"
        return "ORANGE"
    return "GREEN"


def risk_severity(risk):
    return {
        "GREEN": 0, "LOW": 0, "NONE": 0,
        "ORANGE": 1, "MODERATE": 1,
        "RED": 2, "HIGH": 2,
    }.get(str(risk).upper(), 0)


# ============================================================
# FIREBASE FCM SEND HELPER
# ============================================================

def send_to_tokens(tokens, title, body, data=None):
    successful_sends = 0
    for token in set(tokens):
        if not token:
            continue
        try:
            message = messaging.Message(
                notification=messaging.Notification(
                    title=title,
                    body=body,
                ),
                data={str(k): str(v) for k, v in (data or {}).items()},
                token=token,
                android=messaging.AndroidConfig(priority="high"),
            )
            messaging.send(message)
            successful_sends += 1
        except Exception as error:
            print(f"[FCM ERROR] Delivery failed for token: {error}")
    return successful_sends


def get_user_tokens(user_data):
    tokens = user_data.get("fcmTokens", [])
    if isinstance(tokens, str):
        tokens = [tokens]
    if not isinstance(tokens, list):
        return []
    return [t for t in tokens if isinstance(t, str) and t]


# ============================================================
# FEATURE 1: REAL-TIME WEATHER UPDATES & CONDITION CHANGES
# ============================================================

def process_weather_condition_change(db, user_id, enabled, forecast, tokens):
    """
    Sends notification when user's local weather condition changes (e.g., Clear -> Rainy / Thunderstorm).
    """
    if not enabled or not tokens:
        return False

    curr_code = forecast.get("weather_code")
    curr_condition = describe_weather_code(curr_code)
    curr_temp = forecast.get("temperature")
    curr_prob = forecast.get("precipitation_probability", 0)

    state_ref = db.collection("notification_state").document(f"{user_id}_weather_condition")
    state = state_ref.get().to_dict() or {}

    last_condition = state.get("lastCondition")

    # Trigger on first tracking OR condition change
    if last_condition is None:
        state_ref.set({"lastCondition": curr_condition, "updatedAt": firestore.SERVER_TIMESTAMP}, merge=True)
        return False

    if last_condition != curr_condition:
        title = "🌦️ Weather Condition Changed"
        temp_str = f"{curr_temp:.0f}°C" if curr_temp is not None else "N/A"
        body = (
            f"Weather update near your location: {curr_condition}. "
            f"Temperature: {temp_str}. Chance of rain: {curr_prob}%."
        )

        sent = send_to_tokens(
            tokens,
            title,
            body,
            {"type": "weather_change", "condition": curr_condition},
        )
        if sent > 0:
            state_ref.set({"lastCondition": curr_condition, "lastSentAt": firestore.SERVER_TIMESTAMP}, merge=True)
            print(f"[WEATHER UPDATE] Condition change alert sent to user {user_id}: {curr_condition}")
            return True

    return False


# ============================================================
# FEATURE 2: MAJOR WEATHER-CHANGE ALERTS
# ============================================================

def process_major_weather_alerts(db, user_id, enabled, forecast, tokens):
    """
    Triggers major severe weather alerts: Heavy rainfall, Strong winds, Thunderstorms, Sudden temp drops.
    """
    if not enabled or not tokens:
        return False

    max_rain = forecast.get("max_rain_1h_3h", 0.0)
    max_wind = forecast.get("max_wind_3h", 0.0)
    has_thunderstorm = forecast.get("has_thunderstorm", False)
    temp_drop = forecast.get("temp_drop_3h", 0.0)

    alert_reasons = []
    if max_rain >= 15.0:
        alert_reasons.append(f"🌧️ Heavy rainfall approaching ({max_rain:.1f} mm/h)")
    if max_wind >= 40.0:
        alert_reasons.append(f"💨 Strong winds forecasted ({max_wind:.0f} km/h)")
    if has_thunderstorm:
        alert_reasons.append("🌩️ Thunderstorm activity expected in the next 1–3 hours")
    if temp_drop >= 5.0:
        alert_reasons.append(f"📉 Sudden temperature drop of {temp_drop:.0f}°C expected")

    if not alert_reasons:
        return False

    alert_key = " | ".join(alert_reasons)
    state_ref = db.collection("notification_state").document(f"{user_id}_major_weather")
    state = state_ref.get().to_dict() or {}

    last_sent = state.get("lastSentAt")
    last_key = state.get("lastAlertKey")

    now = datetime.now(TIMEZONE)
    cooling_period = timedelta(hours=3)

    if last_sent and last_key == alert_key:
        if hasattr(last_sent, "to_datetime"):
            last_sent_dt = last_sent.to_datetime().astimezone(TIMEZONE)
            if now - last_sent_dt < cooling_period:
                return False

    title = "⚡ Major Weather Alert"
    body = f"Severe weather warning near your area:\n" + "\n".join(alert_reasons) + "\nTake necessary safety precautions."

    sent = send_to_tokens(
        tokens,
        title,
        body,
        {"type": "major_weather_alert", "alert_key": alert_key},
    )
    if sent > 0:
        state_ref.set({
            "lastAlertKey": alert_key,
            "lastSentAt": firestore.SERVER_TIMESTAMP,
        }, merge=True)
        print(f"[MAJOR WEATHER ALERT] Sent to user {user_id}: {alert_key}")
        return True

    return False


# ============================================================
# FEATURE 3: DAILY WEATHER FORECAST (MORNING & EVENING)
# ============================================================

def process_daily_weather_forecast(db, user_id, enabled, forecast, tokens, now=None):
    """
    Sends automatic morning (7 AM IST) and evening (7 PM IST) weather summaries.
    """
    if not enabled or not tokens:
        return False

    now = now or datetime.now(TIMEZONE)
    today_date = now.strftime("%Y-%m-%d")

    # Morning Forecast (07:00 AM - 08:59 AM)
    if MORNING_FORECAST_HOUR <= now.hour < MORNING_FORECAST_HOUR + 2:
        doc_id = f"{user_id}_daily_morning_{today_date}"
        state_ref = db.collection("notification_state").document(doc_id)
        if state_ref.get().exists:
            return False

        cond = describe_weather_code(forecast.get("weather_code"))
        max_t = forecast.get("today_max_temp", 30)
        min_t = forecast.get("today_min_temp", 20)
        max_p = forecast.get("today_max_prob", 0)
        rain_sum = forecast.get("today_rain_sum", 0.0)

        title = "🌅 Today's Weather Forecast"
        body = (
            f"Good morning! Today's weather: {cond}. "
            f"Temp: {min_t:.0f}°C to {max_t:.0f}°C. "
            f"Rain chance: {max_p}%. Expected rain: {rain_sum:.1f} mm. "
            f"Stay prepared!"
        )

        sent = send_to_tokens(tokens, title, body, {"type": "daily_forecast", "time": "morning"})
        if sent > 0:
            state_ref.set({"sentAt": firestore.SERVER_TIMESTAMP})
            print(f"[DAILY FORECAST] Morning forecast sent to user {user_id}")
            return True

    # Evening Forecast (19:00 PM - 20:59 PM)
    if EVENING_FORECAST_HOUR <= now.hour < EVENING_FORECAST_HOUR + 2:
        doc_id = f"{user_id}_daily_evening_{today_date}"
        state_ref = db.collection("notification_state").document(doc_id)
        if state_ref.get().exists:
            return False

        cond = describe_weather_code(forecast.get("weather_code"))
        curr_t = forecast.get("temperature", 25)
        curr_p = forecast.get("precipitation_probability", 0)

        title = "🌙 Evening Weather Summary"
        body = (
            f"Good evening! Tonight's weather: {cond}. "
            f"Temperature: {curr_t:.0f}°C. Rain chance tonight: {curr_p}%."
        )

        sent = send_to_tokens(tokens, title, body, {"type": "daily_forecast", "time": "evening"})
        if sent > 0:
            state_ref.set({"sentAt": firestore.SERVER_TIMESTAMP})
            print(f"[DAILY FORECAST] Evening forecast sent to user {user_id}")
            return True

    return False


# ============================================================
# FEATURE 4: EMERGENCY FLOOD & EXTREME WEATHER ALERTS (2-HOUR EARLY WARNING)
# ============================================================

def process_emergency_flood_alert(db, user_id, enabled, flood_condition, rain_2h, tokens):
    """
    Sends urgent 2-hour early flood warnings with safety instructions for RED and ORANGE risks.
    """
    if not enabled or not tokens or flood_condition not in ("ORANGE", "RED"):
        return False

    if flood_condition == "RED":
        title = "🚨 URGENT FLOOD WARNING (2-Hour Early Alert)"
        body = (
            f"CRITICAL FLOOD RISK predicted in 2 hours near your location due to extreme rainfall ({rain_2h:.1f} mm)! "
            "URGENT SAFETY INSTRUCTION: Move immediately to high ground or safe shelter. "
            "Avoid low-lying roads and water streams."
        )
    else:
        title = "⚠️ ELEVATED FLOOD RISK ALERT (2-Hour Warning)"
        body = (
            f"Elevated flood risk predicted in 2 hours near your location due to heavy rainfall ({rain_2h:.1f} mm). "
            "Secure essential items, keep emergency kit ready, and prepare to move to high ground if water rises."
        )

    return process_personal_alert(
        db=db,
        user_id=user_id,
        category="flood",
        enabled=enabled,
        condition=flood_condition,
        title=title,
        body=body,
        tokens=tokens,
    )


def process_personal_alert(db, user_id, category, enabled, condition, title, body, tokens):
    state_ref = db.collection("notification_state").document(f"{user_id}_{category}")
    snapshot = state_ref.get()
    state = snapshot.to_dict() or {}

    previous = state.get("activeCondition", "NONE")

    if not enabled or condition is None:
        if previous != "NONE":
            state_ref.set({"activeCondition": "NONE", "updatedAt": firestore.SERVER_TIMESTAMP}, merge=True)
        return False

    should_send = (
        previous == "NONE"
        or risk_severity(condition) > risk_severity(previous)
    )

    if not should_send:
        if previous != condition:
            state_ref.set({"activeCondition": condition, "updatedAt": firestore.SERVER_TIMESTAMP}, merge=True)
        return False

    sent = send_to_tokens(
        tokens,
        title,
        body,
        {"type": category, "severity": condition, "scope": "personal"},
    )

    if sent > 0:
        state_ref.set({
            "activeCondition": condition,
            "lastSentAt": firestore.SERVER_TIMESTAMP,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }, merge=True)
        return True

    return False


# ============================================================
# KARNATAKA-WIDE FLOOD ALERTS
# ============================================================

def process_karnataka_alert(db, users, current_risks):
    state_ref = db.collection("notification_state").document("karnataka_flood")
    snapshot = state_ref.get()
    state = snapshot.to_dict() or {}

    previous_risks = {
        str(k): int(v) for k, v in state.get("activeCells", {}).items()
    }

    current_active = {
        str(idx): risk_severity(risk)
        for idx, risk in current_risks.items()
        if risk_severity(risk) > 0
    }

    if not snapshot.exists:
        state_ref.set({"activeCells": current_active, "updatedAt": firestore.SERVER_TIMESTAMP})
        print("Karnataka alert baseline initialized.")
        return 0

    escalated_cells = [
        cell_id for cell_id, severity in current_active.items()
        if severity > previous_risks.get(cell_id, 0)
    ]

    sent_count = 0
    if len(escalated_cells) >= MIN_ESCALATED_CELLS:
        for user in users:
            user_data = user.to_dict() or {}
            if user_data.get("floodAlerts", True) is not True:
                continue

            sent_count += send_to_tokens(
                get_user_tokens(user_data),
                "🌊 Karnataka Flood Risk Update",
                (
                    f"Forecast-based flood risk has increased in {len(escalated_cells)} "
                    "monitored grid cells across Karnataka. Open FloodGuard to check the risk map."
                ),
                {"type": "flood", "scope": "karnataka", "severity": "ELEVATED"},
            )

    state_ref.set({"activeCells": current_active, "updatedAt": firestore.SERVER_TIMESTAMP}, merge=True)
    return sent_count


# ============================================================
# MAIN MONITORING CYCLE
# ============================================================

def run_alert_check():
    print("==================================================")
    print(f"Starting FloodGuard Alert Check at {datetime.now(TIMEZONE).strftime('%Y-%m-%d %H:%M:%S IST')}")
    print("==================================================")

    db = get_firestore()
    users = list(db.collection("users").stream())

    user_locations = {}
    weather_keys = set()

    for user in users:
        coordinates = get_user_coordinates(user.to_dict() or {})
        if coordinates is None:
            continue
        user_locations[user.id] = coordinates
        weather_keys.add(weather_grid_key(*coordinates))

    for cell in GRID_CELLS:
        weather_keys.add(
            weather_grid_key(float(cell["latitude"]), float(cell["longitude"]))
        )

    weather_data_by_key = fetch_forecast_data(weather_keys)
    print(f"[DEBUG] Monitored weather points: {len(weather_keys)}, forecast points loaded: {len(weather_data_by_key)}")

    current_risks = {}
    two_hour_grid_risks = {}

    for index, cell in enumerate(GRID_CELLS):
        key = weather_grid_key(float(cell["latitude"]), float(cell["longitude"]))
        forecast = weather_data_by_key.get(key)
        if forecast is None:
            continue

        base_risk = cell.get("risk", "GREEN")
        current_risks[index] = calculate_final_risk(base_risk, classify_rainfall(forecast["rain_24h"]))
        two_hour_grid_risks[index] = calculate_2h_flood_risk(base_risk, forecast["rain_2h"])

    statewide_sends = process_karnataka_alert(db, users, current_risks)

    personal_weather_updates = 0
    personal_major_weather_sends = 0
    personal_daily_forecast_sends = 0
    personal_flood_sends = 0

    now = datetime.now(TIMEZONE)

    for user in users:
        user_data = user.to_dict() or {}
        tokens = get_user_tokens(user_data)
        coordinates = user_locations.get(user.id)

        if coordinates is None or not tokens:
            continue

        key = weather_grid_key(*coordinates)
        forecast = weather_data_by_key.get(key)

        if forecast is None:
            continue

        weather_enabled = (user_data.get("weatherAlerts", True) is True)
        flood_enabled = (user_data.get("floodAlerts", True) is True)

        # 1. Real-time Weather Condition Changes
        if process_weather_condition_change(db, user.id, weather_enabled, forecast, tokens):
            personal_weather_updates += 1

        # 2. Major Weather-Change Alerts (Heavy rain, winds, thunderstorms, temp drops)
        if process_major_weather_alerts(db, user.id, weather_enabled, forecast, tokens):
            personal_major_weather_sends += 1

        # 3. Daily Forecasts (Morning & Evening)
        if process_daily_weather_forecast(db, user.id, weather_enabled, forecast, tokens, now=now):
            personal_daily_forecast_sends += 1

        # 4. Emergency 2-Hour Early Flood Warning
        nearest_index = find_nearest_cell_index(*coordinates)
        if nearest_index is not None:
            estimated_risk = two_hour_grid_risks.get(nearest_index)
            rain_2h = forecast.get("rain_2h", 0.0)

            if process_emergency_flood_alert(db, user.id, flood_enabled, estimated_risk, rain_2h, tokens):
                personal_flood_sends += 1

    summary = {
        "success": True,
        "monitored_users": len(users),
        "statewide_flood_notifications": statewide_sends,
        "weather_condition_change_alerts": personal_weather_updates,
        "major_weather_alerts": personal_major_weather_sends,
        "daily_forecast_notifications": personal_daily_forecast_sends,
        "emergency_2h_flood_alerts": personal_flood_sends,
    }

    print("FloodGuard Alert Check Finished:", summary)
    return summary


# ============================================================
# STANDALONE EXECUTION SCHEDULER
# ============================================================

if __name__ == "__main__":
    run_alert_check()

    if os.getenv("STANDALONE_LOOP", "false").lower() == "true":
        interval_seconds = max(1, FLOOD_CHECK_INTERVAL_MINUTES) * 60
        print(f"FloodGuard standalone loop enabled; running every {FLOOD_CHECK_INTERVAL_MINUTES} minutes.")
        while True:
            time.sleep(interval_seconds)
            try:
                run_alert_check()
            except Exception:
                logging.exception("FloodGuard alert monitoring encountered an error.")
