
#!/opt/bin/sh
set -eu

CONFIG_DIR="${OC_CONFIG_DIR:-/usr/data/opencreator/klipper/config}"
PLUGIN_DATA="${OC_PLUGIN_DATA:?OC_PLUGIN_DATA is not set}"
STARTUP_DIR="/usr/data/opencreator/startup/scripts"
PYTHON="/usr/data/python-hf/bin/python3"

echo "[Display Manager] Removing plugin configuration..."

"$PYTHON" - "$CONFIG_DIR" <<'PY'
import sys
from pathlib import Path

config = Path(sys.argv[1])

def remove(path, begin, end):
    if not path.is_file():
        return

    text = path.read_text()
    a, b = text.count(begin), text.count(end)

    if a != b or a > 1:
        raise SystemExit(
            f"Invalid markers in {path}; file left untouched"
        )

    if a:
        pos = text.index(begin)
        endpos = text.index(end, pos) + len(end)
        path.write_text(text[:pos] + text[endpos:])

remove(
    config / "oc-macros.cfg",
    "# BEGIN display-manager",
    "# END display-manager",
)

remove(
    config / "printer.base.cfg",
    "# BEGIN display-manager include",
    "# END display-manager include",
)

print("[Display Manager] Own macros and include removed.")
print("[Display Manager] Shared oc-macros.cfg preserved.")
PY

echo "[Display Manager] Restoring original startup scripts..."

LEGACY_DIR="$PLUGIN_DATA/legacy-startup"
mkdir -p "$STARTUP_DIR"

for FILE in 40-grumpyscreen.sh 41-helixscreen.sh; do
    BACKUP="$LEGACY_DIR/$FILE"

    if [ -f "$BACKUP" ]; then
        if [ ! -e "$STARTUP_DIR/$FILE" ]; then
            cp -p "$BACKUP" "$STARTUP_DIR/$FILE"
            rm -f "$BACKUP"
            echo "[OK] Restored $FILE"
        else
            echo "[SKIP] $FILE already exists; backup preserved."
        fi
    fi
done

echo "[Display Manager] Uninstallation completed."
