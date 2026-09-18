GRUB Legacy (GRUB1, 0.97) payload. BIOS only; no UEFI.

    grub_comp/             packed onto boot at the same relative paths
    stage1                 MBR loader (drop in; not tracked)
    stage2                 core
    *_stage1_5             complete GNU 0.97 set (10 files):
                           e2fs fat ffs iso9660 jfs minix reiserfs ufs2 vstafs xfs
                           e2fs_stage1_5 is required (boot partition is ext2)

Packed onto the boot partition as /grub/*.
Install to MBR needs host grub-legacy (grub --batch setup), not grub2 grub-install.

Upstream: GNU GRUB 0.97. Stage binaries currently from CentOS 6.10 grub-0.97
(el7 and later ship GRUB2 only). Place stage1, stage2, and *_stage1_5 here.
