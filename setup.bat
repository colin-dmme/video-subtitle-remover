@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Video Subtitle Remover - Setup
cd /d "%~dp0"

echo.
echo ================================================================
echo   Video Subtitle Remover - Auto Setup
echo ================================================================
echo.

rem ----------------------------------------------------------------
rem STEP 1: Check if running from correct folder
rem ----------------------------------------------------------------
if not exist "%~dp0gui.py" (
    echo [ERROR] Cannot find gui.py in this folder.
    echo         Run setup.bat from the project root folder.
    pause
    exit /b 1
)
if not exist "%~dp0start_vsr_gui.bat" (
    echo [ERROR] Cannot find start_vsr_gui.bat in this folder.
    pause
    exit /b 1
)

rem ----------------------------------------------------------------
rem STEP 2: Check model files and warn about missing ones
rem ----------------------------------------------------------------
echo [1/3] Checking AI model files...
echo.

set "MODELS_OK=1"
set "MISSING_MODELS="

set "MODELS[0]=backend\models\big-lama\big-lama.pt"
set "MODELS[1]=backend\models\propainter\ProPainter.pth"
set "MODELS[2]=backend\models\propainter\raft-things.pth"
set "MODELS[3]=backend\models\propainter\recurrent_flow_completion.pth"
set "MODELS[4]=backend\models\sttn-auto\infer_model.pth"
set "MODELS[5]=backend\models\sttn-det\sttn.pth"
set "MODELS[6]=backend\models\V5\ch_det\inference.pdiparams"
set "MODELS[7]=backend\models\V5\ch_det_fast\inference.pdiparams"

for /L %%i in (0,1,7) do (
    if not exist "%~dp0!MODELS[%%i]!" (
        echo   [MISSING] !MODELS[%%i]!
        set "MODELS_OK=0"
    ) else (
        echo   [OK]      !MODELS[%%i]!
    )
)

echo.
if "!MODELS_OK!"=="0" (
    echo [WARNING] Some AI model files are missing.
    echo          Models are NOT included in the git repository because they
    echo          are too large for GitHub (up to 196 MB per file).
    echo.
    echo          Copy the entire "backend\models\" folder from the source
    echo          machine to fix this. The app may crash or run in limited
    echo          mode without these files.
    echo.
    echo          Continue setup anyway? (Y to continue, any other key to exit)
    set /p "CONTINUE=>>> "
    if /I not "!CONTINUE!"=="Y" (
        echo Setup cancelled.
        pause
        exit /b 0
    )
    echo.
) else (
    echo   All model files are present.
    echo.
)

rem ----------------------------------------------------------------
rem STEP 3: Detect GPU and install Python environment
rem ----------------------------------------------------------------
echo [2/3] Setting up Python environment and dependencies...
echo       (This may take 10-30 minutes on first run — downloading AI packages)
echo.

rem Pass through any flags the user gave this script
call "%~dp0start_vsr_gui.bat" --setup-only %*
if errorlevel 1 (
    echo.
    echo [ERROR] Environment setup failed. See errors above.
    pause
    exit /b 1
)

rem ----------------------------------------------------------------
rem STEP 4: Final summary
rem ----------------------------------------------------------------
echo.
echo [3/3] Verifying setup...
echo.

rem Check which venv was created
set "FOUND_VENV="
for %%V in (.venv-blackwell .venv-cuda126 .venv-cuda118 .venv videoEnv venv) do (
    if exist "%~dp0%%V\Scripts\python.exe" (
        if not defined FOUND_VENV set "FOUND_VENV=%%V"
    )
)

if defined FOUND_VENV (
    echo   Virtual environment : !FOUND_VENV!
) else (
    echo   [WARNING] No virtual environment found — setup may have failed.
)

where nvidia-smi >nul 2>nul
if not errorlevel 1 (
    for /f "delims=" %%G in ('nvidia-smi --query-gpu^=name --format^=csv^,noheader^,nounits 2^>nul') do (
        echo   GPU detected        : %%G
        goto :gpu_done
    )
)
echo   GPU detected        : None (CPU mode)
:gpu_done

echo.
echo ================================================================
echo   Setup complete! Run start_vsr_gui.bat to launch the app.
echo ================================================================
echo.
pause
exit /b 0
