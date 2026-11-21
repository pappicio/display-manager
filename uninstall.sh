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

# BEGIN display-manager supervisor uninstall
rm -f /usr/data/opencreator/scripts/display-manager-supervisor.py
echo "[Display Manager] Supervisor script removed."
# END display-manager supervisor uninstall

# BEGIN display-manager stock restore
PLUGIN_DIR="${OC_PLUGIN_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"
SUPERVISOR="/usr/data/opencreator/scripts/display-manager-supervisor.py"
SUPERVISOR_PID_FILE="/tmp/oc-display-manager-supervisor.pid"
SUPERVISOR_PID="$(cat "$SUPERVISOR_PID_FILE" 2>/dev/null || true)"

case "$SUPERVISOR_PID" in
    ''|*[!0-9]*) ;;
    *)
        if [ -r "/proc/$SUPERVISOR_PID/cmdline" ] &&
           tr '\000' ' ' < "/proc/$SUPERVISOR_PID/cmdline" |
               grep -q "$SUPERVISOR"; then
            kill -TERM "$SUPERVISOR_PID" 2>/dev/null || true

            COUNT=0
            while [ "$COUNT" -lt 8 ]; do
                if [ ! -r "/proc/$SUPERVISOR_PID/cmdline" ] ||
                   ! tr '\000' ' ' < "/proc/$SUPERVISOR_PID/cmdline" |
                       grep -q "$SUPERVISOR"; then
                    break
                fi
                sleep 1
                COUNT=$((COUNT + 1))
            done

            if [ -r "/proc/$SUPERVISOR_PID/cmdline" ] &&
               tr '\000' ' ' < "/proc/$SUPERVISOR_PID/cmdline" |
                   grep -q "$SUPERVISOR"; then
                kill -KILL "$SUPERVISOR_PID" 2>/dev/null || true
            fi
        fi
        ;;
esac

rm -f /usr/data/opencreator/scripts/display-manager.sh
rm -f /usr/data/opencreator/scripts/display-manager.sh.run
rm -f "$SUPERVISOR"

STARTUP_DIR="/usr/data/opencreator/startup/scripts"
mkdir -p "$STARTUP_DIR"

for FILE in 40-grumpyscreen.sh 41-helixscreen.sh; do
    BAK="$PLUGIN_DIR/$FILE.bak"

    if [ -f "$BAK" ]; then
        if [ ! -e "$STARTUP_DIR/$FILE" ]; then
            cp -p "$BAK" "$STARTUP_DIR/$FILE"
            rm -f "$BAK"
            echo "[OK] Restored $FILE"
        else
            echo "[SKIP] $FILE already exists; backup preserved: $BAK"
        fi
    fi
done

rm -f "$SUPERVISOR_PID_FILE"
echo "[Display Manager] Stock startup restoration completed."
# END display-manager stock restore
