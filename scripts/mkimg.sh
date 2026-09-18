#!/bin/sh
# Build an MBR dual-partition raw image: ESP (FAT16) + boot (ext2).
# GRUB_VERSION=grub2: BIOS GRUB2 into the MBR/gap + UEFI files on ESP.
# GRUB_VERSION=grub:  GRUB Legacy (BIOS only); do not install GRUB2 or copy EFI/.
#
# Missing bzImage: still write a partitioned image, warn, exit 0
# (so ESP/partition layout can be checked first).
#
# Usage: run on Linux or WSL2:
#   scripts/mkimg.sh
#   scripts/mkimg.sh -c config/defimage.conf
#   scripts/mkimg.sh config/custom.conf
# Default config: config/defimage.conf
# Needs: sfdisk, losetup, mkfs.vfat, mkfs.ext2
#   grub2: grub-mkimage or grub-install --target=i386-pc
#   grub:  host grub-legacy (grub --batch setup); never dd stage1 alone
# Loop-device access requires root or sudo.

set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
load_image_conf_from_args "$@"

need_cmd sfdisk
need_cmd losetup
need_cmd dd

mkfs_fat() {
    if command -v mkfs.vfat >/dev/null 2>&1; then
        sudo_if_needed mkfs.vfat "$@"
    elif command -v mkfs.fat >/dev/null 2>&1; then
        sudo_if_needed mkfs.fat "$@"
    elif [ -x "$INITRAMFS_DIR/bin/busybox" ]; then
        sudo_if_needed "$INITRAMFS_DIR/bin/busybox" mkfs.vfat "$@"
    else
        die "need mkfs.vfat (dosfstools) or $INITRAMFS_DIR/bin/busybox"
    fi
}

mkfs_ext2() {
    if command -v mkfs.ext2 >/dev/null 2>&1; then
        sudo_if_needed mkfs.ext2 "$@"
    elif [ -x "$INITRAMFS_DIR/bin/busybox" ]; then
        sudo_if_needed "$INITRAMFS_DIR/bin/busybox" mkfs.ext2 "$@"
    else
        die "need mkfs.ext2 (e2fsprogs) or $INITRAMFS_DIR/bin/busybox"
    fi
}

GAP_SECTORS=$((GAP_MIB * 1024 * 1024 / 512))
ESP_SECTORS=$((ESP_SIZE_MIB * 1024 * 1024 / 512))
BOOT_SECTORS=$((BOOT_SIZE_MIB * 1024 * 1024 / 512))
TOTAL_BYTES=$(((GAP_MIB + ESP_SIZE_MIB + BOOT_SIZE_MIB) * 1024 * 1024))
ESP_START=$GAP_SECTORS
BOOT_START=$((GAP_SECTORS + ESP_SECTORS))

