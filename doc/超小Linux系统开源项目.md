## 一、超小的完整 linux 系统开源项目
- 1、Tiny Core Linux
- 2、mylinux-minimal
- 3、TeenyLinux
- 4、SliTaz GNU/Linux
- 5、Dumpster OS
- 6、Damn Small Linux
- 7、Alpine Linux
- 8、Porteus
- 9、antiX
- 10、Buildroot
- 11、Yocto Project

## 二、开源 linux 系统项目兼容性
- 第一梯队：构建工具 Buildroot、Yocto Project，定制化拉满，可以从源码自由配置内核、引导程序、固件支持，是唯一能覆盖全内核版本要求的方案。
- 第二梯队：现成发行版 Alpine Linux、Tiny Core Linux，开箱即用。
- 第三梯队：轻量发行版 SliTaz GNU/Linux、Damn Small Linux、Dumpster OS，有明显短板。

## 三、根文件系统选型

### 1、ext2

| 维度 | 兼容情况 | 说明 |
| --- | --- | --- |
| 内核版本 | Linux 2.0 ~ 7.x 全系列原生支持 | 从 Linux 最早的稳定版开始就是内核核心组件，2.4、2.6、3.x、4.x、5.x、6.x、7.x 均无需任何补丁直接支持 |
| GRUB Legacy | 官方原生完美支持 | 是老版 GRUB（0.9x）最稳定、最兼容的根文件系统，无任何坑 |
| GRUB2 | 原生完整支持 | 所有版本 GRUB2 均可直接读取和引导 ext2 分区 |
| u-boot | 全版本原生支持 | u-boot 从很早版本就支持 ext2，是嵌入式场景的通用标准 |
| 固件模式 | Legacy BIOS / UEFI /u-boot 全兼容 | 固件只负责加载引导程序，文件系统由引导程序解析，ext2 在所有引导程序下都可用 |
| 运行环境 | 全虚拟机 + 物理机 | VMware/VirtualBox/KVM/QEMU、物理硬盘 / U 盘 / CF 卡均完美兼容 |

- **优点**：元数据开销极小、结构简单、全平台全版本无兼容死角。
- **缺点**：无日志功能，意外掉电可能出现文件系统损坏。

### 2、fatfs

| 兼容维度 | FAT12/FAT16/FAT32 支持情况 | 说明 |
| --- | --- | --- |
| 内核版本 | Linux 1.x ~ 7.x 全系列原生支持 | FAT12/16 从 Linux 诞生之初就有 msdos 驱动；FAT32（带长文件名的 vfat 驱动）从 2.0 内核开始原生支持，2.4/2.6 之后完全稳定，覆盖 2.x~7.x 全版本 |
| GRUB Legacy | 原生完美支持 | 是老版 GRUB 0.9x 最稳定兼容的文件系统之一 |
| GRUB2 | 原生完整支持 | 全版本 GRUB2 均可直接读取 FAT 分区 |
| u-boot | 全版本原生支持 | 嵌入式场景的通用标准，常用 FAT 分区存放内核、设备树镜像 |
| 固件模式 | Legacy BIOS + UEFI 全兼容 | UEFI 规范**强制要求** ESP 引导分区必须使用 FAT32 |
| 运行环境 | 全虚拟机 + 物理机 | VMware/VirtualBox/KVM/QEMU、物理硬盘 / U 盘 / SD 卡均无压力 |

- **优点**：FAT/FAT32 在「引导识别、内核驱动」层面的兼容性确实拉满，甚至比 ext2 还广。
- **缺点**：FAT 没有文件属主（uid/gid）、没有 rwx 权限位，不支持符号链接、硬链接，文件名**不区分大小写**。

## 四、社区 Linux 发行版启动分区的文件系统

### 1、主流桌面 / 服务器发行版

| 发行版 | BIOS 模式下单独 /boot 默认格式 | UEFI 模式下单独 /boot 默认格式 | 是否默认单独划分 /boot | 备注 |
| --- | --- | --- | --- | --- |
| Ubuntu | 根分区继承（默认 ext4） | 根分区继承（默认 ext4） | 否，默认放在根分区 | 仅全盘加密、LVM 等特殊场景才推荐单独分区，格式推荐 ext4 |
| Debian | ext2（传统推荐）/ext4（新版） | ext4 | 否，默认放在根分区 | 老旧版本默认单独分区用 ext2，Debian 10+ 不再默认单独划分 |
| Fedora | ext4 | ext4 | 是，默认单独划分 | 根分区默认用 Btrfs，但 /boot 独立为 ext4，确保引导兼容性 |
| RHEL / CentOS 7+ | ext4 | ext4 | 是，默认单独划分 | CentOS 6 及更早版本为 ext3 |
| Arch Linux | 根分区继承（用户自选，通常 ext4/Btrfs） | 根分区继承（用户自选） | 否，无默认单独分区 | 手动单独分区推荐 ext2 或 ext4；systemd-boot 仅支持 FAT/ext4 |
| openSUSE | 根分区继承（默认 Btrfs） | 根分区继承（默认 Btrfs） | 否，默认放在根分区 | GRUB2 原生支持 Btrfs 引导，无需单独分区 |
| 银河麒麟 V10 | 根分区继承（ext4） | 根分区继承（ext4） | 否，默认放在根分区 | 遵循 UEFI 规范，ESP 分区为 FAT32 |

### 2、轻量 / 极简 / 嵌入式发行版

| 发行版 | BIOS 模式下 /boot 默认格式 | UEFI 模式下 /boot 默认格式 | 是否默认单独划分 /boot | 备注 |
| --- | --- | --- | --- | --- |
| Alpine Linux | ext2 /ext4（Extlinux 引导）；Live 模式为 FAT32 | ext4 | 安装脚本默认分 boot 分区 | BIOS 下 Syslinux 推荐 FAT 或 ext2；硬盘安装默认 ext4Alpine Lin... |
| Tiny Core Linux | FAT16/32 或 ext2 | FAT32 或 ext2 | 是，默认单独 boot 分区 | 基于 Syslinux 引导，对 FAT 兼容性最佳，也支持 ext2 |
| SliTaz GNU/Linux | 根分区继承（默认 ext3） | 无官方 UEFI 支持 | 否，放在根分区 | 硬盘安装默认格式化根分区为 ext3，/boot 同在其中SliTaz Doc |
| Damn Small Linux（经典版） | 根分区继承（ext2） | 不支持 UEFI | 否，放在根分区 | 基于 GRUB Legacy，原生仅支持 ext2/FAT |
| Porteus | FAT 或 ext2 | FAT32 | 是，单独 boot 分区 | Live 模块化系统，系统主体为 squashfs 压缩镜像 |
| antiX | 根分区继承（ext4） | ext4 | 否，默认放在根分区 | 基于 Debian，无 systemd，引导兼容老硬件 |
| Buildroot | 可自定义（默认 ext2/ext4） | 可自定义（ext2/ext4） | 可自定义 | 完全可配置，支持 FAT、ext2、ext4、squashfs 等所有格式 |
| Yocto Project | 可自定义（常用 ext4/squashfs） | 可自定义 | 可自定义 | 工业级嵌入式，根据 BSP 配置，常用 ext4 或只读 squashfs |
| Dumpster OS | 根分区继承（ext4） | 根分区继承（ext4） | 否，放在根分区 | 基于 GRUB2，极简构建，根分区为 ext4 |
| TeenyLinux | ext2 | ext2 | 是，独立内核与 boot | 基于 musl，引导程序支持 ext2/FAT |
