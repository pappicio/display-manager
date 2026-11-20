#!/opt/bin/sh
set -eu

SCRIPT="/usr/data/opencreator/scripts/display-manager.sh"
CONFIG_DIR="/usr/data/opencreator/klipper/config"
PYTHON="/usr/data/python-hf/bin/python3"

rm -f "$SCRIPT"

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
        raise SystemExit(f"Invalid markers in {path}; file left untouched")

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

echo "[Display Manager] Removed installed script: $SCRIPT"
