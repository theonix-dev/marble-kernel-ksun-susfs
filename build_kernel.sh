#!/usr/bin/env bash
# ==============================================================================
# Script: build_kernel.sh
# Purpose: Compile patched kernel Image for marble using AOSP Clang
# Target: POCO F5 / Redmi Note 12 Turbo (marble) - LineageOS 23.2 (Android 16)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="$SCRIPT_DIR/build_env/kernel"
CLANG_DIR="${CLANG_DIR:-$HOME/toolchains/aosp-clang/clang-r547379}"
CONFIG_SOURCE="$SCRIPT_DIR/configs/marble_lineageos_23.2_ksunext_susfs.config"

if [ ! -d "$KERNEL_DIR" ]; then
    echo "ОШИБКА: Директорія ядра $KERNEL_DIR не знайдена. Спочатку запустіть ./patch_kernel.sh" >&2
    exit 1
fi

if [ ! -d "$CLANG_DIR" ]; then
    # Перевірка наявності clang у PATH якщо директорія не вказана явно
    if ! command -v clang >/dev/null 2>&1; then
        echo "ОШИБКА: AOSP Clang не знайдено у $CLANG_DIR і в PATH!" >&2
        echo "Встановіть CLANG_DIR=<шлях_до_aosp_clang> або завантажте clang-r547379" >&2
        exit 1
    fi
    echo "==> Використовується системний Clang: $(which clang)"
else
    echo "==> Використовується AOSP Clang: $CLANG_DIR"
    export PATH="$CLANG_DIR/bin:$PATH"
fi

export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export LLVM=1
export LLVM_IAS=1

cd "$KERNEL_DIR"

echo "==> [1/3] Застосування чистої перевіреної GKI конфігурації (KSU-Next + SUSFS)..."
mkdir -p out
if [ -f "$CONFIG_SOURCE" ]; then
    cp -vf "$CONFIG_SOURCE" out/.config
else
    echo "Попередження: $CONFIG_SOURCE не знайдено, використовуємо gki_defconfig..."
    make O=out gki_defconfig
    if [ -f "$SCRIPT_DIR/configs/ksu_susfs.fragment" ]; then
        cat "$SCRIPT_DIR/configs/ksu_susfs.fragment" >> out/.config
    fi
fi
make O=out olddefconfig

echo "==> [2/3] Компіляція ядра Image (потоків: $(nproc))..."
make -j$(nproc) O=out Image

COMPILED_IMAGE="$KERNEL_DIR/out/arch/arm64/boot/Image"
if [ ! -f "$COMPILED_IMAGE" ]; then
    echo "ОШИБКА: Файл Image не згенерувався!" >&2
    exit 1
fi

echo "==> [3/3] Оновлення AnyKernel3/Image..."
cp -vf "$COMPILED_IMAGE" "$SCRIPT_DIR/AnyKernel3/Image"

echo "================================================================="
echo " Ядро успішно скомпільовано!"
echo " Файл ядра: $COMPILED_IMAGE"
echo " Скопійовано в: $SCRIPT_DIR/AnyKernel3/Image"
echo " Тепер запустіть ./package_kernel.sh для створення релізних boot.img та zip"
echo "================================================================="
