@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Download Wheels - Video Subtitle Remover
cd /d "%~dp0"

set "WHEELS=%~dp0.pip-wheels"
set "WHEELS_CU118=%~dp0.pip-wheels\cu118"
set "PY_CMD="

if exist "%~dp0.venv-cuda118\Scripts\python.exe" (
    set "PY_CMD=%~dp0.venv-cuda118\Scripts\python.exe"
    goto :py_found
)
if exist "%~dp0.venv\Scripts\python.exe" (
    set "PY_CMD=%~dp0.venv\Scripts\python.exe"
    goto :py_found
)
py -3.12 -c "import sys" >nul 2>nul
if not errorlevel 1 (
    set "PY_CMD=py -3.12"
    goto :py_found
)
echo Python 3.12 not found.
pause
exit /b 1

:py_found
if not exist "%WHEELS%" mkdir "%WHEELS%"
if not exist "%WHEELS_CU118%" mkdir "%WHEELS_CU118%"

echo.
echo  Video Subtitle Remover - Wheel Downloader
echo  Python  : %PY_CMD%
echo  Luu vao : %WHEELS%
echo.
echo  Chon GPU profile can tai wheel:
echo.
echo    1. Blackwell  (RTX 5060 Ti / 5070 / 5080 / 5090)    ~4.5 GB
echo    2. CUDA 12.6  (RTX 4060 / 4070 / 4080 / 4090)       ~4.5 GB
echo    3. CUDA 11.8  (RTX 3090 / 3080 / 20xx / older)       ~3.5 GB
echo    4. Tat ca profiles                                    ~12  GB
echo.
set /p "CHOICE=Chon (1/2/3/4): "

echo.
echo [1/3] Base packages tu requirements.txt...
"%PY_CMD%" -m pip download --dest "%WHEELS%" --prefer-binary -r "%~dp0requirements.txt"
if errorlevel 1 echo Warning: mot so base package co the that bai, se tu dong tai khi can.

if "%CHOICE%"=="1" ( call :do_blackwell & goto :done )
if "%CHOICE%"=="2" ( call :do_cuda126   & goto :done )
if "%CHOICE%"=="3" ( call :do_cuda118   & goto :done )
if "%CHOICE%"=="4" (
    call :do_blackwell
    call :do_cuda126
    call :do_cuda118
    goto :done
)
echo Lua chon khong hop le.
pause
exit /b 1

:do_blackwell
echo.
echo [Blackwell] PaddlePaddle GPU cu129 (681 MB)...
"%PY_CMD%" -m pip download --dest "%WHEELS%" --only-binary :all: paddlepaddle-gpu==3.2.2 --extra-index-url https://www.paddlepaddle.org.cn/packages/stable/cu129/
echo [Blackwell] PyTorch cu128 (3.2 GB)...
"%PY_CMD%" -m pip download --dest "%WHEELS%" --only-binary :all: torch==2.7.1 torchvision==0.22.1 --index-url https://download.pytorch.org/whl/cu128
exit /b 0

:do_cuda126
echo.
echo [CUDA 12.6] PaddlePaddle GPU cu126 (681 MB)...
"%PY_CMD%" -m pip download --dest "%WHEELS%" --only-binary :all: paddlepaddle-gpu==3.0.0 --extra-index-url https://www.paddlepaddle.org.cn/packages/stable/cu126/
echo [CUDA 12.6] PyTorch cu126 (3.2 GB)...
"%PY_CMD%" -m pip download --dest "%WHEELS%" --only-binary :all: torch==2.7.0 torchvision==0.22.0 --index-url https://download.pytorch.org/whl/cu126
exit /b 0

:do_cuda118
echo.
echo [CUDA 11.8] PaddlePaddle GPU cu118 (500 MB) - luu vao .pip-wheels\cu118\...
"%PY_CMD%" -m pip download --dest "%WHEELS_CU118%" --only-binary :all: paddlepaddle-gpu==3.0.0 --extra-index-url https://www.paddlepaddle.org.cn/packages/stable/cu118/
echo [CUDA 11.8] PyTorch cu118 (2.5 GB)...
"%PY_CMD%" -m pip download --dest "%WHEELS%" --only-binary :all: torch==2.7.0 torchvision==0.22.0 --index-url https://download.pytorch.org/whl/cu118
exit /b 0

:done
echo.
echo =============================================
for /f %%N in ('dir "%WHEELS%\*.whl" /b /a-d 2^>nul ^| find /c ".whl"') do echo Tong so file (main): %%N wheels
for /f %%N in ('dir "%WHEELS_CU118%\*.whl" /b /a-d 2^>nul ^| find /c ".whl"') do echo Tong so file (cu118): %%N wheels
echo.
echo Tiep theo:
echo   1. Nen toan bo folder du an (gom ca .pip-wheels)
echo   2. Upload len Google Drive / OneDrive
echo   3. Khi thue may moi: giai nen va chay start_vsr_gui.bat
echo =============================================
pause
