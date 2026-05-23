#!/bin/bash
# Video Subtitle Remover - Linux Setup Script
# Auto-detects GPU and installs compatible CUDA packages
set -e

VSR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$VSR_DIR/.venv-linux"

echo "============================================"
echo " Video Subtitle Remover - Linux Setup"
echo " Project: $VSR_DIR"
echo "============================================"

# Detect GPU and pick CUDA profile
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "")
CUDA_PROFILE="cu126"  # default: works for V100, RTX 20/30/40 series

if echo "$GPU_NAME" | grep -qiE "RTX 50|5090|5080|5070|5060|Blackwell"; then
    CUDA_PROFILE="blackwell"
fi

echo ""
echo "Detected GPU : ${GPU_NAME:-'(none)'}"
echo "CUDA profile : $CUDA_PROFILE"
echo ""

# 1. System packages
echo "[1/4] Installing system packages..."
apt-get update -qq
apt-get install -y -qq \
    libgl1-mesa-glx libegl1 libxkbcommon0 libdbus-1-3 \
    ffmpeg python3-venv python3-pip

# 2. Create virtual environment
echo ""
echo "[2/4] Creating virtual environment..."
python3 -m venv "$VENV"
source "$VENV/bin/activate"
pip install --upgrade pip setuptools wheel -q

# 3. Install base requirements
echo ""
echo "[3/4] Installing base requirements..."
pip install -r "$VSR_DIR/requirements.txt" -q

# 4. Install GPU packages (no conflicts: both torch + paddle use same cuDNN 9.x)
echo ""
echo "[4/4] Installing GPU packages..."

# Remove any conflicting pre-installed GPU packages first
pip uninstall -y torch torchvision torchaudio paddlepaddle paddlepaddle-gpu 2>/dev/null || true

if [ "$CUDA_PROFILE" = "blackwell" ]; then
    echo "  -> Blackwell / RTX 50 series (cu128 + cu129)"
    pip install torch==2.7.1 torchvision==0.22.1 \
        --index-url https://download.pytorch.org/whl/cu128 -q
    pip install paddlepaddle-gpu==3.2.2 \
        -i https://www.paddlepaddle.org.cn/packages/stable/cu129/ -q
else
    echo "  -> cu126 (V100 / RTX 20/30/40 series)"
    pip install torch==2.7.0 torchvision==0.22.0 \
        --index-url https://download.pytorch.org/whl/cu126 -q
    pip install paddlepaddle-gpu==3.0.0 \
        -i https://www.paddlepaddle.org.cn/packages/stable/cu126/ -q
fi

# 5. Set environment variables permanently in activate script
SITE_PKGS=$(python -c "import site; print(site.getsitepackages()[0])")
cat >> "$VENV/bin/activate" << EOF

# VSR CUDA paths
export LD_LIBRARY_PATH="$SITE_PKGS/nvidia/cudnn/lib:$SITE_PKGS/nvidia/cuda_runtime/lib:\$LD_LIBRARY_PATH"
export PYTHONPATH="$VSR_DIR:\$PYTHONPATH"
export PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True
EOF

# 6. Verify both torch and paddle
echo ""
echo "Verifying installation..."
python -c "
import torch
cuda_ok = torch.cuda.is_available()
gpu = torch.cuda.get_device_name(0) if cuda_ok else 'N/A'
print(f'torch  CUDA : {cuda_ok}  |  GPU: {gpu}')
"
python -c "
import paddle
print(f'paddle CUDA : {paddle.device.is_compiled_with_cuda()}')
"

echo ""
echo "============================================"
echo " Setup complete! Profile: $CUDA_PROFILE"
echo ""
echo " Next steps:"
echo "   source $VENV/bin/activate"
echo "   python $VSR_DIR/backend/main.py --input video.mp4 --output result.mp4"
echo "============================================"
