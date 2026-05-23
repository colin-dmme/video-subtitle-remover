@echo off
setlocal EnableExtensions EnableDelayedExpansion

title Video Subtitle Remover - GUI
cd /d "%~dp0"

set "APP_FILE=%~dp0gui.py"
set "VENV_DIR="
set "PYTHON_EXE="
set "PY_CMD="
set "SETUP_ONLY=0"
set "FORCE_PROFILE="
set "CUDA_PROFILE=cpu"
set "GPU_NAME="
set "PIP_DISABLE_PIP_VERSION_CHECK=1"
set "PIP_NO_INPUT=1"
set "PIP_CACHE_DIR=%~dp0.pip-cache"
set "PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True"
set "PYTHON_VERSION=3.12.10"
set "PYTHON_INSTALLER_URL=https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe"

if /I "%~1"=="--dry-run" (
    echo Launcher is ready.
    echo Project directory: %CD%
    exit /b 0
)

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="--setup-only" set "SETUP_ONLY=1"
if /I "%~1"=="--cpu" set "FORCE_PROFILE=cpu"
if /I "%~1"=="--cuda118" set "FORCE_PROFILE=cuda118"
if /I "%~1"=="--cuda126" set "FORCE_PROFILE=cuda126"
if /I "%~1"=="--blackwell" set "FORCE_PROFILE=blackwell"
if /I "%~1"=="--rtx50" set "FORCE_PROFILE=blackwell"
shift
goto parse_args

:args_done

if not exist "%APP_FILE%" (
    echo Cannot find gui.py in this folder.
    echo Please keep this BAT file in the project root folder.
    pause
    exit /b 1
)

call :select_profile
if errorlevel 1 exit /b 1

call :select_venv
if errorlevel 1 exit /b 1

call :ensure_venv
if errorlevel 1 exit /b 1

call :ensure_dependencies
if errorlevel 1 exit /b 1

if "%SETUP_ONLY%"=="1" (
    echo Environment setup is complete.
    exit /b 0
)

call :run_gui
exit /b %ERRORLEVEL%

:select_profile
if defined FORCE_PROFILE (
    set "CUDA_PROFILE=%FORCE_PROFILE%"
    exit /b 0
)

where nvidia-smi >nul 2>nul
if errorlevel 1 (
    set "CUDA_PROFILE=cpu"
    exit /b 0
)

for /f "delims=" %%G in ('nvidia-smi --query-gpu^=name --format^=csv^,noheader^,nounits 2^>nul') do (
    if not defined GPU_NAME set "GPU_NAME=%%G"
)

if not defined GPU_NAME (
    set "CUDA_PROFILE=cpu"
    exit /b 0
)

echo Detected GPU: %GPU_NAME%

echo %GPU_NAME% | findstr /I "RTX 50 5090 5080 5070 5060 Blackwell" >nul
if not errorlevel 1 (
    set "CUDA_PROFILE=blackwell"
    exit /b 0
)

echo %GPU_NAME% | findstr /I "RTX 40 4090 4080 4070 4060 Ada L40 L4" >nul
if not errorlevel 1 (
    set "CUDA_PROFILE=cuda126"
    exit /b 0
)

set "CUDA_PROFILE=cuda118"
exit /b 0

:select_venv
if "%CUDA_PROFILE%"=="blackwell" (
    set "VENV_DIR=%~dp0.venv-blackwell"
) else if "%CUDA_PROFILE%"=="cuda126" (
    set "VENV_DIR=%~dp0.venv-cuda126"
) else if "%CUDA_PROFILE%"=="cuda118" (
    set "VENV_DIR=%~dp0.venv-cuda118"
) else if exist "%~dp0videoEnv\Scripts\python.exe" (
    set "VENV_DIR=%~dp0videoEnv"
) else if exist "%~dp0.venv\Scripts\python.exe" (
    set "VENV_DIR=%~dp0.venv"
) else if exist "%~dp0venv\Scripts\python.exe" (
    set "VENV_DIR=%~dp0venv"
) else (
    set "VENV_DIR=%~dp0.venv"
)
set "PYTHON_EXE=%VENV_DIR%\Scripts\python.exe"
exit /b 0

:ensure_venv
if exist "%PYTHON_EXE%" exit /b 0

echo Virtual environment was not found.
echo Creating: "%VENV_DIR%"

