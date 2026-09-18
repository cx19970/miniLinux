#!/bin/sh
# Top-level image build. Forwards args to scripts under scripts/.
# Usage:
#   ./build.sh
#   ./build.sh -c config/defimage.conf
#   ./build.sh config/custom.conf
# Default config: config/defimage.conf

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SCRIPTS="$ROOT/scripts"

case "${1:-}" in
    -h|--help)
        echo "usage: $0 [-c|--config FILE] [FILE]"
        echo "default config: config/defimage.conf"
        exit 0
        ;;
esac

sh "$SCRIPTS/mkinitramfs.sh" "$@"
sh "$SCRIPTS/mkefi.sh" "$@"
sh "$SCRIPTS/mkimg.sh" "$@"
