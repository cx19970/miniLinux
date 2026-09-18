#!/bin/sh
# One-shot: drop extra userspace into arch/$ARCH/initramfs.
# Cache-first; downloads Ubuntu jammy (and Debian if needed) debs.
# Not invoked by build.sh. Run on Linux or WSL:
#   scripts/fetch-initramfs-extras.sh
#   REF_FS=/path/to/gen-sys-img-x86/fs scripts/fetch-initramfs-extras.sh
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/common.sh"
load_image_conf_from_args "$@"

IR="$INITRAMFS_DIR"
CACHE="$OUT_DIR/cache/initramfs-debs"
STAGING="$CACHE/deb-extra"
IDX="$CACHE/pkg-idx"
REF_FS="${REF_FS:-/mnt/c/Users/Wang/Desktop/gen-sys-img-x86/fs}"

# Official archive.ubuntu.com is often unreachable from this host; Aliyun carries jammy + security.
UBU_ARCHIVE="${UBU_ARCHIVE:-https://mirrors.aliyun.com/ubuntu}"
UBU_SECURITY="${UBU_SECURITY:-https://mirrors.aliyun.com/ubuntu}"
DEB_MIRROR="${DEB_MIRROR:-https://mirrors.aliyun.com/debian}"

SKIP_DEPS="libc6 libgcc-s1 libstdc++6 gcc-12-base gcc-11-base gcc-10-base gcc-9-base
systemd systemd-sysv systemd-timesyncd libpam-systemd systemd-shared
debconf dpkg perl perl-base python3 python3-minimal python3.10 python3.10-minimal
adduser passwd lsb-base lsb-release init-system-helpers
bash-completion debianutils dash sensible-utils
cron logrotate linux-base util-linux mount login base-files
udev kmod dmsetup e2fsprogs-l10n sensible-mda postfix
liblocale-gettext-perl libtext-charwidth-perl libtext-iconv-perl"

# Seed packages: programs + libc-bin (ldconfig/ldd). lib* Depends are pulled in.
SEED_PKGS="bash jq parted udev rsync acpid cryptsetup-bin e2fsprogs ethtool
fdisk ifenslave kmod btrfs-progs squashfs-tools wget wput netmask
libpam0g libpam-modules libpam-modules-bin libc-bin libcrypt1 zlib1g libsystemd0"

mkdir -p "$CACHE" "$STAGING" "$IDX" \
    "$IR/bin" "$IR/sbin" "$IR/lib" "$IR/lib64" \
    "$IR/usr/bin" "$IR/usr/sbin" "$IR/usr/lib" "$IR/etc"

need_cmd curl
need_cmd gzip
need_cmd awk
need_cmd python3

download() {
    dl_url="$1"
    dl_dest="$2"
    if [ -s "$dl_dest" ]; then
        return 0
    fi
    dl_tmp="$dl_dest.part"
    info "download $dl_url"
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$dl_tmp" "$dl_url" || return $?
    mv -f "$dl_tmp" "$dl_dest"
}

fetch_idx() {
    idx_url="$1"
    idx_out="$2"
    if [ -s "$idx_out" ]; then
        return 0
    fi
    idx_gz="$idx_out.gz"
    download "$idx_url" "$idx_gz" || return $?
    gzip -dc "$idx_gz" > "$idx_out"
}

info "refresh package indexes (cached if present)"
fetch_idx "$UBU_ARCHIVE/dists/jammy-updates/main/binary-amd64/Packages.gz" "$IDX/u-upd-main"
fetch_idx "$UBU_ARCHIVE/dists/jammy-updates/universe/binary-amd64/Packages.gz" "$IDX/u-upd-uni"
fetch_idx "$UBU_SECURITY/dists/jammy-security/main/binary-amd64/Packages.gz" "$IDX/u-sec-main"
fetch_idx "$UBU_SECURITY/dists/jammy-security/universe/binary-amd64/Packages.gz" "$IDX/u-sec-uni"
fetch_idx "$UBU_ARCHIVE/dists/jammy/main/binary-amd64/Packages.gz" "$IDX/u-jam-main"
fetch_idx "$UBU_ARCHIVE/dists/jammy/universe/binary-amd64/Packages.gz" "$IDX/u-jam-uni"
fetch_idx "$DEB_MIRROR/dists/bookworm/main/binary-amd64/Packages.gz" "$IDX/d-book-main" || warn "Debian bookworm index skipped"
fetch_idx "$DEB_MIRROR/dists/bullseye/main/binary-amd64/Packages.gz" "$IDX/d-bull-main" || warn "Debian bullseye index skipped"

# Resolve Filename + Depends. First matching index wins (updates, then security, then jammy, then Debian).
resolve_py="$IDX/resolve.py"
cat > "$resolve_py" << PY
import os, re, sys

