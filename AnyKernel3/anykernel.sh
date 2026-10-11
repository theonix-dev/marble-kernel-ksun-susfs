### AnyKernel3 Ramdisk Mod Script
## POCO F5 / Redmi Note 12 Turbo (marble) KernelSU-Next & SUSFS

properties() { '
kernel.string=KernelSU-Next & SUSFS for POCO F5 (marble) - LineageOS 23.2
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=marble
device.name2=marblein
device.name3=
device.name4=
device.name5=
supported.versions=13 - 16
supported.patchlevels=
'; }

### AnyKernel install
BLOCK=boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=1;

# import functions/variables and setup patching
. tools/ak3-core.sh;

# boot install (GKI split & flash)
split_boot;
flash_boot;
