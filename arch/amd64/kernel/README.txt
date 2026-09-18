Place an amd64 bzImage in this directory. Filename must be:

    bzImage

Current drop-in: Alpine v3.21 netboot vmlinuz-lts (Linux 6.12.81, ~13MiB).
linux.5.10.246-config is a local build config if you compile your own.

This project does not build the kernel. Run scripts/mkimg.sh after placing it.
Without bzImage the image can still be partitioned (for ESP/partition checks),
but GRUB cannot boot a kernel.