def parse_file(path, mirror, pkgs):
    rec = []
    def flush():
        if not rec:
            return
        name = filename = depends = ""
        for line in rec:
            if line.startswith("Package: "):
                name = line[9:].strip()
            elif line.startswith("Filename: "):
                filename = line[10:].strip()
            elif line.startswith("Depends: "):
                depends = line[9:].strip()
        if name and filename and name not in pkgs:
            pkgs[name] = (mirror, filename, depends)
    with open(path, "r", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if line == "":
                flush()
                rec = []
            else:
                rec.append(line)
        flush()

def dep_names(depends):
    out = []
    if not depends:
        return out
    for part in depends.split(","):
        first = part.split("|")[0].strip()
        m = re.match(r"^([a-zA-Z0-9.+-]+)", first)
        if m:
            out.append(m.group(1))
    return out

idx_root = sys.argv[1]
cmd = sys.argv[2]
files = [
    ("u-upd-main", "$UBU_ARCHIVE"),
    ("u-upd-uni", "$UBU_ARCHIVE"),
    ("u-sec-main", "$UBU_SECURITY"),
    ("u-sec-uni", "$UBU_SECURITY"),
    ("u-jam-main", "$UBU_ARCHIVE"),
    ("u-jam-uni", "$UBU_ARCHIVE"),
    ("d-book-main", "$DEB_MIRROR"),
    ("d-bull-main", "$DEB_MIRROR"),
]
pkgs = {}
for name, mirror in files:
    path = os.path.join(idx_root, name)
    if os.path.isfile(path) and os.path.getsize(path) > 0:
        parse_file(path, mirror, pkgs)

if cmd == "lookup":
    pkg = sys.argv[3]
    if pkg not in pkgs:
        sys.exit(1)
    mirror, filename, depends = pkgs[pkg]
    print(mirror + "/" + filename)
    print(depends)
elif cmd == "closure":
    skip = set(sys.argv[3].split())
    seeds = [s for s in sys.argv[4].split() if s]
    seed_set = set(seeds)
    skip -= seed_set
    seen = []
    queue = list(seeds)
    i = 0
    while i < len(queue):
        p = queue[i]
        i += 1
        if p in skip or p in seen:
            continue
        if p not in pkgs:
            print("missing:" + p, file=sys.stderr)
            continue
        seen.append(p)
        _m, _f, deps = pkgs[p]
        for d in dep_names(deps):
            if d.startswith("lib") and d not in skip and d not in seen and d not in queue:
                queue.append(d)
    for p in seen:
        print(p)
else:
    sys.exit(2)
PY

pkg_url() {
    python3 "$resolve_py" "$IDX" lookup "$1" | awk 'NR==1{print; exit}'
}

info "resolve package closure"
CLOSURE=$(python3 "$resolve_py" "$IDX" closure "$SKIP_DEPS" "$SEED_PKGS")
# Always try reiserfsprogs (may only exist on Debian).
case "$CLOSURE" in
    *reiserfsprogs*) ;;
    *)
        if python3 "$resolve_py" "$IDX" lookup reiserfsprogs >/dev/null 2>&1; then
            CLOSURE="$CLOSURE reiserfsprogs"
        else
            warn "reiserfsprogs not in Ubuntu/Debian indexes"
        fi
        ;;
esac

info "packages: $(echo "$CLOSURE" | wc -w | tr -d ' ')"

DEBDIR="$CACHE/debs"
mkdir -p "$DEBDIR"
MISSING_PKGS=""
for pkg in $CLOSURE; do
    [ -n "$pkg" ] || continue
    deb="$DEBDIR/${pkg}.deb"
    if [ -s "$deb" ]; then
        continue
    fi
    url=$(pkg_url "$pkg" || true)
    if [ -z "$url" ]; then
        warn "no Filename for $pkg"
        MISSING_PKGS="$MISSING_PKGS $pkg"
        continue
    fi
    if ! download "$url" "$deb"; then
        warn "download failed $pkg"
        MISSING_PKGS="$MISSING_PKGS $pkg"
        rm -f "$deb.part"
    fi
done

extract_deb() {
    deb="$1"
    dest="$2"
    mkdir -p "$dest"
    if command -v dpkg-deb >/dev/null 2>&1; then
        dpkg-deb -x "$deb" "$dest"
        return
    fi
    tmp=$(mktemp -d)
    (
        cd "$tmp"
        ar x "$deb"
        if [ -f data.tar.xz ]; then
            tar -xJf data.tar.xz -C "$dest"
        elif [ -f data.tar.zst ]; then
            tar --zstd -xf data.tar.zst -C "$dest"
        elif [ -f data.tar.gz ]; then
            tar -xzf data.tar.gz -C "$dest"
        elif [ -f data.tar.bz2 ]; then
            tar -xjf data.tar.bz2 -C "$dest"
        else
            echo "no data.tar in $deb" >&2
            exit 1
        fi
    )
    rm -rf "$tmp"
}

