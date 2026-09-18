#!/bin/sh
# Set modes under a directory: type defaults, then exact-path overrides.
# Usage:
#   scripts/permission.sh
#   scripts/permission.sh -d arch
#   scripts/permission.sh -d arch/amd64/initramfs
#   scripts/permission.sh --dry-run -v
# Default directory: arch/
#
# Directories: only the directory itself is changed (not recursive via the
# override table). Symlinks and generated *.cpio.gz archives are skipped.
#
# Type defaults (no +x, no file(1)):
#   directory                              0755
#   symlink                                skip
#   ELF \x7fELF (ET_EXEC / ET_DYN / ET_REL) 0755  bins, PIE, .so, grub .mod
#   shebang #!                             0755
#   .sh .bash .ksh .zsh .dash .csh .tcsh .py  0755
#   .mod                                   0755
#   other regular files                    0644
# Static .a, PE/EFI, bzImage, ARM64 Image: exact paths in PERM_OVERRIDES.

set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"

print_perm_usage() {
    echo "usage: $0 [-d DIR] [--dry-run] [-v]" >&2
    echo "default directory: arch/" >&2
}

TARGET=""
DRY_RUN=0
VERBOSE=0

while [ $# -gt 0 ]; do
    case "$1" in
        -d|--dir)
            [ -n "${2:-}" ] || die "missing value for $1"
            TARGET="$2"
            shift 2
            ;;
        --dir=*)
            TARGET="${1#--dir=}"
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            print_perm_usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            die "unknown option: $1"
            ;;
        *)
            [ -z "$TARGET" ] || die "unexpected argument: $1"
            TARGET="$1"
            shift
            ;;
    esac
done

[ -z "$TARGET" ] && TARGET="$ROOT/arch"

