根文件系统兼容性推荐：FAT、ext2。

Linux文件系统兼容性推荐：ext2、FAT。

UEFI 强制要求 ESP 分区是 FAT32 格式。

下图是一块 GPT 分区表的磁盘，从左到右为磁盘 LBA 扇区递增方向，同时支持两种启动模式，Legacy 引导仅使用左侧的「保护性 MBR + BIOS boot 分区」，完全不触碰 ESP 分区。
```mermaid
graph LR
    A[LBA 0<br>保护性 MBR<br>512 字节<br>存放 GRUB stage1] --> B[BIOS boot 分区<br>1 MB<br>无文件系统<br>存放 GRUB core.img]
    B --> C[ESP 分区<br>32 MB<br>FAT16/FAT32<br>仅 UEFI 模式使用]
    C --> D["/boot 分区<br>16~32 MB<br>ext2<br>内核 + initramfs + grub.cfg"]
    D --> E["根分区 /<br>剩余空间<br>ext4<br>完整系统文件"]
    E --> F[磁盘末尾<br>GPT 分区表 + 备份表头]
```
- Legacy 模式引导只依赖 **前两个区域**，ESP 分区对 Legacy 完全不可见、也不参与引导。
- UEFI 模式引导只依赖 **ESP 分区**，保护性 MBR 和 BIOS boot 分区完全不参与。
- `/boot` 和根分区是两种模式共用的系统核心。

