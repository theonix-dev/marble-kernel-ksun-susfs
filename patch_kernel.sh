#!/usr/bin/env bash
# ==============================================================================
# Script: patch_kernel.sh
# Purpose: Automatically clone, patch, and configure LineageOS kernel for marble
#          with KernelSU-Next and SUSFS.
# Target: POCO F5 / Redmi Note 12 Turbo (marble) - LineageOS 23.2 (Android 16)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${1:-$SCRIPT_DIR/build_env}"

echo "==> Рабочая директория: $WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 1. Клонирование репозитория ядра (LineageOS 23.2)
if [ ! -d "kernel" ]; then
    echo "==> [1/5] Клонирование репозитория ядра (lineage-23.2)..."
    git clone --depth 1 -b lineage-23.2 https://github.com/LineageOS/android_kernel_xiaomi_sm8450.git kernel
else
    echo "==> [1/5] Ядро уже склонировано, пропускаем..."
fi

# 2. Клонирование патчей SUSFS4KSU (ветка gki-android13-5.10 для Linux 5.10)
if [ ! -d "susfs4ksu" ]; then
    echo "==> [2/5] Клонирование susfs4ksu (gki-android13-5.10)..."
    git clone --depth 1 -b gki-android13-5.10 https://gitlab.com/simonpunk/susfs4ksu.git susfs4ksu
else
    echo "==> [2/5] susfs4ksu уже склонирован, пропускаем..."
fi

# 3. Клонирование KernelSU-Next (ветка dev-susfs)
if [ ! -d "KernelSU-Next" ]; then
    echo "==> [3/5] Клонирование pershoot/KernelSU-Next (dev-susfs)..."
    git clone --depth 1 -b dev-susfs https://github.com/pershoot/KernelSU-Next.git KernelSU-Next
else
    echo "==> [3/5] KernelSU-Next уже склонирован, пропускаем..."
fi

cd kernel

# 4. Применение патчей ядра SUSFS
echo "==> [4/5] Применение патчей SUSFS к ядру..."
cp -vf ../susfs4ksu/kernel_patches/fs/* fs/
cp -vf ../susfs4ksu/kernel_patches/include/linux/* include/linux/

if git apply --check ../susfs4ksu/kernel_patches/50_add_susfs_in_gki-android13-5.10.patch 2>/dev/null; then
    git apply ../susfs4ksu/kernel_patches/50_add_susfs_in_gki-android13-5.10.patch
    echo "==> Патч 50_add_susfs_in_gki-android13-5.10.patch успешно применен."
else
    echo "==> Патч SUSFS уже применен или возник конфликт."
fi

# 5. Интеграция KernelSU-Next
echo "==> [5/5] Интеграция KernelSU-Next в drivers/..."
ln -sf "$(realpath ../KernelSU-Next/kernel)" drivers/kernelsu

if ! grep -q "kernelsu" drivers/Makefile; then
    printf "\nobj-\$(CONFIG_KSU) += kernelsu/\n" >> drivers/Makefile
    echo "==> drivers/Makefile обновлен."
fi

if ! grep -q "drivers/kernelsu/Kconfig" drivers/Kconfig; then
    sed -i '/endmenu/i\source "drivers/kernelsu/Kconfig"' drivers/Kconfig
    echo "==> drivers/Kconfig обновлен."
fi

# Совместимость Linux 5.10 SUSFS: fake_state в selinux_hide.c
SELINUX_HIDE="../KernelSU-Next/kernel/feature/selinux_hide.c"
if [ -f "$SELINUX_HIDE" ] && ! grep -q "fake_state" "$SELINUX_HIDE"; then
    sed -i '/#endif \/\/ #ifndef CONFIG_KSU_SUSFS/a #ifdef CONFIG_KSU_SUSFS\nstruct selinux_state fake_state;\n#endif' "$SELINUX_HIDE"
    sed -i '/pr_info("selinux_hide: init selinux hide\\n");/a #ifdef CONFIG_KSU_SUSFS\n#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 6, 0)\n    fake_state.initialized = true;\n    fake_state.policy = backup_sepolicy;\n#endif\n#endif' "$SELINUX_HIDE"
    echo "==> Патч fake_state для Linux 5.10 применен в KernelSU-Next."
fi

# 6. Обновление конфигурации marble_GKI.config
CONFIG_FILE="arch/arm64/configs/vendor/marble_GKI.config"
echo "==> Проверка флагов конфигурации в $CONFIG_FILE..."

CONFIGS=(
    "CONFIG_KSU=y"
    "CONFIG_KSU_SUSFS=y"
    "CONFIG_KSU_SUSFS_SUS_PATH=y"
    "CONFIG_KSU_SUSFS_SUS_MOUNT=y"
    "CONFIG_KSU_SUSFS_SUS_KSTAT=y"
    "CONFIG_KSU_SUSFS_SPOOF_UNAME=y"
    "CONFIG_KSU_SUSFS_ENABLE_LOG=y"
    "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y"
    "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y"
    "CONFIG_KSU_SUSFS_SUS_MAP=y"
    "CONFIG_KSU_SUSFS_OPEN_REDIRECT=y"
    "CONFIG_TMPFS_XATTR=y"
)

for cfg in "${CONFIGS[@]}"; do
    key="${cfg%%=*}"
    if ! grep -q "^$key=" "$CONFIG_FILE"; then
        echo "$cfg" >> "$CONFIG_FILE"
    fi
done

if [ -f "$SCRIPT_DIR/configs/marble_lineageos_23.2_ksunext_susfs.config" ]; then
    cp -vf "$SCRIPT_DIR/configs/marble_lineageos_23.2_ksunext_susfs.config" arch/arm64/configs/lineage_marble_ksunext_susfs_defconfig
    echo "==> Перевірений defconfig встановлено: arch/arm64/configs/lineage_marble_ksunext_susfs_defconfig"
fi

# 7. Отключение суффикса -dirty в версии ядра
if [ -f "scripts/setlocalversion" ]; then
    sed -i 's/printf '\''%s'\'' -dirty/printf '\''%s'\'' '\'''\''/g' scripts/setlocalversion
fi

echo "================================================================="
echo " Готово! Ядро успешно пропатчено под KernelSU-Next и SUSFS."
echo " Директория пропатченного ядра: $WORK_DIR/kernel"
echo " Инструкция по сборке описана в $SCRIPT_DIR/README.md"
echo "================================================================="
