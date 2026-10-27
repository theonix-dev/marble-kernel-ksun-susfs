# POCO F5 (`marble`) — LineageOS 23.2 (Android 16) Kernel with KernelSU-Next & SUSFS

**English** | [Українська](README_UA.md)

[![Android](https://img.shields.io/badge/Android-16%20(Baklava)-3DDC84?logo=android&logoColor=white)](https://android.com)
[![LineageOS](https://img.shields.io/badge/LineageOS-23.2%20Nightly-167C80?logo=lineageos&logoColor=white)](https://lineageos.org)
[![Device](https://img.shields.io/badge/Device-POCO%20F5%20%2F%20Redmi%20Note%2012%20Turbo-orange?logo=xiaomi&logoColor=white)](https://en.wikipedia.org/wiki/Poco_F5)
[![Kernel](https://img.shields.io/badge/Kernel-Linux%20GKI%205.10.269-blue?logo=linux&logoColor=white)](https://kernel.org)
[![KernelSU-Next](https://img.shields.io/badge/KernelSU--Next-v3.4.1%20(33345--5)-success)](https://github.com/KernelSU-Next/KernelSU-Next)
[![SUSFS](https://img.shields.io/badge/SUSFS-v2.3.0%20(9%20Features)-blueviolet)](https://gitlab.com/simonpunk/susfs4ksu)
[![License](https://img.shields.io/badge/License-GPL--2.0-yellow.svg)](LICENSE)
[![Status](https://img.shields.io/badge/Status-Verified%20on%20Hardware-brightgreen)](#-hardware-verification)

Source tree, build configurations, and packaging automation for **Linux GKI 5.10.269** targeting the **Xiaomi POCO F5 / Redmi Note 12 Turbo (`marble` / `marblein`)** on **LineageOS 23.2 (Android 16)**. Features integrated **KernelSU-Next v3.4.1** and **SUSFS v2.3.0** with strict Qualcomm vendor DLKM ABI compatibility and Android Verified Boot (AVB) signing.

> Technical analysis of bootloops, DLKM symbol versioning, struct page memory corruption, and AVB descriptor alignment is documented in [roadmap.md](roadmap.md).

---

## 📸 Hardware Verification

Tested on physical hardware (**POCO F5 `marble`**) running official build `lineage-23.2-20261006-NIGHTLY-marble`. All 9 Magisk/Zygisk modules operational, `sucompat` enabled, zero kernel update or driver mismatch warnings in KernelSU Manager.

<p align="center">
  <img src="assets/ksu_home.png" width="45%" alt="KernelSU Home Screen" />
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="assets/ksunext_manager.png" width="45%" alt="KernelSU-Next Manager Details" />
</p>

---

## ⚙️ Technical Specifications

* **GKI 2.0 & Vendor DLKM ABI Integrity**:
  Kernel configuration strictly adheres to the stock LineageOS memory layout. Diagnostic flags altering `struct page` (`CONFIG_PAGE_OWNER`, `CONFIG_PAGE_PINNER`, `CONFIG_DEBUG_FS`) are omitted. This maintains binary compatibility with Qualcomm proprietary modules (`/vendor_dlkm`), ensuring operational `/data` cryptographic mounting via `qcom_scm.ko`.
* **KernelSU-Next v3.4.1 (33345-5)**:
  Direct integration from [pershoot/KernelSU-Next](https://github.com/pershoot/KernelSU-Next) (`dev-susfs` branch), implementing driver protocol v3.4+, native supercall routing, and Android 16 compatibility.
* **SUSFS v2.3.0 (All 9 Subsystems Active)**:
  - `CONFIG_KSU_SUSFS_SUS_PATH` (Path hiding)
  - `CONFIG_KSU_SUSFS_SUS_MOUNT` (Mount point hiding)
  - `CONFIG_KSU_SUSFS_SUS_KSTAT` (kstat attribute spoofing)
  - `CONFIG_KSU_SUSFS_SPOOF_UNAME` (Uname spoofing)
  - `CONFIG_KSU_SUSFS_ENABLE_LOG` (Kernel logging)
  - `CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS` (Symbol concealment)
  - `CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG` (Cmdline / bootconfig spoofing)
  - `CONFIG_KSU_SUSFS_OPEN_REDIRECT` (Syscall open redirection)
  - `CONFIG_KSU_SUSFS_SUS_MAP` (Address space protection)
* **AVB Hash Footer (Flags: 3)**:
  Pre-signed boot image containing an accurate SHA-256 payload digest and verification bypass flags, preventing execution drop to Fastboot by Qualcomm ABL.

---

## 📦 Release Artifacts

Pre-built binaries are located in [`output/`](output/):

| File | Description | Size |
|---|---|---|
| **`AnyKernel3-marble-ksunext-susfs-LineageOS-23.2.zip`** | Flashable archive for Custom Recovery (OrangeFox / LineageOS Recovery) | ~22.8 MB |
| **`boot-ksunext-susfs-LineageOS-23.2-marble.img`** | Standalone boot partition image with AVB footer for Fastboot | 192 MB (201,326,592 B) |

### SHA-256 Checksums
```text
5501e483e5cda27dcd02a5589ba7886517a58a974049eb0fe92a9932eca63287  boot-ksunext-susfs-LineageOS-23.2-marble.img
e08c0c26579a9f0995836fa79494304eb68c13c7bc67ffd6e0f5b883f30ae667  AnyKernel3-marble-ksunext-susfs-LineageOS-23.2.zip
```

---

## ⚡ Installation

### Method 1: Custom Recovery (OrangeFox / LineageOS Recovery) — Recommended
1. Transfer `AnyKernel3-marble-ksunext-susfs-LineageOS-23.2.zip` to device storage or OTG drive.
2. Reboot into recovery mode:
   ```bash
   adb reboot recovery
   ```
3. Select the zip file and confirm flashing.
4. Reboot to system (`Reboot System`).

---

### Method 2: Fastboot Flashing
1. Reboot into Fastboot mode:
   ```bash
   adb reboot bootloader
   ```
2. Determine active slot:
   ```bash
   fastboot getvar current-slot
   ```
3. Flash the boot image to the active partition slot:
   * Slot **b**:
     ```bash
     fastboot flash boot_b output/boot-ksunext-susfs-LineageOS-23.2-marble.img
     ```
   * Slot **a**:
     ```bash
     fastboot flash boot_a output/boot-ksunext-susfs-LineageOS-23.2-marble.img
     ```
4. Reboot the device:
   ```bash
   fastboot reboot
   ```

---

## 🛠️ Build Pipeline

### 1. Requirements
* Linux x86_64 environment (Ubuntu 22.04+, Arch Linux, Debian)
* Packages: `python3`, `git`, `make`, `bc`, `bison`, `flex`, `libssl-dev`
* Google AOSP Clang: `clang-r547379` (or newer)
* Android Verified Boot utility: `avbtool`

### 2. Source Tree Setup & Patching
```bash
./patch_kernel.sh
```
The script clones upstream LineageOS kernel sources (`lineage-23.2`), fetches `dev-susfs` branch of KernelSU-Next, applies SUSFS kernel patches, and integrates the driver into `drivers/kernelsu`.

### 3. Compilation
Specify the toolchain path and execute compilation:
```bash
export CLANG_DIR="$HOME/toolchains/aosp-clang/clang-r547379"
./build_kernel.sh
```
Builds against `configs/marble_lineageos_23.2_ksunext_susfs.config`. The compiled `Image` binary is copied to `AnyKernel3/Image`.

### 4. Release Packaging
```bash
./package_kernel.sh
```
Generates the flashable AnyKernel3 zip and signs the boot partition image with `avbtool`.

---

## 🔍 Runtime Verification

Verify system and driver status via ADB shell:

```bash
adb shell
uname -a
# Expected: Linux localhost 5.10.269-gki-g490755fcc6cc #3 SMP PREEMPT ... aarch64 Toybox

su -v
# Expected: 3.4.1:KernelSU

ksu_susfs show version
# Expected: v2.3.0

ksu_susfs show enabled_features
# All 9 features reporting status: 1
```

---

## 🤝 Credits & Contacts

### Credits
* **[LineageOS Team](https://github.com/LineageOS)** — Kernel source tree and device platform support (`sm8450`).
* **[pershoot](https://github.com/pershoot)** — KernelSU-Next and SUSFS branch integration (`dev-susfs`).
* **[simonpunk](https://gitlab.com/simonpunk)** — SuSFS4KSU kernel subsystem design and implementation.
* **[osm0sis](https://github.com/osm0sis)** — AnyKernel3 installation backend.
* **[tiann](https://github.com/tiann)** & **[rifsxd](https://github.com/rifsxd)** — KernelSU and KernelSU-Next development.

### Contacts & Maintainer
* **Maintainer**: onix ([@theonix-dev](https://github.com/theonix-dev))
* **Email**: [onixtheoni@gmail.com](mailto:onixtheoni@gmail.com)
* **Bug Reports & Inquiries**: [GitHub Issues](https://github.com/theonix-dev/marble-kernel-ksun-susfs/issues)

---

## 📄 License

This repository is licensed under the **GNU General Public License v2.0** (GPL-2.0). See [LICENSE](LICENSE) for full legal text.
