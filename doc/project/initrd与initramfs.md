## 技术说明

**initrd（旧）**  内核把一块磁盘映像当块设备挂上（常见是 gzip 的 ext2）。内核要 `CONFIG_BLK_DEV_RAM` + `CONFIG_BLK_DEV_INITRD`。现在很少用。

**initramfs（现）**  把目录打成 **cpio**（常再 gzip），启动时解到 **tmpfs**，根上必须有 `/init`。对应 `CONFIG_BLK_DEV_INITRD`+ cpio。Linux 2.6 起就是这条路。

GRUB 的 `initrd` 会把文件交给内核；内核看到 **newc cpio** 就当 initramfs，不会当成旧 initrd。

## 项目落地实情

本仓库菜单写 `initrd /initramfs.cpio.gz`，文件本身是 newc cpio。

本仓库源树是 `arch/amd64/initramfs/`（FHS 根）。`scripts/mkinitramfs.sh` 打成 `initramfs.cpio.gz`，不打 `README.txt`、`.gitkeep` 和这份归档自身。启动后停在 initramfs 里的 busybox sh，本阶段不切根。

运行时：
- 程序：Alpine **静态** busybox（`bin/busybox`），不引入 musl `.so`。打包时按 `busybox --list-full` 在 FHS 路径上建 applet 符号链接；树上已有的真实文件（GNU wget、kmod、e2fsck 等）不会被覆盖。
- 对齐参考目录能力的独立程序（bash、jq、parted、udevadm、rsync、cryptsetup、e2fsprogs、ethtool、fdisk/sfdisk、btrfs/squashfs/reiserfs 工具、wget/wput 等）从 **Ubuntu 22.04** deb 取出；`parser` 来自参考树。Alpine 里多数 `*-static` 只是 `.a`，动态 Alpine 程序依赖 musl，不能与 Ubuntu glibc 混放。
- 动态库：Ubuntu 22.04 的 `libc6`、`libgcc-s1`、`libstdc++6` 以及上述程序的 `.so`（libblkid、libudev、libpam、libcrypto 等），按发行版路径放在 `lib/`、`lib64/`、`usr/lib/`。
- 构建不联网；`scripts/fetch-initramfs-extras.sh` 可一次性从缓存或开源仓库 drop-in，不绑进 `build.sh`。

