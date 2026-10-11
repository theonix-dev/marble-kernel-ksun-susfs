# AGENTS.md

## Overview

This repository contains documentation, patches, and build automation for building the Android Linux kernel for **Xiaomi POCO F5 / Redmi Note 12 Turbo (`marble`)** running **LineageOS 23.2 (Android 16)** with integrated **KernelSU-Next** and **SUSFS (SuSFS4KSU)**.

## Target Hardware & Software Stack

- **Device**: Xiaomi POCO F5 / Redmi Note 12 Turbo (`marble` / `marblein`)
- **Platform / SoC**: Qualcomm Snapdragon 7+ Gen 2 (`SM7475`), using Xiaomi `sm8450` platform common tree
- **Target OS**: LineageOS 23.2 (Android 16)
- **Kernel Version**: Linux `5.10.x` (GKI 2.0 based)
- **Upstream Kernel Repo**: `https://github.com/LineageOS/android_kernel_xiaomi_sm8450.git` (branch: `lineage-23.2`)
- **Root Flavor**: KernelSU-Next (Fork: `https://github.com/pershoot/KernelSU-Next.git`, branch: `dev-susfs`)
- **SUSFS Subsystem**: `https://gitlab.com/simonpunk/susfs4ksu.git` (branch: `gki-android13-5.10`)

## Key Architecture & Integration Rules

1. **Do NOT apply `10_enable_susfs_for_ksu.patch` to KernelSU-Next**:
   - The stock patch in `simonpunk/susfs4ksu` was created for the flatter directory layout of official `tiann/KernelSU`.
   - KernelSU-Next has restructured directories (`feature/`, `supercall/`, `infra/`, etc.).
   - The canonical approach used across custom GKI builds (e.g. WildKernels) is using `pershoot/KernelSU-Next` (branch `dev-susfs`), which already contains native SUSFS integration.

2. **Kernel-side SUSFS Patch**:
   - Files to copy into kernel root:
     - `kernel_patches/fs/*` -> `fs/`
     - `kernel_patches/include/linux/*` -> `include/linux/`
   - Kernel diff patch: `50_add_susfs_in_gki-android13-5.10.patch` applies directly with zero rejects to `android_kernel_xiaomi_sm8450` branch `lineage-23.2`.

3. **Driver Integration**:
   - Link `../KernelSU-Next/kernel` into `drivers/kernelsu`.
   - Append `obj-$(CONFIG_KSU) += kernelsu/` to `drivers/Makefile`.
   - Add `source "drivers/kernelsu/Kconfig"` inside `drivers/Kconfig` before the closing `endmenu`.

4. **Kconfig Invariants**:
   - The following flags must be present in `arch/arm64/configs/vendor/marble_GKI.config` or `gki_defconfig`:
     ```kconfig
     CONFIG_KSU=y
     CONFIG_KSU_SUSFS=y
     CONFIG_KSU_SUSFS_SUS_PATH=y
     CONFIG_KSU_SUSFS_SUS_MOUNT=y
     CONFIG_KSU_SUSFS_SUS_KSTAT=y
     CONFIG_KSU_SUSFS_SPOOF_UNAME=y
     CONFIG_KSU_SUSFS_ENABLE_LOG=y
     CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
     CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
     CONFIG_KSU_SUSFS_SUS_MAP=y
     CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
     CONFIG_TMPFS_XATTR=y
     ```

5. **Localversion & Integrity**:
   - Prevent `-dirty` tag from polluting `/proc/version` by editing `scripts/setlocalversion`.

## Build & Toolchain Guidelines

- **Compiler**: AOSP Clang (`clang-r450784d` or Clang 14.x-17.x).
- **Environment flags**:
  ```bash
  export ARCH=arm64
  export SUBARCH=arm64
  export CROSS_COMPILE=aarch64-linux-gnu-
  export LLVM=1
  export LLVM_IAS=1
  ```
- **Config targets**:
  > **CRITICAL LESSON**: Do **NOT** merge `vendor/waipio_GKI.config` or `vendor/xiaomi_GKI.config`! They enable `CONFIG_PAGE_OWNER=y` and `CONFIG_PAGE_PINNER=y`, expanding `struct page` and corrupting memory in Qualcomm vendor DLKM (`qcom_scm.ko`), causing keystore2 -28 and RescueParty bootloops.
  Use the verified clean config `configs/marble_lineageos_23.2_ksunext_susfs.config` or pure `gki_defconfig` merged with `configs/ksu_susfs.fragment`:
  ```bash
  cp configs/marble_lineageos_23.2_ksunext_susfs.config out/.config
  make O=out olddefconfig
  make -j$(nproc) O=out Image
  ```

## Agent Workflows

- When updating kernel commits from LineageOS upstream, check for git conflicts in `fs/proc/`, `fs/namespace.c`, and `fs/notify/fdinfo.c`.
- If compiling standalone kernels, do not commit compiled binaries (`Image`, object files, etc.) to version control.
- Keep `patch_kernel.sh` idempotent so it can be re-run safely.
