#!/usr/bin/env bash
# ==============================================================================
# Script: package_kernel.sh
# Purpose: Repack stock boot image with patched kernel and build AnyKernel3 zip
# Target: POCO F5 / Redmi Note 12 Turbo (marble) - LineageOS 23.2 (Android 16)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_IMAGE="${1:-$SCRIPT_DIR/AnyKernel3/Image}"
if [ ! -f "$KERNEL_IMAGE" ] && [ -f "$SCRIPT_DIR/build_env/kernel/out/arch/arm64/boot/Image" ]; then
    KERNEL_IMAGE="$SCRIPT_DIR/build_env/kernel/out/arch/arm64/boot/Image"
fi

STOCK_BOOT_IMG="${2:-}"
if [ -z "$STOCK_BOOT_IMG" ]; then
    if [ -f "$SCRIPT_DIR/stock_boot/official_lineage_23.2_boot.img" ]; then
        STOCK_BOOT_IMG="$SCRIPT_DIR/stock_boot/official_lineage_23.2_boot.img"
    elif [ -f "$HOME/Downloads/boot.img" ]; then
        STOCK_BOOT_IMG="$HOME/Downloads/boot.img"
    fi
fi

AK3_DIR="$SCRIPT_DIR/AnyKernel3"
OUTPUT_DIR="$SCRIPT_DIR/output"
MAGISKBOOT="$AK3_DIR/tools/magiskboot"

mkdir -p "$OUTPUT_DIR"

echo "==> [1/4] Перевірка вихідних файлів..."
if [ ! -f "$KERNEL_IMAGE" ]; then
    echo "ОШИБКА: Скомпільоване ядро не знайдено по шляху $KERNEL_IMAGE" >&2
    echo "Спочатку запустіть ./build_kernel.sh або вкажіть шлях до Image першим аргументом." >&2
    exit 1
fi
echo "==> Використовується ядро Image: $KERNEL_IMAGE ($(du -h "$KERNEL_IMAGE" | cut -f1))"

# Оновлюємо Image всередині AnyKernel3
cp -vf "$KERNEL_IMAGE" "$AK3_DIR/Image"

echo "==> [2/4] Створення прошиваного zip-архіву AnyKernel3..."
ZIP_NAME="AnyKernel3-marble-ksunext-susfs-LineageOS-23.2.zip"
python3 -c "import zipfile, os, sys; ak3, out = sys.argv[1], sys.argv[2]; zf = zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED); [(zf.write(os.path.join(r, f), os.path.relpath(os.path.join(r, f), ak3))) for r, _, fs in os.walk(ak3) if '.git' not in r for f in fs if f != 'README.md' and not f.endswith('placeholder')]; zf.close()" "$AK3_DIR" "$OUTPUT_DIR/$ZIP_NAME"
echo "==> Успішно створено: $OUTPUT_DIR/$ZIP_NAME"

BOOT_OUT_NAME="boot-ksunext-susfs-LineageOS-23.2-marble.img"
if [ -n "$STOCK_BOOT_IMG" ] && [ -f "$STOCK_BOOT_IMG" ]; then
    echo "==> [3/4] Перепакування стокового boot.img із застосуванням валідного AVB футера..."
    TMP_DIR="$(mktemp -d /tmp/kernel_repack.XXXXXX)"
    trap 'rm -rf "$TMP_DIR"' EXIT

    cd "$TMP_DIR"
    
    # Визначаємо як запустити magiskboot (через qemu якщо це ARM бінарник на x86_64)
    RUN_MAGISKBOOT="$MAGISKBOOT"
    if file "$MAGISKBOOT" | grep -q "ARM aarch64" && [ "$(uname -m)" != "aarch64" ]; then
        RUN_MAGISKBOOT="qemu-aarch64 $MAGISKBOOT"
    fi

    $RUN_MAGISKBOOT unpack "$STOCK_BOOT_IMG"
    cp -vf "$KERNEL_IMAGE" "$TMP_DIR/kernel"
    $RUN_MAGISKBOOT repack "$STOCK_BOOT_IMG" "$TMP_DIR/boot_raw.img"

    # Критично: підпис та налаштування AVB футера з flags 3 (disable verification)
    if command -v avbtool >/dev/null 2>&1; then
        echo "==> Налаштування AVB футера через avbtool..."
        avbtool erase_footer --image "$TMP_DIR/boot_raw.img" 2>/dev/null || true
        avbtool add_hash_footer \
            --image "$TMP_DIR/boot_raw.img" \
            --partition_name boot \
            --partition_size 201326592 \
            --flags 3 \
            --prop com.android.build.boot.os_version:16 \
            --prop com.android.build.boot.fingerprint:POCO/lineage_marble/marble:16/BP4A.251205.006/499ef752f4:userdebug/release-keys
        cp -vf "$TMP_DIR/boot_raw.img" "$OUTPUT_DIR/$BOOT_OUT_NAME"
        echo "==> Успішно створено boot image з валідним AVB футером: $OUTPUT_DIR/$BOOT_OUT_NAME"
    else
        echo "ПОПЕРЕДЖЕННЯ: avbtool не знайдено, копіюється boot_raw.img без налаштування AVB."
        cp -vf "$TMP_DIR/boot_raw.img" "$OUTPUT_DIR/$BOOT_OUT_NAME"
    fi
else
    echo "==> [3/4] Стоковий boot.img не вказано або не знайдено. Створення boot.img пропущено."
    echo "    (AnyKernel3 zip вже містить нове ядро і може прошиватись напряму через рекавері)."
fi

echo "==> [4/4] Оновлення контрольних сум SHA256..."
cd "$OUTPUT_DIR"
if [ -f "$BOOT_OUT_NAME" ]; then
    sha256sum "$BOOT_OUT_NAME" "$ZIP_NAME" > SHA256SUMS
else
    sha256sum "$ZIP_NAME" > SHA256SUMS
fi
cat SHA256SUMS

echo "================================================================="
echo " Пакування завершено успішно!"
echo " Релізні файли знаходяться в: $OUTPUT_DIR"
echo "================================================================="
