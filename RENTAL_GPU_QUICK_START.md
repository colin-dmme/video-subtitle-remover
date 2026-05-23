# Rental GPU Quick Start

This project can bootstrap itself on a fresh hourly Windows GPU machine.

## Fast path

1. Copy or unzip this project folder onto the rental machine.
2. Double-click `start_vsr_gui.bat`.
3. Wait for the first setup to finish.
4. When the GUI opens, start processing as usual.

The first run installs Python 3.12 if needed, creates a local virtual environment, installs dependencies, and chooses a CUDA profile based on the NVIDIA GPU name.

## Automatic GPU profiles

| GPU family | Profile | Environment folder |
| --- | --- | --- |
| RTX 50 series, RTX 5090, RTX 5080, RTX 5070, RTX 5060 Ti | Blackwell CUDA | `.venv-blackwell` |
| RTX 40 series, RTX 4090, RTX 4080, RTX 4070, RTX 4060 | CUDA 12.6 | `.venv-cuda126` |
| Older NVIDIA GPUs, including GTX 1080 Ti, RTX 20/30 series | CUDA 11.8 | `.venv-cuda118` |
| No NVIDIA GPU detected | CPU | `.venv` |

## Manual override

Run one of these from a command prompt in the project folder:

```bat
start_vsr_gui.bat --blackwell
start_vsr_gui.bat --cuda126
start_vsr_gui.bat --cuda118
start_vsr_gui.bat --cpu
```

To set up the environment without opening the GUI:

```bat
start_vsr_gui.bat --setup-only
```

## What to check

The console should show one of these lines:

```text
Runtime mode: NVIDIA RTX 50 / Blackwell CUDA
Runtime mode: NVIDIA CUDA 12.6
Runtime mode: NVIDIA CUDA 11.8
```

Inside the app log, the important line is:

```text
Subtitle removal model: STTN Smart Erase (GPU)
```

If it says `(CPU)`, the CUDA environment did not initialize correctly.

## Notes for hourly machines

- Keep the project folder on a persistent disk if the provider offers one. The `.venv-*` folder and `.pip-cache` can be reused and avoid downloading large packages again.
- If every machine is completely fresh, expect the first setup to take time because PyTorch, PaddlePaddle, and CUDA runtime wheels are large.
- For RTX 50 series machines, use the Blackwell profile. CUDA 11.8 is not the right choice for these GPUs.
- Make sure the rental machine has a working NVIDIA driver. `nvidia-smi` must run in Command Prompt.
