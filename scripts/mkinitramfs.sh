#!/bin/sh
# Pack arch/$ARCH/initramfs into initramfs.cpio.gz
# Usage: scripts/mkinitramfs.sh [-c|--config FILE]

# shellcheck disable=SC2173
trap '' SIGINT

set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
load_image_conf_from_args "$@"

need_cmd find
need_cmd cpio
need_cmd gzip
need_cmd mknod

SRC="$INITRAMFS_DIR"
[ -f "$SRC/init" ] || die "missing $SRC/init"

OUT_CPIO="$INITRAMFS_DIR/initramfs.cpio.gz"
mkdir -p "$OUT_DIR"

STAGE=$(mktemp -d /tmp/minilinux-initramfs.XXXXXX)
cleanup_stage() {
    rm -rf "$STAGE"
}
trap cleanup_stage EXIT INT TERM

# Staging copy so pack-time mknod/dev nodes and mode fixes do not pollute
# the source tree, and README.txt / stale archives stay out of the image.
cp -arf "$SRC/." "$STAGE/"
rm -f "$STAGE/README.txt" "$STAGE/initramfs.cpio.gz"
find "$STAGE" -name .gitkeep -delete
find "$STAGE" -name .gitignore -delete
mkdir -p "$STAGE/bin" "$STAGE/sbin" "$STAGE/usr/bin" "$STAGE/usr/sbin" \
    "$STAGE/dev" "$STAGE/proc" "$STAGE/sys" "$STAGE/boot" "$STAGE/mnt" \
    "$STAGE/tmp" "$STAGE/etc" "$STAGE/root"

# No busybox execution during packing. The applet links (and /bin/sh) are
# built by /init at boot instead: this script may run on a host that cannot
# execute the target-arch busybox (cross-compile), and a missing/wrong-arch
# binary here would break the build silently.
[ -f "$STAGE/bin/busybox" ] || warn "busybox missing at $SRC/bin/busybox"

[ -e "$STAGE/dev/console" ] || mknod -m 622 "$STAGE/dev/console" c 5 1 2>/dev/null || \
    warn "cannot mknod console (need root?); continuing"
[ -e "$STAGE/dev/null" ] || mknod -m 666 "$STAGE/dev/null" c 1 3 2>/dev/null || true

apply_tree_permissions "$STAGE"

gzip_cmd() {
    gzip -9
}

(
    cd "$STAGE"
    find . -print0 | cpio --null --create --format=newc --owner=0:0 2>/dev/null \
        || find . | cpio -o -H newc
) | gzip_cmd > "$OUT_CPIO"

[ -s "$OUT_CPIO" ] || die "empty initramfs archive"
cp -f "$OUT_CPIO" "$OUT_DIR/initramfs.cpio.gz"
info "wrote $OUT_CPIO"
info "copied $OUT_DIR/initramfs.cpio.gz"
