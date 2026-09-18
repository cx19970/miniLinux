## 技术说明

**Legacy BIOS** 只保证：读磁盘 LBA 0 的 512 字节并跳到 `0x7C00`。不知道分区里有没有配置文件，也不认识 `.cfg`。

**UEFI** 只保证：
- 有 ESP，且为 FAT12/16/32。
- 启动项是 **`.efi` 可执行文件**。
- 可移动介质默认路径：`\EFI\BOOT\BOOTX64.EFI`（32 位是 `BOOTIA32.EFI`）。

规范到 `.efi` 为止。固件**不会**去读 `grub.cfg`。读配置的是已经跑起来的 GRUB。

所以：`/grub/grub.conf` vs `/grub/grub.cfg` vs `/EFI/BOOT/grub.cfg` vs `/grub/menu.lst` vs `/loader/loader.conf` 都不是「规范强制允许/禁止」的条目，而是 **GRUB 加载器自己去哪找文本配置**。放在 FAT 上合法，放在 ext2 上也合法，只要 GRUB 能读那个文件系统。

GRUB Legacy（GRUB1，0.9x）还是 GRUB2（1.99/2.xx），取决于镜像里装哪套二进制，与设备、厂商无关。

## 项目落地实情

GRUB2 用 `.mod` + `grub.cfg` + `grub-mkimage`。  
GRUB1 是另一套东西：`stage1` / `stage1.5` / `stage2`，配置是 `menu.lst` 或 `grub.conf`，**没有** `i386-pc/*.mod` 这种树。

本仓库用 `config/defimage.conf` 里的 `GRUB_VERSION` 二选一，**一张镜像只装一代**：

- `grub`：`arch/amd64/grub/`，GRUB Legacy 0.97，**仅 BIOS**。不生成、不安装 UEFI；ESP 可为空。
- `grub2`：`arch/amd64/grub2/`，现有流程（`i386-pc` MBR + 整棵 `EFI/` 拷 ESP）。`mkefi.sh` 生成 `BOOTX64.EFI`。

不做「BIOS 用 GRUB1、UEFI 用 GRUB2」混装。分区布局不变（MBR 双分区、ESP 仍格式化）。

GRUB1 源文件在 `arch/amd64/grub/grub_comp/grub/`；封包到 boot 分区后仍是真实菜单 `/grub/grub.conf`，`/grub/menu.lst` 和 `/grub/grub.cfg` 内容相同，都是 GRUB1 兼容入口（`title` + `configfile /grub/grub.conf`），不是给 GRUB2 用的。另有 `stage2` 以及完整 10 个 `*_stage1_5`（e2fs/fat/ffs/iso9660/jfs/minix/reiserfs/ufs2/vstafs/xfs）。boot 为 ext2，`setup` 必须能找到 `e2fs_stage1_5`。内核仍在分区根 `/bzImage`、`/initramfs.cpio.gz`。MBR 安装依赖宿主机 **grub-legacy** 的 `grub`（`root (hd0,1)` + `setup --prefix=/grub (hd0)`），不能对 loop 跑 GRUB2 的 `grub-install --target=i386-pc`，也不能只 `dd stage1` 而不嵌入 stage2 的 LBA。

stage 二进制上游为 GNU GRUB 0.97，当前来自 CentOS 6.10 的 `grub-0.97`（不在本仓库编译）。`arch/amd64/grub2/` 的模块与 `grub_comp/grub/grub.cfg` 保持不动。