mkdir -p "$OUT_DIR"
IMG_FINAL="$OUT_DIR/$IMAGE_NAME"
# losetup on WSL drvfs (/mnt/c, /mnt/e, ...) often fails; build on a native fs then copy.
IMG="$IMG_FINAL"
case "$IMG_FINAL" in
    /mnt/[a-z]/*|/mnt/[A-Z]/*)
        IMG=$(mktemp /tmp/minilinux-XXXXXX.img)
        info "work image $IMG (drvfs); copy to $IMG_FINAL when done"
        ;;
esac

# Fill in boot files that can be generated locally
if [ "$GRUB_VERSION" = grub2 ] && [ ! -f "$GRUB2_DIR/EFI/BOOT/BOOTX64.EFI" ]; then
    if [ -x "$SCRIPT_DIR/mkefi.sh" ] || [ -f "$SCRIPT_DIR/mkefi.sh" ]; then
        sh "$SCRIPT_DIR/mkefi.sh" -c "$IMAGE_CONF" || warn "mkefi.sh failed; ESP may lack BOOTX64.EFI"
    fi
fi
if [ ! -f "$INITRAMFS_DIR/initramfs.cpio.gz" ]; then
    sh "$SCRIPT_DIR/mkinitramfs.sh" -c "$IMAGE_CONF" || warn "mkinitramfs.sh failed"
fi

MISSING_KERNEL=0
if [ ! -f "$KERNEL_DIR/bzImage" ]; then
    MISSING_KERNEL=1
    warn "missing $KERNEL_DIR/bzImage — image will be partitioned but cannot boot a kernel"
fi
if [ "$GRUB_VERSION" = grub2 ]; then
    [ -f "$GRUB2_DIR/grub_comp/grub/grub.cfg" ] || die "missing $GRUB2_DIR/grub_comp/grub/grub.cfg"
    if [ ! -f "$GRUB2_DIR/EFI/BOOT/BOOTX64.EFI" ]; then
        warn "missing BOOTX64.EFI — UEFI boot will fail until you run mkefi.sh or drop in the file"
    fi
else
    [ -f "$GRUB1_DIR/grub_comp/grub/grub.conf" ] || die "missing $GRUB1_DIR/grub_comp/grub/grub.conf"
    if [ ! -f "$GRUB1_DIR/stage2" ]; then
        warn "missing $GRUB1_DIR/stage2 — drop in GRUB1 stage files"
    fi
fi
if [ ! -f "$INITRAMFS_DIR/initramfs.cpio.gz" ]; then
    warn "missing initramfs.cpio.gz — GRUB initrd path will be missing"
fi

NEED=0
if [ -f "$KERNEL_DIR/bzImage" ]; then
    NEED=$((NEED + $(wc -c < "$KERNEL_DIR/bzImage" | tr -d ' ')))
fi
if [ -f "$INITRAMFS_DIR/initramfs.cpio.gz" ]; then
    NEED=$((NEED + $(wc -c < "$INITRAMFS_DIR/initramfs.cpio.gz" | tr -d ' ')))
fi
# Leave room for /grub, ext2 metadata, and 5% reserved blocks.
AVAIL=$((BOOT_SIZE_MIB * 1024 * 1024 * 85 / 100))
if [ "$NEED" -gt "$AVAIL" ]; then
    die "boot payload ${NEED}B does not fit ${BOOT_SIZE_MIB}MiB partition (increase BOOT_SIZE_MIB)"
fi

ESP_MNT=""
BOOT_MNT=""
LOOP=""
EXTRA_LOOPS=""
USE_LOOP=0

cleanup() {
    st=$?
    if [ "${USE_LOOP:-0}" = 1 ]; then
        if [ -n "${ESP_MNT:-}" ]; then
            sudo_if_needed umount "$ESP_MNT" 2>/dev/null || true
        fi
        if [ -n "${BOOT_MNT:-}" ]; then
            sudo_if_needed umount "$BOOT_MNT" 2>/dev/null || true
        fi
        for d in ${EXTRA_LOOPS:-}; do
            sudo_if_needed losetup -d "$d" 2>/dev/null || true
        done
        if [ -n "${LOOP:-}" ]; then
            sudo_if_needed losetup -d "$LOOP" 2>/dev/null || true
        fi
        [ -n "${ESP_MNT:-}" ] && rmdir "$ESP_MNT" 2>/dev/null || true
        [ -n "${BOOT_MNT:-}" ] && rmdir "$BOOT_MNT" 2>/dev/null || true
    else
        [ -n "${BOOT_MNT:-}" ] && rm -rf "$BOOT_MNT" 2>/dev/null || true
        [ -n "${ESP_SLICE:-}" ] && rm -f "$ESP_SLICE" 2>/dev/null || true
        [ -n "${BOOT_SLICE:-}" ] && rm -f "$BOOT_SLICE" 2>/dev/null || true
    fi
    return $st
}
trap cleanup EXIT INT TERM

rm -f "$IMG"
if command -v truncate >/dev/null 2>&1; then
    truncate -s "$TOTAL_BYTES" "$IMG"
else
    dd if=/dev/zero of="$IMG" bs=1048576 count=$((GAP_MIB + ESP_SIZE_MIB + BOOT_SIZE_MIB)) status=none
fi

info "partition $IMG (MBR, ${ESP_SIZE_MIB}MiB ESP + ${BOOT_SIZE_MIB}MiB boot)"
sfdisk --no-reread "$IMG" >/dev/null <<EOF
label: dos
unit: sectors
start=$ESP_START, size=$ESP_SECTORS, type=$ESP_TYPE, bootable
start=$BOOT_START, size=$BOOT_SECTORS, type=$BOOT_TYPE
EOF

have_loop() {
    [ -e /dev/loop-control ] || [ -b /dev/loop0 ]
}

stage_boot_tree() {
    dest="$1"
    rm -rf "$dest"
    mkdir -p "$dest"
    copy() { cp -a "$@"; }

    if [ -f "$KERNEL_DIR/bzImage" ]; then
        copy "$KERNEL_DIR/bzImage" "$dest/bzImage"
    fi
    if [ -f "$INITRAMFS_DIR/initramfs.cpio.gz" ]; then
        copy "$INITRAMFS_DIR/initramfs.cpio.gz" "$dest/initramfs.cpio.gz"
    fi
    if [ "$GRUB_VERSION" = grub2 ]; then
        mkdir -p "$dest/grub/i386-pc"
        if [ -d "$GRUB2_DIR/grub_comp" ]; then
            for d in grub EFI loader; do
                if [ -d "$GRUB2_DIR/grub_comp/$d" ]; then
                    mkdir -p "$dest/$d"
                    copy "$GRUB2_DIR/grub_comp/$d/." "$dest/$d/"
                fi
            done
        fi
        if ls "$GRUB2_DIR/i386-pc"/*.mod >/dev/null 2>&1; then
            copy "$GRUB2_DIR/i386-pc/." "$dest/grub/i386-pc/"
        fi
    else
        mkdir -p "$dest/grub"
        if [ -d "$GRUB1_DIR/grub_comp/grub" ]; then
            copy "$GRUB1_DIR/grub_comp/grub/." "$dest/grub/"
        fi
        for f in stage1 stage2; do
            if [ -f "$GRUB1_DIR/$f" ]; then
                copy "$GRUB1_DIR/$f" "$dest/grub/$f"
            else
                warn "missing $GRUB1_DIR/$f"
            fi
        done
        copied15=0
        for f in "$GRUB1_DIR/"*_stage1_5; do
            [ -f "$f" ] || continue
            copy "$f" "$dest/grub/"
            copied15=1
        done
        if [ "$copied15" -eq 0 ]; then
            warn "missing $GRUB1_DIR/*_stage1_5"
        fi
    fi
    find "$dest" -name .gitkeep -delete 2>/dev/null || true
}

ext2_fill() {
    slice="$1"
    tree="$2"
    cmds=$(mktemp /tmp/minilinux-debugfs.XXXXXX)
    (
        cd "$tree"
        find . -type d | sort | while read -r d; do
            [ "$d" = . ] && continue
            printf 'mkdir %s\n' "${d#.}"
        done
        find . -type f | sort | while read -r f; do
            printf 'write %s %s\n' "$(pwd)/${f#./}" "${f#.}"
        done
    ) > "$cmds"
    debugfs -w -f "$cmds" "$slice" >/dev/null
    rm -f "$cmds"
}

populate_without_loop() {
    need_cmd debugfs
    ESP_SLICE=$(mktemp /tmp/minilinux-esp-XXXXXX.img)
    BOOT_SLICE=$(mktemp /tmp/minilinux-boot-XXXXXX.img)
    BOOT_MNT=$(mktemp -d /tmp/minilinux-boot.XXXXXX)

    dd if="$IMG" of="$ESP_SLICE" bs=512 skip="$ESP_START" count="$ESP_SECTORS" status=none
    dd if="$IMG" of="$BOOT_SLICE" bs=512 skip="$BOOT_START" count="$BOOT_SECTORS" status=none

    info "format ESP FAT16 label=$ESP_LABEL (file)"
    if ! mkfs_fat -F 16 -n "$ESP_LABEL" "$ESP_SLICE"; then
        warn "mkfs FAT16 failed, retry cluster size 1"
        mkfs_fat -F 16 -s 1 -n "$ESP_LABEL" "$ESP_SLICE"
    fi
    info "format boot ext2 label=$BOOT_LABEL (file)"
    mkfs_ext2 -F -L "$BOOT_LABEL" -b 1024 "$BOOT_SLICE" >/dev/null

    if [ "$GRUB_VERSION" = grub2 ]; then
        if command -v mcopy >/dev/null 2>&1 && [ -d "$GRUB2_DIR/EFI" ]; then
            mcopy -i "$ESP_SLICE" -s "$GRUB2_DIR/EFI" :: || warn "mcopy EFI to ESP failed"
        else
            warn "no loop and no mcopy; ESP formatted but EFI files not copied"
        fi
    else
        info "GRUB_VERSION=grub: leave ESP empty (BIOS only)"
    fi

    info "copy boot files via debugfs"
    stage_boot_tree "$BOOT_MNT"
    apply_tree_permissions "$BOOT_MNT"
    ext2_fill "$BOOT_SLICE" "$BOOT_MNT"

    dd if="$ESP_SLICE" of="$IMG" bs=512 seek="$ESP_START" conv=notrunc status=none
    dd if="$BOOT_SLICE" of="$IMG" bs=512 seek="$BOOT_START" conv=notrunc status=none
    rm -f "$ESP_SLICE" "$BOOT_SLICE"
    ESP_SLICE=""
    BOOT_SLICE=""
}

if have_loop; then
    LOOP=$(sudo_if_needed losetup --show -P -f "$IMG") || LOOP=""
fi
if [ -n "${LOOP:-}" ]; then
    USE_LOOP=1
    info "loop $LOOP"

    P1=""
    P2=""
    i=0
    while [ "$i" -lt 8 ]; do
        if [ -b "${LOOP}p1" ] && [ -b "${LOOP}p2" ]; then
            P1="${LOOP}p1"
            P2="${LOOP}p2"
            break
        fi
        i=$((i + 1))
        sleep 1
    done
    if [ -z "$P1" ]; then
        P1=$(sudo_if_needed losetup --show -f -o $((ESP_START * 512)) --sizelimit $((ESP_SECTORS * 512)) "$IMG")
        P2=$(sudo_if_needed losetup --show -f -o $((BOOT_START * 512)) --sizelimit $((BOOT_SECTORS * 512)) "$IMG")
        EXTRA_LOOPS="$P1 $P2"
    fi
    [ -n "$P1" ] && [ -n "$P2" ] || die "could not map partitions on $LOOP"

    info "format ESP FAT16 label=$ESP_LABEL"
    if ! mkfs_fat -F 16 -n "$ESP_LABEL" "$P1"; then
        warn "mkfs FAT16 failed, retry cluster size 1"
        mkfs_fat -F 16 -s 1 -n "$ESP_LABEL" "$P1"
    fi
    info "format boot ext2 label=$BOOT_LABEL"
    mkfs_ext2 -F -L "$BOOT_LABEL" -b 1024 "$P2" >/dev/null

    ESP_MNT=$(mktemp -d /tmp/minilinux-esp.XXXXXX)
    BOOT_MNT=$(mktemp -d /tmp/minilinux-boot.XXXXXX)
    sudo_if_needed mount -o uid=$(id -u),gid=$(id -g) "$P1" "$ESP_MNT" 2>/dev/null \
        || sudo_if_needed mount "$P1" "$ESP_MNT"
    sudo_if_needed mount "$P2" "$BOOT_MNT"
    copy() { sudo_if_needed cp -a "$@"; }

    if [ "$GRUB_VERSION" = grub2 ]; then
        if [ -d "$GRUB2_DIR/EFI" ]; then
            copy "$GRUB2_DIR/EFI" "$ESP_MNT/"
            sudo_if_needed find "$ESP_MNT" -name .gitkeep -delete 2>/dev/null || true
        else
            warn "missing $GRUB2_DIR/EFI; ESP will have no UEFI payload"
        fi
    else
        info "GRUB_VERSION=grub: leave ESP empty (BIOS only)"
    fi

    if [ -f "$KERNEL_DIR/bzImage" ]; then
        copy "$KERNEL_DIR/bzImage" "$BOOT_MNT/bzImage"
    fi
    if [ -f "$INITRAMFS_DIR/initramfs.cpio.gz" ]; then
        copy "$INITRAMFS_DIR/initramfs.cpio.gz" "$BOOT_MNT/initramfs.cpio.gz"
    fi
    if [ "$GRUB_VERSION" = grub2 ]; then
        sudo_if_needed mkdir -p "$BOOT_MNT/grub/i386-pc"
        if [ -d "$GRUB2_DIR/grub_comp" ]; then
            for d in grub EFI loader; do
                if [ -d "$GRUB2_DIR/grub_comp/$d" ]; then
                    sudo_if_needed mkdir -p "$BOOT_MNT/$d"
                    copy "$GRUB2_DIR/grub_comp/$d/." "$BOOT_MNT/$d/"
                fi
            done
            if [ -d "$GRUB2_DIR/grub_comp/EFI" ]; then
                copy "$GRUB2_DIR/grub_comp/EFI" "$ESP_MNT/"
            fi
        fi
        if ls "$GRUB2_DIR/i386-pc"/*.mod >/dev/null 2>&1; then
            copy "$GRUB2_DIR/i386-pc/." "$BOOT_MNT/grub/i386-pc/"
        fi
    else
        sudo_if_needed mkdir -p "$BOOT_MNT/grub"
        if [ -d "$GRUB1_DIR/grub_comp/grub" ]; then
            copy "$GRUB1_DIR/grub_comp/grub/." "$BOOT_MNT/grub/"
        fi
        for f in stage1 stage2; do
            if [ -f "$GRUB1_DIR/$f" ]; then
                copy "$GRUB1_DIR/$f" "$BOOT_MNT/grub/$f"
            else
                warn "missing $GRUB1_DIR/$f"
            fi
        done
        copied15=0
        for f in "$GRUB1_DIR/"*_stage1_5; do
            [ -f "$f" ] || continue
            copy "$f" "$BOOT_MNT/grub/"
            copied15=1
        done
        if [ "$copied15" -eq 0 ]; then
            warn "missing $GRUB1_DIR/*_stage1_5"
        fi
    fi
    sudo_if_needed find "$BOOT_MNT" -name .gitkeep -delete 2>/dev/null || true
else
    info "no loop device; format slices + debugfs (WSL1 / no losetup)"
    populate_without_loop
fi

# True if this grub-install is GRUB2 (has --target).
grub_install_is_grub2() {
    command -v grub-install >/dev/null 2>&1 || return 1
    grub-install --help 2>&1 | grep -q -- '--target'
}

# GRUB2 reports "2.x"; GRUB Legacy reports 0.97.
host_grub_is_legacy() {
    bin="$1"
    [ -x "$bin" ] || return 1
    ver=$("$bin" --version 2>&1 || true)
    case "$ver" in
        *2.[0-9]*) return 1 ;;
    esac
    return 0
}

find_grub1_shell() {
    for c in grub grub-legacy; do
        if command -v "$c" >/dev/null 2>&1; then
            b=$(command -v "$c")
            if host_grub_is_legacy "$b"; then
                printf '%s\n' "$b"
                return 0
            fi
        fi
    done
    if command -v grub-install >/dev/null 2>&1 && ! grub_install_is_grub2; then
        d=$(dirname "$(command -v grub-install)")
        if host_grub_is_legacy "$d/grub"; then
            printf '%s\n' "$d/grub"
            return 0
        fi
    fi
    return 1
}

install_grub1_bios() {
    if [ ! -f "$BOOT_MNT/grub/stage1" ] || [ ! -f "$BOOT_MNT/grub/stage2" ]; then
        warn "GRUB1 stage1/stage2 not on boot partition; skip MBR install"
        return 1
    fi
    if [ ! -f "$BOOT_MNT/grub/e2fs_stage1_5" ]; then
        warn "missing e2fs_stage1_5; ext2 boot partition may not be readable by GRUB1"
    fi

    shell=$(find_grub1_shell || true)
    if [ -z "$shell" ]; then
        warn "no grub-legacy on host; not writing stage1 with dd (would omit stage2 LBA)"
        return 1
    fi

    # Boot is the second MBR partition: GRUB Legacy numbers it (hd0,1).
    info "install GRUB1 via $shell (root (hd0,1); setup --prefix=/grub (hd0))"
    if sudo_if_needed "$shell" --batch --no-floppy --device-map=/dev/null <<EOF
device (hd0) ${LOOP:-$IMG}
root (hd0,1)
setup --force-lba --prefix=/grub (hd0)
quit
EOF
    then
        info "BIOS GRUB1 installed via grub-legacy"
        return 0
    fi
    warn "grub-legacy setup failed"
    return 1
}

install_grub2_bios() {
    moddir=""
    if ls "$GRUB2_DIR/i386-pc"/*.mod >/dev/null 2>&1; then
        moddir="$GRUB2_DIR/i386-pc"
    elif [ -d /usr/lib/grub/i386-pc ]; then
        moddir=/usr/lib/grub/i386-pc
        warn "using host i386-pc modules $moddir"
    else
        warn "no i386-pc GRUB modules; skip BIOS install"
        return 1
    fi

    boot_img="$moddir/boot.img"
    if command -v grub-install >/dev/null 2>&1; then
        if sudo_if_needed grub-install --target=i386-pc \
            --boot-directory="$BOOT_MNT" \
            --directory="$moddir" \
            --modules="biosdisk part_msdos ext2 fat" \
            "${LOOP:-$IMG}"; then
            info "BIOS GRUB2 installed via grub-install"
            return 0
        fi
        warn "grub-install failed, trying boot.img + core.img"
    fi

    if ! command -v grub-mkimage >/dev/null 2>&1; then
        warn "grub-mkimage not found; BIOS GRUB2 not installed"
        return 1
    fi
    [ -f "$boot_img" ] || { warn "missing $boot_img"; return 1; }
    [ -f "$GRUB2_DIR/early-efi.cfg" ] || { warn "missing early-efi.cfg"; return 1; }

    core="$OUT_DIR/cache/core.img"
    mkdir -p "$OUT_DIR/cache"
    MODULES="biosdisk part_msdos fat ext2 search search_fs_file search_fs_uuid search_label"
    MODULES="$MODULES normal boot linux configfile echo ls test minicmd cat sleep"
    grub-mkimage -O i386-pc -d "$moddir" -p /grub -c "$GRUB2_DIR/early-efi.cfg" -o "$core" $MODULES

    core_bytes=$(wc -c < "$core")
    max=$(((GAP_SECTORS - 1) * 512))
    # wc may pad with spaces
    core_bytes=$(echo "$core_bytes" | tr -d ' ')
    [ "$core_bytes" -le "$max" ] || die "core.img (${core_bytes}B) exceeds gap (${max}B)"

    # Write only the first 440 bytes of the MBR; keep the partition table and 55AA.
    # Prefer the loop device when attached.
    target="$LOOP"
    [ -n "$target" ] || target="$IMG"
    sudo_if_needed dd if="$boot_img" of="$target" bs=440 count=1 conv=notrunc status=none
    sudo_if_needed dd if="$core" of="$target" bs=512 seek=1 conv=notrunc status=none
    info "BIOS GRUB2 installed via boot.img + core.img"
    return 0
}

if [ "$GRUB_VERSION" = grub2 ]; then
    install_grub2_bios || warn "Legacy BIOS GRUB2 not installed; UEFI may still work"
else
    install_grub1_bios || warn "Legacy BIOS GRUB1 not installed (need host grub-legacy); image files still written"
fi

if [ "$USE_LOOP" = 1 ]; then
    apply_tree_permissions "$BOOT_MNT"
    apply_tree_permissions "$ESP_MNT"
    sudo_if_needed umount "$ESP_MNT" 2>/dev/null || true
    sudo_if_needed umount "$BOOT_MNT" 2>/dev/null || true
    ESP_MNT=""
    BOOT_MNT=""
    if [ -n "${LOOP:-}" ]; then
        sudo_if_needed losetup -d "$LOOP" 2>/dev/null || true
        LOOP=""
    fi
    for d in ${EXTRA_LOOPS:-}; do
        sudo_if_needed losetup -d "$d" 2>/dev/null || true
    done
    EXTRA_LOOPS=""
else
    rm -rf "$BOOT_MNT" 2>/dev/null || true
    BOOT_MNT=""
fi

if [ "$IMG" != "$IMG_FINAL" ]; then
    cp -f "$IMG" "$IMG_FINAL"
    rm -f "$IMG"
    IMG="$IMG_FINAL"
fi

info "wrote $IMG (${GAP_MIB}+${ESP_SIZE_MIB}+${BOOT_SIZE_MIB} MiB)"
if [ "$MISSING_KERNEL" -eq 1 ]; then
    warn "done with missing bzImage (exit 0); place kernel and re-run mkimg.sh to boot"
fi
exit 0