info "extract debs -> $STAGING"
rm -rf "$STAGING"
mkdir -p "$STAGING"
for deb in "$DEBDIR"/*.deb; do
    [ -f "$deb" ] || continue
    extract_deb "$deb" "$STAGING"
done
rm -rf "$STAGING/usr/share/doc" \
    "$STAGING/usr/share/lintian" \
    "$STAGING/usr/share/locale" \
    "$STAGING/usr/share/man" \
    "$STAGING/usr/share/info" \
    "$STAGING/usr/share/gcc" \
    "$STAGING/usr/share/bash-completion" \
    "$STAGING/usr/lib/debug" 2>/dev/null || true

# Copy a path from staging (or elsewhere), resolving absolute symlinks to regular files.
copy_resolved() {
    src="$1"
    dest="$2"
    [ -e "$src" ] || [ -L "$src" ] || return 1
    mkdir -p "$(dirname "$dest")"
    cand="$src"
    n=0
    while [ -L "$cand" ] && [ "$n" -lt 12 ]; do
        t=$(readlink "$cand")
        case "$t" in
            /*)
                if [ -e "$STAGING$t" ] || [ -L "$STAGING$t" ]; then
                    cand="$STAGING$t"
                elif [ -e "$t" ]; then
                    cand="$t"
                else
                    break
                fi
                ;;
            *)
                cand="$(dirname "$cand")/$t"
                ;;
        esac
        n=$((n + 1))
    done
    if [ -f "$cand" ]; then
        rm -f "$dest"
        cp -a "$cand" "$dest"
        return 0
    fi
    return 1
}

find_cmd() {
    name="$1"
    # Prefer sbin/bin over usr/* to match a small root.
    for d in sbin bin usr/sbin usr/bin; do
        p="$STAGING/$d/$name"
        if [ -e "$p" ] || [ -L "$p" ]; then
            printf '%s\n' "$p"
            return 0
        fi
    done
    found=$(find "$STAGING" \( -type f -o -type l \) -name "$name" 2>/dev/null | awk '
        /\/usr\/share\// { next }
        { print; exit }
    ')
    if [ -n "$found" ]; then
        printf '%s\n' "$found"
        return 0
    fi
    return 1
}

install_named() {
    name="$1"
    destrel="$2"
    src=$(find_cmd "$name" || true)
    if [ -z "$src" ]; then
        warn "missing command $name"
        return 1
    fi
    if copy_resolved "$src" "$IR/$destrel"; then
        chmod 755 "$IR/$destrel" 2>/dev/null || true
        info "  $destrel <- ${src#$STAGING/}"
        return 0
    fi
    warn "could not copy $name"
    return 1
}

info "install commands"
# name dest-relative
while read -r name destrel; do
    [ -n "${name:-}" ] || continue
    case "$name" in
        \#*) continue ;;
    esac
    install_named "$name" "$destrel" || true
done << 'EOF'
bash bin/bash
jq bin/jq
ldconfig bin/ldconfig
ldd usr/bin/ldd
parted bin/parted
udevadm bin/udevadm
rsync bin/rsync
acpid sbin/acpid
cryptsetup sbin/cryptsetup
e2fsck sbin/e2fsck
mke2fs sbin/mke2fs
resize2fs sbin/resize2fs
ethtool sbin/ethtool
fdisk sbin/fdisk
sfdisk sbin/sfdisk
ifenslave sbin/ifenslave
insmod sbin/insmod
rmmod sbin/rmmod
lsmod sbin/lsmod
modprobe sbin/modprobe
depmod sbin/depmod
mkfs.btrfs sbin/mkfs.btrfs
mkfs.reiserfs sbin/mkfs.reiserfs
reiserfsck sbin/reiserfsck
mksquashfs sbin/mksquashfs
unsquashfs sbin/unsquashfs
netmask sbin/netmask
wget usr/bin/wget
wput usr/bin/wput
mkfs.ext2 sbin/mkfs.ext2
mkfs.ext3 sbin/mkfs.ext3
mkfs.ext4 sbin/mkfs.ext4
fsck.ext2 sbin/fsck.ext2
fsck.ext3 sbin/fsck.ext3
fsck.ext4 sbin/fsck.ext4
tune2fs sbin/tune2fs
e2label sbin/e2label
kmod sbin/kmod
EOF

# FHS copy of ldconfig
if [ -f "$IR/bin/ldconfig" ]; then
    mkdir -p "$IR/sbin"
    cp -a "$IR/bin/ldconfig" "$IR/sbin/ldconfig"
fi

info "copy shared libraries (resolve abs symlinks)"
copy_lib_tree() {
    from="$1"
    [ -d "$from" ] || return 0
    find "$from" \( -type f -o -type l \) -print | while read -r p; do
        rel=${p#"$STAGING/"}
        case "$rel" in
            usr/share/*|usr/lib/debug/*) continue ;;
            *gconv*) continue ;;
            *.py|*.la|*.a) continue ;;
        esac
        # Skip musl
        case "$rel" in
            *musl*) warn "skip musl $rel"; continue ;;
        esac
        # Only runtime libs and pam/security modules / udev helpers that are .so
        case "$p" in
            *.so|*.so.*) ;;
            *)
                case "$rel" in
                    usr/lib/*/security/*) ;;
                    lib/*/security/*) ;;
                    *) continue ;;
                esac
                ;;
        esac
        dest="$IR/$rel"
        copy_resolved "$p" "$dest" || true
    done
}

copy_lib_tree "$STAGING/lib"
copy_lib_tree "$STAGING/lib64"
copy_lib_tree "$STAGING/usr/lib"
copy_lib_tree "$STAGING/usr/lib64"

# libcrypt / libnsl SONAME links sometimes live only as abs links under lib/
if [ -d "$STAGING/lib/x86_64-linux-gnu" ]; then
    mkdir -p "$IR/lib/x86_64-linux-gnu"
fi

info "copy reference extras (parser, pam, mdev, terminfo)"
if [ -d "$REF_FS" ]; then
    if [ -f "$REF_FS/bin/parser" ] && [ "$(wc -c < "$REF_FS/bin/parser" | tr -d ' ')" -gt 64 ]; then
        cp -a "$REF_FS/bin/parser" "$IR/bin/parser"
        chmod 755 "$IR/bin/parser"
        info "  bin/parser <- reference"
        xml="$REF_FS/lib64/libxml2.so.2.8.0"
        if [ -f "$xml" ] && [ "$(wc -c < "$xml" | tr -d ' ')" -gt 64 ]; then
            mkdir -p "$IR/lib64" "$IR/lib/x86_64-linux-gnu"
            cp -a "$xml" "$IR/lib64/libxml2.so.2.8.0"
            cp -a "$xml" "$IR/lib64/libxml2.so.2"
            cp -a "$xml" "$IR/lib/x86_64-linux-gnu/libxml2.so.2.8.0"
            cp -a "$xml" "$IR/lib/x86_64-linux-gnu/libxml2.so.2"
            info "  libxml2.so.2 <- reference (parser)"
        fi
    else
        warn "reference parser missing or empty: $REF_FS/bin/parser"
    fi
    if [ -f "$REF_FS/etc/mdev.conf" ] && [ ! -s "$IR/etc/mdev.conf" ]; then
        cp -a "$REF_FS/etc/mdev.conf" "$IR/etc/mdev.conf"
    fi
    if [ -f "$REF_FS/etc/shells" ] && [ ! -s "$IR/etc/shells" ]; then
        cp -a "$REF_FS/etc/shells" "$IR/etc/shells"
    fi
    if [ -d "$REF_FS/etc/pam.d" ]; then
        mkdir -p "$IR/etc/pam.d"
        for f in "$REF_FS/etc/pam.d/"*; do
            [ -f "$f" ] || continue
            bn=$(basename "$f")
            [ -s "$IR/etc/pam.d/$bn" ] || cp -a "$f" "$IR/etc/pam.d/$bn"
        done
    fi
    if [ -d "$REF_FS/etc/terminfo" ]; then
        mkdir -p "$IR/etc/terminfo"
        cp -a "$REF_FS/etc/terminfo/." "$IR/etc/terminfo/"
    fi
    # Fallback reiserfs binaries from the reference tree if packages were missing.
    for n in mkfs.reiserfs reiserfsck; do
        if [ ! -s "$IR/sbin/$n" ] && [ -f "$REF_FS/sbin/$n" ]; then
            sz=$(wc -c < "$REF_FS/sbin/$n" | tr -d ' ')
            if [ "$sz" -gt 64 ]; then
                cp -a "$REF_FS/sbin/$n" "$IR/sbin/$n"
                chmod 755 "$IR/sbin/$n"
                warn "used reference ELF for sbin/$n (${sz}B); may need old glibc ABI"
            fi
        fi
    done
else
    warn "REF_FS not found: $REF_FS (parser/terminfo/pam not copied from reference)"
fi

# Do not clobber project passwd/group/nsswitch/ld.so.conf with package copies.
rm -f "$IR/etc/passwd-" "$IR/etc/group-" 2>/dev/null || true
find "$IR" -name .gitkeep -delete 2>/dev/null || true

info "busybox: $(ls -l "$IR/bin/busybox" 2>/dev/null || echo missing)"
if [ -n "$MISSING_PKGS" ]; then
    warn "packages not downloaded:$MISSING_PKGS"
fi
info "done (drop-in only; run scripts/mkinitramfs.sh to pack)"
