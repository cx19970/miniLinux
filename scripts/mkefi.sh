#!/bin/sh
# Build EFI/BOOT/BOOTX64.EFI with grub-mkimage. Skip if it already exists.
# GRUB_VERSION=grub: no-op (GRUB Legacy is BIOS only).
# Usage: scripts/mkefi.sh [-c|--config FILE]
# Module dir: arch/$ARCH/grub2/x86_64-efi, else /usr/lib/grub/x86_64-efi.

# shellcheck disable=SC2173
trap '' SIGINT

set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
load_image_conf_from_args "$@"

if [ "$GRUB_VERSION" = grub ]; then
    info "GRUB_VERSION=grub: skip UEFI image (GRUB Legacy is BIOS only)"
    exit 0
fi

EFI_OUT="$GRUB2_DIR/EFI/BOOT/BOOTX64.EFI"
mkdir -p "$GRUB2_DIR/EFI/BOOT"

# if [ -f "$EFI_OUT" ]; then
#     info "keep existing $EFI_OUT"
#     exit 0
# fi

need_cmd grub-mkimage
[ -f "$GRUB2_DIR/early-efi.cfg" ] || die "missing $GRUB2_DIR/early-efi.cfg"

MODDIR=""
if [ -d "$GRUB2_DIR/x86_64-efi" ] && ls "$GRUB2_DIR/x86_64-efi"/*.mod >/dev/null 2>&1; then
    MODDIR="$GRUB2_DIR/x86_64-efi"
elif [ -d /usr/lib/grub/x86_64-efi ]; then
    warn "using host GRUB modules /usr/lib/grub/x86_64-efi"
    MODDIR=/usr/lib/grub/x86_64-efi
else
    die "no x86_64-efi modules; drop .mod files into $GRUB2_DIR/x86_64-efi or install grub-efi-amd64-bin"
fi

# Modules embedded into BOOTX64.EFI. Add/remove names here.
# Omit GRUB unit-test modules (*_test, functional_test, videotest, ...).
# Keep test (grub.cfg `test` command).
MODULES="part_msdos part_gpt part_apple part_bsd part_acorn part_amiga"
MODULES="$MODULES part_dfly part_dvh part_plan part_sun part_sunpc msdospart gptsync"
MODULES="$MODULES fat ext2 exfat ntfs ntfscomp iso9660 udf hfs hfsplus hfspluscomp"
MODULES="$MODULES xfs btrfs f2fs jfs reiserfs nilfs2 erofs squash4 romfs sfs"
MODULES="$MODULES minix minix_be minix2 minix2_be minix3 minix3_be ufs1 ufs1_be ufs2"
MODULES="$MODULES affs afs bfs cbfs zfs zfscrypt zfsinfo tar cpio cpio_be newc odc procfs"
MODULES="$MODULES search search_fs_file search_fs_uuid search_label"
MODULES="$MODULES normal boot linux linux16 multiboot multiboot2 configfile"
MODULES="$MODULES echo ls test minicmd cat sleep true eval help hexdump read regexp"
# GRUB2 modules (but less used)
if [ "$EFI_BUILD_MODE" = "full" ]; then
MODULES="$MODULES chain loopback memdisk blocklist probe loadenv syslinuxcfg legacycfg"
MODULES="$MODULES disk diskfilter lvm ldm mdraid09 mdraid09_be mdraid1x"
MODULES="$MODULES raid5rec raid6rec dm_nv scsi ata ahci pata nativedisk offsetio"
MODULES="$MODULES cryptodisk luks luks2 geli afsplitter argon2 pbkdf2 plainmount"
MODULES="$MODULES password password_pbkdf2 pgp pubkey key_protector asn1"
MODULES="$MODULES tpm tpm2_key_protector tss2"
MODULES="$MODULES gcry_arcfour gcry_aria gcry_blake2 gcry_blowfish gcry_camellia"
MODULES="$MODULES gcry_cast5 gcry_crc gcry_des gcry_dsa gcry_gost28147 gcry_gostr3411_94"
MODULES="$MODULES gcry_hwfeatures gcry_idea gcry_kdf gcry_keccak gcry_md4 gcry_md5"
MODULES="$MODULES gcry_rfc2268 gcry_rijndael gcry_rmd160 gcry_rsa gcry_salsa20 gcry_seed"
MODULES="$MODULES gcry_serpent gcry_sha1 gcry_sha256 gcry_sha512 gcry_sm3 gcry_sm4"
MODULES="$MODULES gcry_stribog gcry_tiger gcry_twofish gcry_whirlpool crypto mpi"
MODULES="$MODULES net efinet http tftp"
MODULES="$MODULES usb usb_keyboard usbms ehci ohci uhci"
MODULES="$MODULES usbserial_common usbserial_ftdi usbserial_pl2303 usbserial_usbdebug"
MODULES="$MODULES all_video efi_gop efi_uga efitextmode gfxmenu gfxterm gfxterm_background"
MODULES="$MODULES font bitmap bitmap_scale jpeg png tga video video_fb video_colors"
MODULES="$MODULES video_bochs video_cirrus videoinfo fixvideo"
MODULES="$MODULES serial terminal terminfo at_keyboard keylayouts keystatus"
MODULES="$MODULES efifwsetup smbios lsefi lsefimmap lsefisystab lsacpi lssal lsmmap lspci"
MODULES="$MODULES acpi halt reboot date datehook datetime time play"
MODULES="$MODULES gzio xzio lzopio zstd zstdio bufio fshelp file elf relocator mmap"
MODULES="$MODULES hashsum crc64 adler32 json tr cmp div cpuid iorw memrw"
MODULES="$MODULES hdparm pcidump setpci rdmsr wrmsr backtrace progress gettext"
MODULES="$MODULES archelp extcmd setjmp random priority_queue blsuki bli"
MODULES="$MODULES appleldr aout bsd macho xnu xnu_uuid loadbios macbless"
MODULES="$MODULES cbtable cbls cbmemc cbtime cs5536"
MODULES="$MODULES parttool hello morse spkmodem trig"
fi

# Build EFI/BOOT/BOOTX64.EFI with grub-mkimage.
# MODULES is the list of modules to build the EFI image.
# The modules contained in MODULES will be packaged into EFI.
# The image prefix must match the runtime layout used by early-efi.cfg and the boot partition.
if ! grub-mkimage -O x86_64-efi -d "$MODDIR" -p /grub -c "$GRUB2_DIR/early-efi.cfg" \
    -o "$EFI_OUT" $MODULES; then
    die "grub-mkimage failed (module/host version mismatch?). Place BOOTX64.EFI at $EFI_OUT"
fi

info "wrote $EFI_OUT"
