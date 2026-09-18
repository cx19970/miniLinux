FHS tree packed as the initramfs root.

    init                 startup script (busybox sh; no pivot)
    bin/busybox          Alpine busybox-static
    bin/ bash jq ldconfig parted udevadm rsync parser
    sbin/ disk, crypto, kmod, and net helpers (see below)
    lib/ lib64/ usr/lib/ Ubuntu 22.04 glibc, libstdc++, and extra .so
    etc/passwd group nsswitch.conf ld.so.conf pam.d mdev.conf profile

Drop binaries and libraries into the matching directories. Do not add
Alpine musl .so files (they conflict with Ubuntu glibc).

BusyBox applets (ls, mount, getty, mdev, ...) are created at pack time by
scripts/mkinitramfs.sh from `busybox --list-full`. Real files already in the
tree are not overwritten, so GNU wget / kmod / e2fsck win over applets.

Sources (drop in; build.sh does not download):
    Alpine v3.21  busybox-static  -> bin/busybox
    Ubuntu 22.04  libc6, libgcc-s1, libstdc++6, libc-bin (ldconfig)
    Ubuntu 22.04  bash jq parted udev rsync acpid cryptsetup-bin
                  e2fsprogs ethtool fdisk ifenslave kmod btrfs-progs
                  squashfs-tools wget wput netmask libpam0g libpam-modules
    Debian        reiserfsprogs when Ubuntu no longer ships it
    Reference fs  bin/parser and libxml2.so.2 (no distro package for parser)

Fetch extras (Linux/WSL, cache in out/cache/initramfs-debs):
    scripts/fetch-initramfs-extras.sh

scripts/mkinitramfs.sh packs this directory to initramfs.cpio.gz
(excluding README.txt, .gitkeep, and the archive itself).
You may also replace initramfs.cpio.gz directly.

This initramfs is the running root (no pivot). Extra CLI tools here match
the gen-sys-img-x86/fs capability list; further apps can still use plugins
or a persistent partition.
