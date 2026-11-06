
import json
import uuid
from datetime import datetime, timezone
from pathlib import Path
from io import BytesIO
from typing import Optional

from fastapi import (
    FastAPI,
    UploadFile,
    File,
    Form,
    HTTPException
)

from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from PIL import Image, UnidentifiedImageError


# ============================================================
# CONFIGURATION
# ============================================================

BASE_DIR = Path(__file__).resolve().parent

UPLOAD_DIR = BASE_DIR / "damage_assessment_uploads"

DATA_FILE = BASE_DIR / "damage_assessments.json"

MAX_FILE_SIZE = 10 * 1024 * 1024  # 10 MB

ALLOWED_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".webp"
}

UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


# ============================================================
# FASTAPI APPLICATION
# ============================================================

app = FastAPI(
    title="FloodGuard AI Damage Assessment API",
    description="Local flood damage image upload and assessment API.",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Make uploaded images accessible through HTTP.
app.mount(
    "/uploads",
    StaticFiles(directory=str(UPLOAD_DIR)),
    name="uploads"
)


# ============================================================
# IMAGE VALIDATION AND STORAGE
# ============================================================

async def save_image(
    image: UploadFile,
    filename_prefix: str
):
    content = await image.read(MAX_FILE_SIZE + 1)

    if not content:
        raise HTTPException(
            status_code=400,
            detail="Uploaded image is empty."
        )

    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=400,
            detail="Image size must not exceed 10 MB."
        )

    fmt = None
    try:
        with Image.open(BytesIO(content)) as img:
            img.verify()
            fmt = (img.format or "").upper()
    except (UnidentifiedImageError, OSError):
        raise HTTPException(
            status_code=400,
            detail="Invalid or corrupted image."
        )

    fmt_to_ext = {
        'JPEG': '.jpg',
        'PNG': '.png',
        'WEBP': '.webp'
    }

    extension = fmt_to_ext.get(fmt)
    if not extension:
        orig_ext = Path(image.filename or "").suffix.lower()
        if orig_ext in ALLOWED_EXTENSIONS:
            extension = orig_ext
        else:
            extension = ".jpg"

    filename = f"{filename_prefix}{extension}"
    file_path = UPLOAD_DIR / filename
    file_path.write_bytes(content)

    return filename, f"damage_assessment_uploads/{filename}"


# ============================================================
# JSON DATABASE HELPERS
# ============================================================

def load_assessments():

    if not DATA_FILE.exists():
        return []

    try:
        records = json.loads(
            DATA_FILE.read_text(encoding="utf-8")
        )

        if not isinstance(records, list):
            return []

        return records

    except (json.JSONDecodeError, OSError):
        return []


def save_assessments(records):

    DATA_FILE.write_text(
        json.dumps(records, indent=4),
        encoding="utf-8"
    )


# ============================================================
# HEALTH CHECK
# ============================================================

@app.get("/")
def home():

    return {
        "success": True,
        "message": "FloodGuard Damage Assessment API is running.",
        "storage": "Local computer",
        "ai_status": "Not integrated yet"
    }


# ============================================================
# UPLOAD DAMAGE ASSESSMENT
# ============================================================

@app.post("/assessments")
async def create_assessment(

    mode: str = Form(...),

    latitude: float = Form(...),

    longitude: float = Form(...),

    after_image: UploadFile = File(...),

    before_image: Optional[UploadFile] = File(None)

):

    # Validate assessment mode.
    if mode not in ["before_after", "after_only"]:

        raise HTTPException(
            status_code=400,
            detail="Invalid assessment mode."
        )

    # Validate GPS coordinates.
    if not (-90 <= latitude <= 90):

        raise HTTPException(
            status_code=400,
            detail="Invalid latitude."
        )

    if not (-180 <= longitude <= 180):

        raise HTTPException(
            status_code=400,
            detail="Invalid longitude."
        )

    # Before image is compulsory in comparison mode.
    if mode == "before_after" and (before_image is None or not before_image.filename):

        raise HTTPException(
            status_code=400,
            detail="Before-flood image is required."
        )

    assessment_id = str(uuid.uuid4())

    # Save after-flood image.
    after_filename, after_path = await save_image(
        after_image,
        f"{assessment_id}_after"
    )

    # Save before-flood image if provided.
    before_filename = None
    before_path = None

    if before_image is not None and before_image.filename:
        before_filename, before_path = await save_image(
            before_image,
            f"{assessment_id}_before"
        )

    # Create assessment record.
    assessment = {

        "assessment_id": assessment_id,

        "mode": mode,

        "latitude": latitude,

        "longitude": longitude,

        "before_image": before_path,

        "after_image": after_path,

        "imageUrl": f"/uploads/{after_filename}",

        "beforeImageUrl": (
            f"/uploads/{before_filename}"
            if before_filename else None
        ),

        "assessment_date": datetime.now(
            timezone.utc
        ).isoformat(),

        # AI model has not been integrated yet.
        "analysis_status": "pending_ai_model",

        "severity": None,

        "damageLevel": None,

        "inspectionPriority": None,

        "details": "Waiting for AI damage analysis."

    }

    # Save to local JSON database.
    records = load_assessments()

    records.append(assessment)

    save_assessments(records)

    return {

        "success": True,

        "message": "Images uploaded successfully.",

        "assessment": assessment,

        "note": (
            "Images and GPS information have been saved locally. "
            "AI damage classification is not integrated yet."
        )

    }


# ============================================================
# GET ALL DAMAGE ASSESSMENTS
# ============================================================

@app.get("/assessments")
def get_assessments():

    records = load_assessments()

    for record in records:

        after_path = record.get("after_image")

        before_path = record.get("before_image")

        if after_path:

            filename = Path(after_path).name

            record["imageUrl"] = (
                f"/uploads/{filename}"
            )

        if before_path:

            filename = Path(before_path).name

            record["beforeImageUrl"] = (
                f"/uploads/{filename}"
            )

    return {

        "success": True,

        "total": len(records),

        "assessments": records

    }


# ============================================================
# GET ONE DAMAGE ASSESSMENT
# ============================================================

@app.get("/assessments/{assessment_id}")
def get_assessment(assessment_id: str):

    records = load_assessments()

    for record in records:

        if record.get("assessment_id") == assessment_id:

            return {
                "success": True,
                "assessment": record
            }

    raise HTTPException(
        status_code=404,
        detail="Assessment not found."
    )


# ============================================================
# DELETE ONE ASSESSMENT
# ============================================================

@app.delete("/assessments/{assessment_id}")
def delete_assessment(assessment_id: str):

    records = load_assessments()

    updated_records = []

    found = None

    for record in records:

        if record.get("assessment_id") == assessment_id:
            found = record
        else:
            updated_records.append(record)

    if found is None:

        raise HTTPException(
            status_code=404,
            detail="Assessment not found."
        )

    # Delete associated image files.
    for key in ["after_image", "before_image"]:

        image_path = found.get(key)

        if image_path:

            filename = Path(image_path).name

            file_path = UPLOAD_DIR / filename

            if file_path.exists():
                file_path.unlink()

    save_assessments(updated_records)

    return {

        "success": True,

        "message": "Assessment deleted successfully."

    }


# ============================================================
# RUN SERVER
# ============================================================

if __name__ == "__main__":

    import uvicorn

    uvicorn.run(
        "damage_assessment_api:app",
        host="0.0.0.0",
        port=8000,
        reload=True
    )

