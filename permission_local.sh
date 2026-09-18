#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SCRIPTS="$ROOT/scripts"

chmod a+x "$ROOT"/*.sh

chmod a+x "$SCRIPTS"/*.sh

sh "$SCRIPTS/permission.sh"

sync

exit 0