resolve_target_dir() {
    d="$1"
    case "$d" in
        /*)
            [ -d "$d" ] || die "not a directory: $d"
            echo "$d"
            return 0
            ;;
    esac
    if [ -d "$d" ]; then
        echo "$(CDPATH= cd -- "$d" && pwd)"
        return 0
    fi
    if [ -d "$ROOT/$d" ]; then
        echo "$(CDPATH= cd -- "$ROOT/$d" && pwd)"
        return 0
    fi
    die "not a directory: $d"
}

TARGET=$(resolve_target_dir "$TARGET")
need_cmd find
need_cmd stat

# Exact relative path (from TARGET) -> mode. Comments and blank lines ignored.
# Paths are listed both under arch/ and under an initramfs root so the same
# special files match whether the user points at arch/ or a staging tree.
PERM_OVERRIDES=$(cat <<'EOF'
# relative to arch/
amd64/initramfs/init                         0755
amd64/initramfs/etc/shadow                   0600
amd64/initramfs/etc/passwd                   0644
amd64/initramfs/etc/group                    0644
amd64/initramfs/etc/shells                   0644
amd64/initramfs/etc/nsswitch.conf            0644
amd64/initramfs/etc/ld.so.conf               0644
amd64/initramfs/etc/mdev.conf                0644
amd64/initramfs/etc/profile                  0644
amd64/initramfs/tmp                          1777
amd64/initramfs/var/tmp                      1777
amd64/initramfs/README.txt                   0644
amd64/kernel/README.txt                      0644
amd64/grub/README.txt                        0644
amd64/grub2/README.txt                       0644
# kernel / EFI (not classified by type defaults)
amd64/kernel/bzImage                         0755
amd64/grub2/EFI/BOOT/BOOTX64.EFI             0755
arm64/kernel/Image                           0755
# static libraries (.a) — add paths here, mode 0644
# amd64/initramfs/usr/lib/x86_64-linux-gnu/libc.a  0644
# relative to an initramfs root (mkinitramfs staging)
init                                         0755
etc/shadow                                   0600
etc/passwd                                   0644
etc/group                                    0644
etc/shells                                   0644
etc/nsswitch.conf                            0644
etc/ld.so.conf                               0644
etc/mdev.conf                                0644
etc/profile                                  0644
tmp                                          1777
var/tmp                                      1777
README.txt                                   0644
# kernel / EFI on a kernel dir, boot tree, or ESP
bzImage                                      0755
Image                                        0755
EFI/BOOT/BOOTX64.EFI                         0755
BOOTX64.EFI                                  0755
EOF
)

norm_mode() {
    m=$1
    while :; do
        case "$m" in
            0*)
                m=${m#0}
                [ -n "$m" ] || { m=0; break; }
                ;;
            *)
                break
                ;;
        esac
    done
    printf '%s\n' "$m"
}

relpath_from_target() {
    t="$1"
    p="$2"
    if [ "$p" = "$t" ]; then
        printf '%s\n' "."
        return 0
    fi
    r=${p#"$t"/}
    r=${r#./}
    printf '%s\n' "$r"
}

override_mode() {
    rel="$1"
    printf '%s\n' "$PERM_OVERRIDES" | awk -v r="$rel" '
        /^[[:space:]]*#/ { next }
        NF < 2 { next }
        $1 == r { print $2; exit }
    '
}

read_magic_hex() {
    dd if="$1" bs=1 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n'
}

type_default_mode() {
    path="$1"
    if [ -d "$path" ]; then
        printf '%s\n' "755"
        return 0
    fi
    if [ -L "$path" ] || [ ! -f "$path" ]; then
        printf '%s\n' ""
        return 0
    fi

    mag=$(read_magic_hex "$path")
    case "$mag" in
        7f454c46*)
            # ELF: ET_EXEC, ET_DYN (PIE + shared objects), ET_REL (grub .mod)
            printf '%s\n' "755"
            return 0
            ;;
        2321*)
            printf '%s\n' "755"
            return 0
            ;;
    esac

    base=$(basename "$path")
    case "$base" in
        *.mod)
            printf '%s\n' "755"
            return 0
            ;;
        *.sh|*.bash|*.ksh|*.zsh|*.dash|*.csh|*.tcsh|*.py)
            printf '%s\n' "755"
            return 0
            ;;
    esac
    printf '%s\n' "644"
}

do_chmod() {
    mode="$1"
    path="$2"
    if chmod "$mode" "$path" 2>/dev/null; then
        return 0
    fi
    sudo_if_needed chmod "$mode" "$path"
}

current_mode() {
    path="$1"
    if stat -c %a "$path" >/dev/null 2>&1; then
        stat -c %a "$path"
        return 0
    fi
    sudo_if_needed stat -c %a "$path"
}

info "permission $TARGET"

list=$(mktemp /tmp/minilinux-perm.XXXXXX)
cleanup_list() {
    rm -f "$list"
}
trap cleanup_list EXIT INT TERM

find "$TARGET" \( -type f -o -type d \) > "$list"

changed=0
unchanged=0
skipped=0

while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -f "$path" ] && [ ! -L "$path" ]; then
        case "$path" in
            *.cpio.gz)
                skipped=$((skipped + 1))
                continue
                ;;
        esac
    fi

    rel=$(relpath_from_target "$TARGET" "$path")
    expected=$(override_mode "$rel")
    if [ -z "$expected" ]; then
        expected=$(type_default_mode "$path")
    fi
    if [ -z "$expected" ]; then
        skipped=$((skipped + 1))
        continue
    fi
    expected=$(norm_mode "$expected")

    cur=$(current_mode "$path" 2>/dev/null || true)
    if [ -z "$cur" ]; then
        warn "cannot stat $rel"
        skipped=$((skipped + 1))
        continue
    fi
    cur=$(norm_mode "$cur")

    if [ "$cur" = "$expected" ]; then
        unchanged=$((unchanged + 1))
        [ "$VERBOSE" = 1 ] && info "$expected  $rel"
        continue
    fi

    if [ "$DRY_RUN" = 1 ]; then
        info "chmod $expected $rel"
        changed=$((changed + 1))
        continue
    fi

    do_chmod "$expected" "$path"
    [ "$VERBOSE" = 1 ] && info "$expected  $rel"
    changed=$((changed + 1))
done < "$list"

if [ "$DRY_RUN" = 1 ]; then
    info "permission dry-run: would-change=$changed unchanged=$unchanged skipped=$skipped"
else
    info "permission: changed=$changed unchanged=$unchanged skipped=$skipped"
fi
