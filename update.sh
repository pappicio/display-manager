#!/opt/bin/sh
set -eu

PLUGIN_DIR="${OC_PLUGIN_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"

exec "$PLUGIN_DIR/install.sh"
