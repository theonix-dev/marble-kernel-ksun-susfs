# Roadmap & Technical Post-Mortem: POCO F5 (`marble`) Kernel Development

> **Device**: Xiaomi POCO F5 / Redmi Note 12 Turbo (`marble` / `marblein`)  
> **Platform / SoC**: Qualcomm Snapdragon 7+ Gen 2 (SM7475, `sm8450` platform common tree)  
> **Target OS**: LineageOS 23.2 (Android 16, build `20261006-NIGHTLY-marble`)  
> **Kernel Version**: Linux GKI `5.10.269`  
> **Integrated Components**: KernelSU-Next `v3.4.1 (33345-5)` + SUSFS `v2.3.0` (all 9 features enabled)  
> **Status**: Production-ready, validated on target hardware.

---

## Table of Contents

1. [Overview](#overview)
2. [Incident Analysis and Remediation](#incident-analysis-and-remediation)
   - [Issue 1: KernelSU-Next Driver Mismatch and sucompat Deprecation](#issue-1-kernelsu-next-driver-mismatch-and-sucompat-deprecation)
   - [Issue 2: RescueParty Bootloop via Vendor DLKM Incompatibility](#issue-2-rescueparty-bootloop-via-vendor-dlkm-incompatibility)
   - [Issue 3: Bootloader Drop via AVB Hash and Footer Mismatch](#issue-3-bootloader-drop-via-avb-hash-and-footer-mismatch)
   - [Issue 4: Kernel Memory Corruption via CONFIG_PAGE_OWNER ABI Incompatibility](#issue-4-kernel-memory-corruption-via-config_page_owner-abi-incompatibility)
   - [Issue 5: Verification and Final Build (Build #3)](#issue-5-verification-and-final-build-build-3)
3. [Architecture and Component Compatibility](#architecture-and-component-compatibility)
4. [Build Pipeline and Reproducibility](#build-pipeline-and-reproducibility)
   - [1. Toolchain Setup (AOSP Clang)](#1-toolchain-setup-aosp-clang)
   - [2. Source Tree and Patch Application](#2-source-tree-and-patch-application)
   - [3. GKI Configuration](#3-gki-configuration)
   - [4. Kernel Image Compilation](#4-kernel-image-compilation)
   - [5. Packaging boot.img (AVB Sign) and AnyKernel3 Zip](#5-packaging-bootimg-avb-sign-and-anykernel3-zip)
5. [Installation and Flashing Guide](#installation-and-flashing-guide)
6. [Device Verification Checklist](#device-verification-checklist)
7. [Technical Takeaways](#technical-takeaways)

---

## Overview

This project provides a reliable, production-ready custom kernel for the **Xiaomi POCO F5 (marble)** running official **LineageOS 23.2 (Android 16)** on top of **Linux GKI 5.10.269**, integrating:
1. **KernelSU-Next v3.4.1**: An updated KernelSU fork supporting modern system call interfaces and Android 16 userspace requirements.
2. **SUSFS (SuSFS4KSU) v2.3.0**: A kernel subsystem providing mount hiding, kstat spoofing, open redirect, path obfuscation, and evasion against modern root detection implementations (Play Integrity, banking applications, RootBeer, etc.).

Achieving a stable boot required addressing four distinct boot-critical issues: symbol version mismatches, Android Verified Boot (AVB) descriptor integrity failures, ABI layout divergences in memory structures, and driver protocol updates.

---

## Incident Analysis and Remediation

### Issue 1: KernelSU-Next Driver Mismatch and sucompat Deprecation

#### 1. Problem Description
Following an update of the **KernelSU-Next Manager** application to version **v3.4.1 (33345-5)**, the application reported:
* `Kernel update required`
* `SUCOMPAT DISABLED`
* Superuser privilege escalation was non-functional or degraded.

#### 2. Root Cause
The installed kernel contained a KernelSU driver implementing protocol version `12874` (KernelSU ~1.0.x generation). Manager version 3.4.1 requires an updated driver ABI, revised IOCTL command handling, and native SUSFS supercall support absent from legacy driver implementations.

#### 3. Remediation
The kernel was rebuilt from source using:
* Kernel Source: [LineageOS/android_kernel_xiaomi_sm8450](https://github.com/LineageOS/android_kernel_xiaomi_sm8450) (branch `lineage-23.2`).
* KernelSU-Next Source: [pershoot/KernelSU-Next](https://github.com/pershoot/KernelSU-Next) (branch `dev-susfs`). This branch integrates SUSFS directly into the driver tree, preventing patch drift and rejects associated with upstream `tiann/KernelSU`.
* SUSFS Patch Source: [simonpunk/susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) (branch `gki-android13-5.10`).

---

### Issue 2: RescueParty Bootloop via Vendor DLKM Incompatibility

#### 1. Symptoms
Upon flashing the initial build to slot `boot_b`:
1. The device powered on to the POCO boot logo.
2. Vibration triggered, and the display turned off.
3. The device rebooted exactly 10 consecutive times.
4. On the 10th reboot, the device dropped into **Fastboot (Bootloader)** mode.

#### 2. Root Cause Analysis
A cycle of 10 consecutive reboots indicates invocation of the **Android RescueParty** subsystem:
```text
RescueParty: Attempting to recover from crash loop. Level: RESCUE_LEVEL_RESET
RescueParty: Reboot loop detected (count: 10). Dropping to bootloader fallback.
```
Failures in critical system daemons (`system_server`, `zygote`, `keystore2`, `vold`) prior to `sys.boot_completed` increment the RescueParty failure counter on each boot attempt.

Analysis of kernel crash buffers (`mtdoops` / `pstore`) and installed partition metadata revealed:
* The device contained older vendor partitions (`vendor_dlkm`, `vendor_boot`, and `dtbo` from November 28, 2025) built against **Linux 5.10.246**.
* The newly built kernel image was compiled against **Linux 5.10.269** (LineageOS 23.2 nightly).
* During boot, kernel module loading (`CONFIG_MODVERSIONS`) verified exported symbol CRC checksums (`module_layout`).
* Due to CRC mismatches between 5.10.246 and 5.10.269, the kernel rejected proprietary Qualcomm loadable modules (`qcom_scm.ko`, touchscreen drivers, display DRM drivers, hardware cryptography drivers).
* Without `qcom_scm.ko`, the `android.system.keystore2` service failed with error `-28` (`ENOSPC` / failure to communicate with the hardware keystore via SCM). Consequently, `vold` could not decrypt the `/data` partition, resulting in repeated userspace crashes.

#### 3. Remediation
Synchronize all vendor partitions with the target LineageOS build:
1. Extract the current partitions from `lineage-23.2-20261006-nightly-marble-signed.zip` using `payload-dumper-go`:
   - `dtbo.img`
   - `vendor_boot.img`
   - `vendor_dlkm.img`
2. Flash the extracted images to the active slot via `fastbootd`:
   ```bash
   fastboot flash dtbo dtbo.img
   fastboot flash vendor_boot vendor_boot.img
   fastboot flash vendor_dlkm vendor_dlkm.img
   ```
Following synchronization, the modules in `/vendor_dlkm` matched version 5.10.269 with CRC `0x7c24b32d module_layout`.

---

### Issue 3: Bootloader Drop via AVB Hash and Footer Mismatch

#### 1. Symptoms
After repacking `boot.img` via `magiskboot repack` and flashing through `fastboot flash boot_b boot.img`:
* The kernel did not execute.
* Immediately after the initial vibration, the device dropped directly into **Fastboot** mode.

#### 2. Root Cause Analysis
Inspection of the stock `boot.img` via `avbtool info_image` showed:
* The stock partition image is exactly **201,326,592 bytes** (192 MiB, matching the physical `boot` partition size on `marble`).
* An **AVB Footer (VBMeta Descriptor)** is appended at the end of the partition image:
  ```text
  Footer version:           1.0
  Image size:               201326592 bytes
  Original image size:      50003968 bytes
  Descriptors:
      Hash descriptor:
        Image Size:            50003968 bytes
        Partition Name:        boot
        Digest:                c2c25652f4c3... (stock payload digest)
  ```
* Repacking with `magiskboot repack`:
  - Replaced the kernel payload with a different file size.
  - Stored either an invalid AVB footer or retained the **stale SHA256 digest** and original payload size from the stock kernel.
* The Qualcomm ABL (Android Bootloader) validated partition integrity before booting. It computed the salted SHA256 digest over the new kernel image, detected a mismatch with the digest registered in the footer, marked the partition as corrupted/tampered, and dropped execution to Fastboot.

#### 3. Remediation
Re-sign the image and regenerate the AVB footer with verification disabled (`--flags 3`):
```bash
avbtool erase_footer --image boot.img
avbtool add_hash_footer \
    --image boot.img \
    --partition_name boot \
    --partition_size 201326592 \
    --flags 3 \
    --prop com.android.build.boot.os_version:16 \
    --prop com.android.build.boot.fingerprint:POCO/lineage_marble/marble:16/BP4A.251205.006/499ef752f4:userdebug/release-keys
```
* The `--flags 3` argument sets `AVB_VBMETA_IMAGE_FLAGS_HASHTREE_ERROR_MODE_RESTART` and disables verification enforcement.
* `avbtool` computed the salted SHA256 digest for the new kernel payload and recorded the accurate `Original image size`.
* Qualcomm ABL validated the footer structure and transferred control to the kernel.

---

### Issue 4: Kernel Memory Corruption via CONFIG_PAGE_OWNER ABI Incompatibility

#### 1. Symptoms
Following the AVB fix, the kernel booted and the LineageOS boot animation appeared. After 15–20 seconds, the device vibrated and resumed the 10-reboot RescueParty bootloop.

#### 2. Root Cause Analysis
The stock LineageOS kernel booted without failure on the same partition set, whereas the custom 5.10.269 build failed during early userspace initialization.

The kernel configuration extracted from the functional stock kernel using `scripts/extract-ikconfig` was compared against the custom build configuration.

In the initial build script, the kernel configuration was generated via:
```bash
make gki_defconfig vendor/waipio_GKI.config vendor/xiaomi_GKI.config vendor/marble_GKI.config
```
Merging the Xiaomi vendor fragments enabled debug options:
```text
CONFIG_PAGE_OWNER=y
CONFIG_PAGE_PINNER=y
CONFIG_PAGE_EXTENSION=y
CONFIG_DEBUG_FS=y
```
In contrast, the official LineageOS kernel configuration defined:
```text
# CONFIG_PAGE_OWNER is not set
# CONFIG_PAGE_PINNER is not set
# CONFIG_DEBUG_FS is not set
```

#### Failure Mechanism in C Memory Structures:
1. In `include/linux/mm_types.h`, the size of `struct page` changes based on compile-time definitions:
   ```c
   struct page {
       unsigned long flags;
       ...
   #if defined(CONFIG_PAGE_EXTENSION)
       /* Page extension tracking metadata */
   #endif
   };
   ```
2. The precompiled Qualcomm vendor modules (`qcom_scm.ko`, Adreno GPU driver `kgsl.ko`, display DRM driver) in `/vendor_dlkm` were compiled by LineageOS **without** `CONFIG_PAGE_EXTENSION`.
3. When the custom kernel allocated pages (via DMA or `alloc_pages`) and passed pointers to `qcom_scm.ko`, the module accessed struct members using compact offsets, whereas the kernel core used expanded offsets.
4. This mismatch resulted in silent kernel memory corruption. When `keystore2` dispatched cryptographic requests through Qualcomm SCM, memory buffer corruption caused the operations to fail with error `-28`. The volume manager (`vold`) could not mount `/data`, triggering unrecoverable userspace crashes.

#### 3. Remediation
Do not merge Xiaomi vendor configuration fragments (`vendor/waipio_GKI.config`, `vendor/xiaomi_GKI.config`, `vendor/marble_GKI.config`).
Base the build configuration exclusively on clean `gki_defconfig` with the minimal required flags for KernelSU-Next and SUSFS:
```ini
CONFIG_TMPFS_XATTR=y
CONFIG_KSU=y
CONFIG_KSU_THRONE_TRACKER_ALWAYS_THREADED=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
```
Ensure `CONFIG_PAGE_OWNER`, `CONFIG_PAGE_PINNER`, `CONFIG_PAGE_EXTENSION`, and `CONFIG_DEBUG_FS` remain disabled to preserve 100% ABI compatibility with vendor modules.

---

### Issue 5: Verification and Final Build (Build #3)

Kernel recompiled with the clean configuration (Build #3) showed:
1. **Boot Performance**: Cold boot to Android desktop completed in **25 seconds** without intermediate restarts.
2. **Diagnostics via `adb shell`**:
   ```bash
   $ uname -a
   Linux localhost 5.10.269-gki-g490755fcc6cc #3 SMP PREEMPT Sun Oct 11 06:03:47 EEST 2026 aarch64 Toybox

   $ su -v
   3.4.1:KernelSU

   $ id
   uid=0(root) gid=0(root) groups=0(root) context=u:r:ksu:s0

   $ ksu_susfs show version
   v2.3.0
   ```
3. **SUSFS Feature Verification (all 9 features active)**:
   ```text
   CONFIG_KSU_SUSFS_SUS_PATH: 1
   CONFIG_KSU_SUSFS_SUS_MOUNT: 1
   CONFIG_KSU_SUSFS_SUS_KSTAT: 1
   CONFIG_KSU_SUSFS_SPOOF_UNAME: 1
   CONFIG_KSU_SUSFS_ENABLE_LOG: 1
   CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS: 1
   CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG: 1
   CONFIG_KSU_SUSFS_OPEN_REDIRECT: 1
   CONFIG_KSU_SUSFS_SUS_MAP: 1
   ```
4. **KernelSU-Next Manager Status**:
   - Status: `Working [BUILT-IN (GKI2)]`
   - Kernel update warnings: None.
   - All 9 Magisk/Zygisk modules functional: BCR, Play Integrity Fix, GooglePhotos ReVanced, Music ReVanced, SuSFS-for-KernelSU, Zygisk Next 1.5.0, etc.

---

## Architecture and Component Compatibility

```
+------------------------------------------------------------------------+
|                   Android 16 Userspace (LineageOS 23.2)                |
|  - KernelSU-Next Manager v3.4.1 (33345-5)                              |
|  - Active Modules: Zygisk-Next 1.5.0, PIF, SuSFS Module, BCR, ReVanced  |
+------------------------------------------------------------------------+
                                    ▲
                                    │ (Syscalls / IOCTL / Supercall)
+------------------------------------------------------------------------+
|              Linux GKI Kernel 5.10.269-gki-g490755fcc6cc #3            |
|  - KernelSU-Next (pershoot/dev-susfs)                                  |
|  - SUSFS v2.3.0 (simonpunk/gki-android13-5.10)                        |
|  - Clean struct page ABI (PAGE_OWNER=n, DEBUG_FS=n)                    |
|  - AVB Hash Footer Flags: 3 (Permissive / Valid Digest)                |
+------------------------------------------------------------------------+
        ▲                                                ▲
        │                                                │
+-------------------------------+              +-------------------------+
|  /vendor_dlkm (Qualcomm)      |              |  Qualcomm ABL Bootloader|
|  - qcom_scm.ko (5.10.269)     |              |  - Slot: _b (Active)    |
|  - msm_drm.ko                 |              |  - AVB Verification: OK |
|  - kgsl.ko (Adreno GPU)       |              +-------------------------+
+-------------------------------+
```

---

## Build Pipeline and Reproducibility

### 1. Toolchain Setup (AOSP Clang)

Building GKI 5.10 for Android 16 requires the official Google AOSP Clang toolchain:
* **Recommended Version**: `clang-r547379` (LLVM 20.0.0) or recent AOSP Clang releases.
* **Installation**:
  ```bash
  mkdir -p ~/toolchains/aosp-clang
  cd ~/toolchains/aosp-clang
  git clone --depth 1 -b master https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 clang-repo
  cp -r clang-repo/clang-r547379 ./
  ```

### 2. Source Tree and Patch Application

Execute the automated patch script:
```bash
./patch_kernel.sh
```
Operations performed:
1. Clones `LineageOS/android_kernel_xiaomi_sm8450` (branch `lineage-23.2`).
2. Clones `simonpunk/susfs4ksu` (branch `gki-android13-5.10`).
3. Clones `pershoot/KernelSU-Next` (branch `dev-susfs`).
4. Applies kernel patch `50_add_susfs_in_gki-android13-5.10.patch`.
5. Links KernelSU-Next into the kernel source tree (`drivers/kernelsu`).
6. Applies the `fake_state` compatibility patch in `selinux_hide.c` for Linux 5.10.
7. Disables the `-dirty` localversion flag in `scripts/setlocalversion` to preserve version string integrity.

### 3. GKI Configuration

The validated configuration file is maintained at:
```text
configs/marble_lineageos_23.2_ksunext_susfs.config
```
This configuration maintains 100% parity with stock LineageOS 23.2 GKI, enables all KernelSU-Next and SUSFS flags, and explicitly omits ABI-altering `PAGE_OWNER` flags.

### 4. Kernel Image Compilation

Execute:
```bash
./build_kernel.sh
```
Operations performed:
1. Applies `configs/marble_lineageos_23.2_ksunext_susfs.config` via `make O=out olddefconfig`.
2. Compiles the kernel image: `make -j$(nproc) O=out Image`.
3. Copies the output binary to `AnyKernel3/Image`.

### 5. Packaging boot.img (AVB Sign) and AnyKernel3 Zip

Execute:
```bash
./package_kernel.sh AnyKernel3/Image
```
Operations performed:
1. Generates flashable zip archive `output/AnyKernel3-marble-ksunext-susfs-LineageOS-23.2.zip`.
2. Repacks the stock boot image with `magiskboot` (if `stock_boot/boot.img` is present).
3. Invokes `avbtool` with `--flags 3` to sign and output `output/boot-ksunext-susfs-LineageOS-23.2-marble.img`.
4. Generates cryptographic checksums in `output/SHA256SUMS`.

---

## Installation and Flashing Guide

### Method A: Custom Recovery (Recommended)
1. Boot device into **OrangeFox** or **LineageOS Recovery**.
2. Navigate to the flash menu and select:
   `output/AnyKernel3-marble-ksunext-susfs-LineageOS-23.2.zip`
3. Swipe to flash (AnyKernel3 unpacks the existing boot partition of the active slot, replaces the kernel payload, and repacks the image).
4. Reboot to system.

### Method B: Fastboot Flashing
1. Reboot the device to Fastboot mode:
   ```bash
   adb reboot bootloader
   ```
2. Identify the active slot:
   ```bash
   fastboot getvar current-slot
   # Output example: current-slot: b
   ```
3. Flash the repacked boot image to the active slot:
   ```bash
   fastboot flash boot_b output/boot-ksunext-susfs-LineageOS-23.2-marble.img
   ```
   *(Substitute `boot_a` if the active slot is `a`)*.
4. Reboot the device:
   ```bash
   fastboot reboot
   ```

---

## Device Verification Checklist

Verify runtime status via terminal (`adb shell` or Termux):

| Check | Expected Result | Command |
|---|---|---|
| **Kernel Version** | `5.10.269-gki-g490755fcc6cc #3` | `uname -a` |
| **KernelSU Version** | `3.4.1:KernelSU` | `su -v` |
| **Root Context** | `uid=0(root) ... context=u:r:ksu:s0` | `id` |
| **SUSFS Version** | `v2.3.0` | `ksu_susfs show version` |
| **SUSFS Features** | All 9 features return `1` | `ksu_susfs show enabled_features` |
| **Manager Status** | `Working [BUILT-IN (GKI2)]` | KernelSU-Next Manager UI |

---

## Technical Takeaways

1. **GKI 2.0 and Strict DLKM Struct Alignment**:
   In Android 13+ architectures, the Generic Kernel Image (GKI) is decoupled from vendor loadable kernel modules (`vendor_dlkm`). Any variance in configuration flags that alter data structure layouts (`CONFIG_PAGE_OWNER`, `CONFIG_PAGE_EXTENSION`) causes fatal memory corruption in vendor drivers without userspace boot capability.
2. **AVB Footer Integrity for Bootloader Execution**:
   Replacing kernel payloads with `magiskboot` without regenerating AVB descriptors leads to bootloader execution drops. The Qualcomm ABL drops execution to Fastboot whenever the salted SHA256 digest in the footer fails to match the partition image contents.
3. **Pershoot KernelSU-Next Tree as Canonical Source**:
   For Linux 5.10+ kernels with SUSFS integration, the `pershoot:dev-susfs` branch avoids patch merge conflicts and maintains native synchronization between KernelSU-Next and SUSFS interfaces.
