@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Video Subtitle Remover - Setup
cd /d "%~dp0"

echo.
echo ================================================================
echo   Video Subtitle Remover - Tu dong cai dat
echo ================================================================
echo.

rem ----------------------------------------------------------------
rem Kiem tra chay dung thu muc
rem ----------------------------------------------------------------
if not exist "%~dp0gui.py" (
    echo [LOI] Khong tim thay gui.py.
    echo       Chay setup.bat tu thu muc goc cua project.
    goto :end_error
)
if not exist "%~dp0start_vsr_gui.bat" (
    echo [LOI] Khong tim thay start_vsr_gui.bat.
    goto :end_error
)

rem ----------------------------------------------------------------
rem Kiem tra file AI model
rem ----------------------------------------------------------------
echo [1/3] Kiem tra AI model files...
echo.

set "MODELS_MISSING=0"

call :check_model "backend\models\big-lama\big-lama.pt"
call :check_model "backend\models\propainter\ProPainter.pth"
call :check_model "backend\models\propainter\raft-things.pth"
call :check_model "backend\models\propainter\recurrent_flow_completion.pth"
call :check_model "backend\models\sttn-auto\infer_model.pth"
call :check_model "backend\models\sttn-det\sttn.pth"
call :check_model "backend\models\V5\ch_det\inference.pdiparams"
call :check_model "backend\models\V5\ch_det_fast\inference.pdiparams"

echo.
if "!MODELS_MISSING!"=="1" (
    echo [CANH BAO] Mot so file model dang thieu.
    echo            Model qua lon de dua len GitHub ^(len den 196 MB/file^).
    echo            Can copy thu muc "backend\models\" tu may cu sang may nay.
    echo.
    set /p "CONTINUE=Tiep tuc cai dat khong co model? ^(Y/N^): "
    if /I not "!CONTINUE!"=="Y" goto :end_cancel
    echo.
) else (
    echo   Tat ca model files da co day du.
    echo.
)

rem ----------------------------------------------------------------
rem Cai dat moi truong Python
rem ----------------------------------------------------------------
echo [2/3] Cai dat Python + thu vien...
echo       ^(Lan dau co the mat 10-30 phut - tai cac goi AI lon^)
echo.

call "%~dp0start_vsr_gui.bat" --setup-only
if errorlevel 1 (
    echo.
    echo [LOI] Cai dat that bai. Xem chi tiet o tren.
    goto :end_error
)

rem ----------------------------------------------------------------
rem Ket qua
rem ----------------------------------------------------------------
echo.
echo [3/3] Ket qua...
echo.

set "FOUND_VENV="
for %%V in (.venv-blackwell .venv-cuda126 .venv-cuda118 .venv videoEnv venv) do (
    if not defined FOUND_VENV (
        if exist "%~dp0%%V\Scripts\python.exe" set "FOUND_VENV=%%V"
    )
)

if defined FOUND_VENV (
    echo   Virtual env : !FOUND_VENV!
) else (
    echo   [CANH BAO] Khong tim thay virtual environment.
)

set "GPU_INFO=Khong co (che do CPU)"
where nvidia-smi >nul 2>nul
if not errorlevel 1 (
    for /f "delims=" %%G in ('nvidia-smi --query-gpu^=name --format^=csv^,noheader^,nounits 2^>nul') do (
        set "GPU_INFO=%%G"
        goto :show_gpu
    )
)
:show_gpu
echo   GPU         : !GPU_INFO!

echo.
echo ================================================================
echo   XONG! Chay start_vsr_gui.bat de mo ung dung.
echo ================================================================
echo.
goto :end_ok

rem ----------------------------------------------------------------
rem Subroutine kiem tra tung file model
rem ----------------------------------------------------------------
:check_model
if exist "%~dp0%~1" (
    echo   [CO]     %~1
) else (
    echo   [THIEU]  %~1
    set "MODELS_MISSING=1"
)
exit /b 0

:end_ok
pause
exit /b 0

:end_cancel
echo.
echo Da huy. Chay lai setup.bat sau khi copy thu muc backend\models\.
pause
exit /b 0

:end_error
echo.
pause
exit /b 1
