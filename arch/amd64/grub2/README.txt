GRUB2 payload for BIOS and UEFI.

    grub_comp/             packed onto boot at the same relative paths
    early-efi.cfg          embedded into BOOTX64.EFI / BIOS core.img
    i386-pc/               BIOS GRUB2 modules (Alpine grub-bios)
    x86_64-efi/            UEFI GRUB2 modules (Alpine grub-efi)
    EFI/                   copied as a whole tree onto the ESP (FAT16)

EFI/ layout (all files under EFI/ are packed into the image):

    EFI/BOOT/BOOTX64.EFI   UEFI removable-media fallback (required for QEMU/USB)
    EFI/<vendor>/<name>.efi
                           optional extra copies for firmware that looks up a
                           fixed path (same GRUB image, different location)

BOOTX64.EFI:
1. scripts/mkefi.sh (needs host grub-mkimage; embeds almost all x86_64-efi
   .mod files, omitting unit-test modules, keeping test.mod)
2. drop a ready file into EFI/BOOT/

mkefi.sh / mkimg.sh will not overwrite an existing BOOTX64.EFI.
Edit MODULES in scripts/mkefi.sh to add or drop embedded modules.
Vendor files are not generated; add them under EFI/<vendor>/ by hand.
