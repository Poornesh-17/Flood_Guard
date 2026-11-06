@echo off
title FloodGuard AI Backend Server
cd /d "C:\flutter app\projects\FloodGuard\FloodWatch_AI_backend"
echo ============================================================
echo Starting FloodGuard AI Backend Server on 0.0.0.0:8000...
echo ============================================================
python -m uvicorn app:app --host 0.0.0.0 --port 8000 --reload
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Uvicorn failed. Trying damage_assessment_api:app...
    python -m uvicorn damage_assessment_api:app --host 0.0.0.0 --port 8000 --reload
)
pause