call :find_or_install_python
if errorlevel 1 (
    echo Python 3.12 could not be installed or found.
    pause
    exit /b 1
)

call %PY_CMD% -m venv "%VENV_DIR%"
if errorlevel 1 (
    echo Failed to create the virtual environment.
    pause
    exit /b 1
)

exit /b 0

:find_or_install_python
set "PY_CMD="

where py >nul 2>nul
if not errorlevel 1 (
    py -3.12 -c "import sys" >nul 2>nul
    if not errorlevel 1 (
        set "PY_CMD=py -3.12"
        exit /b 0
    )
)

where python >nul 2>nul
if not errorlevel 1 (
    python -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 12) else 1)" >nul 2>nul
    if not errorlevel 1 (
        set "PY_CMD=python"
        exit /b 0
    )
)

if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" (
    set "PY_CMD="%LOCALAPPDATA%\Programs\Python\Python312\python.exe""
    exit /b 0
)

echo Python 3.12 was not found.
echo Downloading and installing Python %PYTHON_VERSION% for this Windows user...
set "PYTHON_INSTALLER=%TEMP%\python-%PYTHON_VERSION%-amd64.exe"

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%PYTHON_INSTALLER_URL%' -OutFile '%PYTHON_INSTALLER%'"
if errorlevel 1 exit /b 1

"%PYTHON_INSTALLER%" /quiet InstallAllUsers=0 PrependPath=1 Include_launcher=1 Include_pip=1 Include_test=0
if errorlevel 1 exit /b 1

if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" (
    set "PY_CMD="%LOCALAPPDATA%\Programs\Python\Python312\python.exe""
    exit /b 0
)

where py >nul 2>nul
if not errorlevel 1 (
    py -3.12 -c "import sys" >nul 2>nul
    if not errorlevel 1 (
        set "PY_CMD=py -3.12"
        exit /b 0
    )
)

exit /b 1

:ensure_dependencies
echo Checking Python dependencies...
echo Runtime profile: %CUDA_PROFILE%

rem -- Fast-path: skip heavy import checks if a marker file exists ----------
rem The marker is written after a successful full check. Delete it manually
rem (or delete the venv) to force a re-check on the next launch.
set "_MARKER=%VENV_DIR%\.deps-verified-%CUDA_PROFILE%"
if exist "!_MARKER!" (
    echo Dependencies are ready.
    exit /b 0
)

if "%CUDA_PROFILE%"=="cpu" (
    "%PYTHON_EXE%" -c "import PySide6, qfluentwidgets, cv2, numpy, av, paddleocr, paddle, torch, torchvision" >nul 2>nul
    if not errorlevel 1 (
        echo. > "!_MARKER!"
        echo Dependencies are ready.
        exit /b 0
    )
) else (
    set "_DEPS_READY=0"
    "%PYTHON_EXE%" -c "import PySide6, qfluentwidgets, cv2, numpy, av, paddleocr, torchvision" >nul 2>nul
    if not errorlevel 1 (
        "%PYTHON_EXE%" -c "import torch; raise SystemExit(0 if torch.cuda.is_available() else 1)" >nul 2>nul
        if not errorlevel 1 (
            "%PYTHON_EXE%" -c "import paddle; raise SystemExit(0 if paddle.device.is_compiled_with_cuda() else 1)" >nul 2>nul
            if not errorlevel 1 set "_DEPS_READY=1"
        )
    )
    if "!_DEPS_READY!"=="1" (
        echo. > "!_MARKER!"
        echo Dependencies are ready.
        exit /b 0
    )
)

echo Missing dependencies detected.
if "%CUDA_PROFILE%"=="blackwell" (
    echo Installing Blackwell / RTX 50 series CUDA environment.
) else if "%CUDA_PROFILE%"=="cuda126" (
    echo Installing CUDA 12.6 environment.
) else if "%CUDA_PROFILE%"=="cuda118" (
    echo Installing CUDA 11.8 environment.
) else (
    echo Installing CPU environment.
)
echo This first setup can take a while because AI/video packages are large.
echo.

"%PYTHON_EXE%" -m pip install --upgrade pip setuptools wheel
if errorlevel 1 goto install_failed

"%PYTHON_EXE%" -m pip install -r "%~dp0requirements.txt" --find-links "%~dp0.pip-wheels"
if errorlevel 1 goto install_failed

