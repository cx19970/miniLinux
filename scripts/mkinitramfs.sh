#!/bin/sh
# Pack arch/$ARCH/initramfs into initramfs.cpio.gz
# Usage: scripts/mkinitramfs.sh [-c|--config FILE]

# shellcheck disable=SC2173
trap '' SIGINT

set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
load_image_conf_from_args "$@"

need_cmd find

SRC="$INITRAMFS_DIR"
[ -f "$SRC/init" ] || die "missing $SRC/init"

OUT_CPIO="$INITRAMFS_DIR/initramfs.cpio.gz"
mkdir -p "$OUT_DIR"

STAGE=$(mktemp -d /tmp/minilinux-initramfs.XXXXXX)
cleanup_stage() {
    rm -rf "$STAGE"
}
trap cleanup_stage EXIT INT TERM

# Staging copy so busybox --install does not pollute the source tree.
cp -a "$SRC/." "$STAGE/"
rm -f "$STAGE/README.txt" "$STAGE/initramfs.cpio.gz"
find "$STAGE" -name .gitkeep -delete
mkdir -p "$STAGE/bin" "$STAGE/sbin" "$STAGE/usr/bin" "$STAGE/usr/sbin" \
    "$STAGE/dev" "$STAGE/proc" "$STAGE/sys" "$STAGE/boot" "$STAGE/mnt" \
    "$STAGE/tmp" "$STAGE/etc" "$STAGE/root"

if [ -x "$STAGE/bin/busybox" ]; then
    BB_ABS=$(CDPATH= cd -- "$STAGE/bin" && pwd)/busybox
    # --install DIR dumps every applet into DIR. Use --list-full for FHS
    # paths, and skip names already occupied by real extras (wget, kmod, ...).
    "$BB_ABS" --list-full | while read -r rel; do
        [ -n "$rel" ] || continue
        case "$rel" in
            /*) rel=${rel#/} ;;
        esac
        dest="$STAGE/$rel"
        if [ -e "$dest" ] || [ -L "$dest" ]; then
            continue
        fi
        mkdir -p "$(dirname "$dest")"
        case "$rel" in
            bin/*) ln -sf busybox "$dest" ;;
            sbin/*) ln -sf ../bin/busybox "$dest" ;;
            usr/bin/*|usr/sbin/*) ln -sf ../../bin/busybox "$dest" ;;
            *) ln -sf bin/busybox "$dest" ;;
        esac
    done || warn "busybox applet links failed; init will call busybox directly"
    ln -sf busybox "$STAGE/bin/sh" 2>/dev/null || true
else
    warn "busybox missing at $SRC/bin/busybox"
fi

if command -v mknod >/dev/null 2>&1; then
    [ -e "$STAGE/dev/console" ] || mknod -m 622 "$STAGE/dev/console" c 5 1 2>/dev/null || \
        warn "cannot mknod console (need root?); continuing"
    [ -e "$STAGE/dev/null" ] || mknod -m 666 "$STAGE/dev/null" c 1 3 2>/dev/null || true
fi

apply_tree_permissions "$STAGE"

gzip_cmd() {
    if command -v gzip >/dev/null 2>&1; then
        gzip -9
    elif [ -x "$STAGE/bin/busybox" ]; then
        "$STAGE/bin/busybox" gzip -9
    else
        die "need gzip"
    fi
}

(
    cd "$STAGE"
    if command -v cpio >/dev/null 2>&1; then
        find . -print0 | cpio --null --create --format=newc --owner=0:0 2>/dev/null \
            || find . | cpio -o -H newc
    elif [ -x ./bin/busybox ]; then
        find . | ./bin/busybox cpio -o -H newc
    else
        die "need cpio"
    fi
) | gzip_cmd > "$OUT_CPIO"

[ -s "$OUT_CPIO" ] || die "empty initramfs archive"
cp -f "$OUT_CPIO" "$OUT_DIR/initramfs.cpio.gz"
info "wrote $OUT_CPIO"
info "copied $OUT_DIR/initramfs.cpio.gz"
