# Sourced by other scripts. Do not execute directly.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
DEFAULT_IMAGE_CONF="$ROOT/config/defimage.conf"

die() { echo "error: $*" >&2; exit 1; }
warn() { echo "warning: $*" >&2; }
info() { echo "$*" >&2; }

print_conf_usage() {
    echo "usage: $0 [-c|--config FILE] [FILE]" >&2
    echo "default config: config/defimage.conf" >&2
}

# Resolve FILE to an absolute path. Looks in cwd, $ROOT, and $ROOT/config.
resolve_conf_path() {
    conf="$1"
    case "$conf" in
        /*)
            echo "$conf"
            return 0
            ;;
    esac
    if [ -f "$conf" ]; then
        echo "$(CDPATH= cd -- "$(dirname -- "$conf")" && pwd)/$(basename "$conf")"
        return 0
    fi
    if [ -f "$ROOT/$conf" ]; then
        echo "$ROOT/$conf"
        return 0
    fi
    if [ -f "$ROOT/config/$conf" ]; then
        echo "$ROOT/config/$conf"
        return 0
    fi
    echo "$conf"
}

load_image_conf() {
    conf="${1:-}"
    if [ -z "$conf" ]; then
        conf="$DEFAULT_IMAGE_CONF"
    else
        conf=$(resolve_conf_path "$conf")
    fi
    [ -f "$conf" ] || die "missing config: $conf"
    IMAGE_CONF="$conf"
    info "config $IMAGE_CONF"
    set -a
    # shellcheck disable=SC1091
    . "$conf"
    set +a
    : "${ARCH:=amd64}"
    : "${IMAGE_NAME:=minilinux-amd64.img}"
    : "${GAP_MIB:=1}"
    : "${ESP_SIZE_MIB:=8}"
    : "${BOOT_SIZE_MIB:=40}"
    : "${ESP_LABEL:=MINLINUXESP}"
    : "${BOOT_LABEL:=MINILINUXBOOT}"
    : "${ESP_TYPE:=ef}"
    : "${BOOT_TYPE:=83}"
    : "${GRUB_VERSION:=grub2}"
    case "$GRUB_VERSION" in
        grub|grub2) ;;
        *) die "GRUB_VERSION must be grub or grub2 (got: $GRUB_VERSION)" ;;
    esac
    ARCH_DIR="$ROOT/arch/$ARCH"
    KERNEL_DIR="$ARCH_DIR/kernel"
    GRUB1_DIR="$ARCH_DIR/grub"
    GRUB2_DIR="$ARCH_DIR/grub2"
    INITRAMFS_DIR="$ARCH_DIR/initramfs"
    OUT_DIR="$ROOT/out"
    info "GRUB_VERSION=$GRUB_VERSION"
}

# Parse -c/--config FILE or a positional FILE, then load it.
load_image_conf_from_args() {
    conf=""
    while [ $# -gt 0 ]; do
        case "$1" in
            -c|--config)
                [ -n "${2:-}" ] || die "missing value for $1"
                conf="$2"
                shift 2
                ;;
            --config=*)
                conf="${1#--config=}"
                shift
                ;;
            -h|--help)
                print_conf_usage
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
                [ -z "$conf" ] || die "unexpected argument: $1"
                conf="$1"
                shift
                ;;
        esac
    done
    load_image_conf "$conf"
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "need command: $1"
}

sudo_if_needed() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        die "need root (or sudo) for: $*"
    fi
}

# Apply type + override modes under DIR via permission.sh. Missing DIR is a no-op.
apply_tree_permissions() {
    dir="${1:-}"
    [ -n "$dir" ] && [ -d "$dir" ] || return 0
    sh "$SCRIPT_DIR/permission.sh" -d "$dir"
}