if "%CUDA_PROFILE%"=="blackwell" goto install_blackwell
if "%CUDA_PROFILE%"=="cuda126" goto install_cuda126
if "%CUDA_PROFILE%"=="cuda118" goto install_cuda118
goto install_cpu

:install_blackwell
"%PYTHON_EXE%" -m pip uninstall -y paddlepaddle paddlepaddle-gpu torch torchvision torchaudio
"%PYTHON_EXE%" -m pip install paddlepaddle-gpu==3.2.2 -i https://www.paddlepaddle.org.cn/packages/stable/cu129/ --find-links "%~dp0.pip-wheels"
if errorlevel 1 goto install_failed
"%PYTHON_EXE%" -m pip install torch==2.7.1 torchvision==0.22.1 --index-url https://download.pytorch.org/whl/cu128 --find-links "%~dp0.pip-wheels"
if errorlevel 1 goto install_failed
goto verify_cuda

:install_cuda126
"%PYTHON_EXE%" -m pip uninstall -y paddlepaddle paddlepaddle-gpu torch torchvision torchaudio
"%PYTHON_EXE%" -m pip install paddlepaddle-gpu==3.0.0 -i https://www.paddlepaddle.org.cn/packages/stable/cu126/ --find-links "%~dp0.pip-wheels"
if errorlevel 1 goto install_failed
"%PYTHON_EXE%" -m pip install torch==2.7.0 torchvision==0.22.0 --index-url https://download.pytorch.org/whl/cu126 --find-links "%~dp0.pip-wheels"
if errorlevel 1 goto install_failed
goto verify_cuda

:install_cuda118
"%PYTHON_EXE%" -m pip uninstall -y paddlepaddle paddlepaddle-gpu torch torchvision torchaudio
"%PYTHON_EXE%" -m pip install paddlepaddle-gpu==3.0.0 -i https://www.paddlepaddle.org.cn/packages/stable/cu118/ --find-links "%~dp0.pip-wheels\cu118" --find-links "%~dp0.pip-wheels"
if errorlevel 1 goto install_failed
"%PYTHON_EXE%" -m pip install torch==2.7.0 torchvision==0.22.0 --index-url https://download.pytorch.org/whl/cu118 --find-links "%~dp0.pip-wheels"
if errorlevel 1 goto install_failed
goto verify_cuda

:install_cpu
"%PYTHON_EXE%" -m pip install paddlepaddle==3.0.0 -i https://www.paddlepaddle.org.cn/packages/stable/cpu/ --find-links "%~dp0.pip-wheels"
if errorlevel 1 goto install_failed
"%PYTHON_EXE%" -m pip install torch==2.7.0 torchvision==0.22.0 --find-links "%~dp0.pip-wheels"
if errorlevel 1 goto install_failed
"%PYTHON_EXE%" -c "import PySide6, qfluentwidgets, cv2, numpy, av, paddleocr, paddle, torch, torchvision" >nul 2>nul
if errorlevel 1 goto install_failed
goto install_success

:verify_cuda
"%PYTHON_EXE%" -c "import torch; raise SystemExit(0 if torch.cuda.is_available() else 1)" >nul 2>nul
if errorlevel 1 goto install_failed
"%PYTHON_EXE%" -c "import paddle; raise SystemExit(0 if paddle.device.is_compiled_with_cuda() else 1)" >nul 2>nul
if errorlevel 1 goto install_failed
goto install_success

:install_success
echo Dependencies installed successfully.
rem Write marker so next launch skips the heavy import checks
echo. > "!_MARKER!"
exit /b 0

:install_failed
echo.
echo Dependency installation failed.
echo Please check the error above, then run this BAT file again.
pause
exit /b 1

:run_gui
if "%CUDA_PROFILE%"=="blackwell" (
    echo Runtime mode: NVIDIA RTX 50 / Blackwell CUDA
) else if "%CUDA_PROFILE%"=="cuda126" (
    echo Runtime mode: NVIDIA CUDA 12.6
) else if "%CUDA_PROFILE%"=="cuda118" (
    echo Runtime mode: NVIDIA CUDA 11.8
) else (
    echo Runtime mode: CPU
)
echo Starting Video Subtitle Remover GUI...
echo Keep this window open while the app is running.
"%PYTHON_EXE%" "%APP_FILE%"
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo.
    echo The GUI stopped with error code %EXIT_CODE%.
    pause
)

exit /b %EXIT_CODE%
