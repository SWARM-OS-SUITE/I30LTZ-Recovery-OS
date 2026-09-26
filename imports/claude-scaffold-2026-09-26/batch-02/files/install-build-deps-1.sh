#!/usr/bin/env bash
# i30LTZ Recovery OS — Debian 12 Build Dependency Installer
# v0.1.0 | 2026-09-26
# Run as root on a clean Debian 12 (Bookworm) machine.

set -euo pipefail

echo "============================================"
echo "  i30LTZ Recovery OS — Build Deps"
echo "  v0.1.0 | 2026-09-26 | Debian 12"
echo "============================================"

apt-get update
apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    curl \
    git \
    cmake \
    ninja-build \
    clang \
    libclang-dev \
    libssl-dev \
    libsqlite3-dev \
    libfreetype-dev \
    fontconfig \
    libfontconfig-dev \
    libxcb-xfixes0-dev \
    libxkbcommon-dev \
    libgl1-mesa-dev \
    libudev-dev \
    libinput-dev \
    libwayland-dev \
    wayland-protocols \
    libdbus-1-dev \
    smartmontools \
    ddrescue \
    hdparm \
    lshw \
    pciutils \
    usbutils

# ── llama.cpp system build (for MAD IT) ─────────────────────────────────
echo "[i30LTZ] Building llama.cpp..."
if [ ! -d /opt/i30ltz/llama.cpp ]; then
    mkdir -p /opt/i30ltz
    git clone --depth=1 https://github.com/ggerganov/llama.cpp /opt/i30ltz/llama.cpp
fi
cmake -S /opt/i30ltz/llama.cpp -B /opt/i30ltz/llama.cpp/build \
    -DCMAKE_BUILD_TYPE=Release -DLLAMA_NATIVE=ON
cmake --build /opt/i30ltz/llama.cpp/build --parallel
echo "[i30LTZ] llama.cpp built at /opt/i30ltz/llama.cpp/build"

# ── Rust ────────────────────────────────────────────────────────────────
if ! command -v cargo &>/dev/null; then
    echo "[i30LTZ] Installing Rust (rustup, stable)..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable
    source "$HOME/.cargo/env"
else
    rustup update stable
fi

echo ""
echo "[i30LTZ] All dependencies installed."
echo "[i30LTZ] Next steps:"
echo "   make dev            — fast dev build"
echo "   make release        — stripped release build"
echo "   sudo make install   — deploy to /opt/i30ltz"
echo ""
