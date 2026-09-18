Packed onto the boot partition at the same relative paths.
EFI/BOOT/grub.cfg is also merged onto the ESP.

    grub/grub.cfg          real GRUB2 menu
    grub/grub.conf         stub: configfile /grub/grub.cfg
    grub/menu.lst          stub: configfile /grub/grub.cfg
    EFI/BOOT/grub.cfg      stub: configfile /grub/grub.cfg
    EFI/BOOT/BOOTX64.cfg   stub: configfile /grub/grub.cfg
    EFI/BOOT/BOOTX64.conf  stub: configfile /grub/grub.cfg
    loader/loader.conf     stub: configfile /grub/grub.cfg
