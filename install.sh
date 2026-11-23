
#!/opt/bin/sh
set -eu

PLUGIN_DIR="${OC_PLUGIN_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}"
PLUGIN_DATA="${OC_PLUGIN_DATA:?OC_PLUGIN_DATA is not set}"
CONFIG_DIR="${OC_CONFIG_DIR:-/usr/data/opencreator/klipper/config}"
PYTHON="/usr/data/python-hf/bin/python3"

GRUMPY_DIR="/usr/data/grumpyscreen"
GRUMPY_BIN="$GRUMPY_DIR/grumpyscreen"

HELIX_DIR="/usr/data/helixscreen"
HELIX_BIN="$HELIX_DIR/bin/helix-screen"
HELIX_URL="https://github.com/prestonbrown/helixscreen/releases/download/v1.1.0-rc.4/helixscreen-k1-v1.1.0-rc.4.tar.gz"

SOURCE="$PLUGIN_DIR/scripts/display-manager.sh"
SUPERVISOR_SOURCE="$PLUGIN_DIR/scripts/display-manager-supervisor.py"

LEGACY_DIR="/usr/data/opencreator/startup/scripts"
LEGACY_BACKUP_DIR="$PLUGIN_DATA/legacy-startup"

SHARED_SCRIPTS="/usr/data/opencreator/scripts"

echo
echo "========== DISPLAY MANAGER INSTALLER =========="

# Validate native plugin files.
for FILE in "$SOURCE" "$SUPERVISOR_SOURCE"; do
    if [ ! -f "$FILE" ]; then
        echo "[ERROR] Missing $FILE"
        exit 1
    fi
done

[ -x "$PYTHON" ] || {
    echo "[ERROR] Python interpreter not found: $PYTHON"
    exit 1
}

echo "[OK] Native plugin files verified."

echo
echo "========== GRUMPYSCREEN =========="

if [ -x "$GRUMPY_BIN" ]; then
    echo "[OK] GrumpyScreen already exists: $GRUMPY_BIN"
else
    echo "[MISSING] GrumpyScreen not found."
    echo "[DOWNLOAD] Searching latest stable MIPS/K1 release..."

    "$PYTHON" - "$GRUMPY_DIR" <<'PY'
import json
import shutil
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from pathlib import Path

dest = Path(sys.argv[1])
api = "https://api.github.com/repos/FlashForge-C5-Modding-Group/grumpyscreen/releases/latest"
headers = {"User-Agent": "OpenCreator-DisplayManager"}

def get(url):
    return urllib.request.urlopen(
        urllib.request.Request(url, headers=headers), timeout=90
    )

with get(api) as response:
    release = json.load(response)

print("[INFO] Release:", release.get("tag_name"))

assets = release.get("assets", [])
candidates = [
    a for a in assets
    if any(x in a["name"].lower() for x in ("mips", "mipsel", "xburst", "k1"))
    and a["name"].lower().endswith((".tar.gz", ".tgz", ".tar", ".zip"))
]

if len(candidates) != 1:
    print("[ERROR] Expected exactly one MIPS/K1 archive.")
    for asset in assets:
        print("  " + asset["name"])
    sys.exit(1)

asset = candidates[0]
print("[DOWNLOAD]", asset["name"])

with tempfile.TemporaryDirectory(prefix="grumpy-") as tmp:
    archive = Path(tmp) / asset["name"]

    with get(asset["browser_download_url"]) as response, archive.open("wb") as out:
        shutil.copyfileobj(response, out)

    extracted = Path(tmp) / "extract"
    extracted.mkdir()

    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as z:
            for name in z.namelist():
                p = Path(name)
                if p.is_absolute() or ".." in p.parts:
                    raise SystemExit("[ERROR] Unsafe archive path")
            z.extractall(extracted)

    elif tarfile.is_tarfile(archive):
        with tarfile.open(archive) as t:
            for member in t.getmembers():
                p = Path(member.name)
                if p.is_absolute() or ".." in p.parts:
                    raise SystemExit("[ERROR] Unsafe archive path")
            t.extractall(extracted)
    else:
        raise SystemExit("[ERROR] Unsupported archive format")

    binaries = list(extracted.rglob("grumpyscreen"))
    if not binaries:
        raise SystemExit("[ERROR] grumpyscreen binary not found")

    source_dir = binaries[0].parent
    dest.mkdir(parents=True, exist_ok=True)

    for item in source_dir.iterdir():
        target = dest / item.name
        if item.is_dir():
            shutil.copytree(item, target, dirs_exist_ok=True)
        else:
            shutil.copy2(item, target)

    installed = dest / "grumpyscreen"
    if not installed.is_file():
        raise SystemExit("[ERROR] GrumpyScreen installation failed")

    installed.chmod(installed.stat().st_mode | 0o111)
    print("[OK] GrumpyScreen installed.")
PY
fi

if [ ! -x "$GRUMPY_BIN" ]; then
    echo "[ERROR] GrumpyScreen verification failed."
    exit 1
fi

echo "[OK] GrumpyScreen verified."

echo
echo "========== HELIXSCREEN =========="

if [ -x "$HELIX_BIN" ]; then
    echo "[OK] HelixScreen already exists: $HELIX_BIN"
else
    echo "[MISSING] HelixScreen not found."
    echo "[DOWNLOAD] Downloading HelixScreen v1.1.0-rc.4..."

    ARCHIVE="/tmp/helixscreen-k1-v1.1.0-rc.4.tar.gz"
    EXTRACT="/tmp/helixscreen-k1-extract"

    rm -rf "$EXTRACT"
    mkdir -p "$EXTRACT"

    curl -fL --retry 2 --progress-bar "$HELIX_URL" -o "$ARCHIVE"

    echo "[EXTRACT] Extracting HelixScreen package..."
    tar -xzf "$ARCHIVE" -C "$EXTRACT"

    PACKAGE_DIR="$EXTRACT/helixscreen"

    if [ ! -d "$PACKAGE_DIR" ]; then
        echo "[ERROR] HelixScreen directory not found in package."
        exit 1
    fi

    mkdir -p "$HELIX_DIR"
    cp -a "$PACKAGE_DIR/." "$HELIX_DIR/"

    if [ ! -f "$HELIX_BIN" ]; then
        echo "[ERROR] HelixScreen binary not found: $HELIX_BIN"
        exit 1
    fi

    find "$HELIX_DIR/bin" -type f -exec chmod 755 {} \;

    rm -rf "$EXTRACT" "$ARCHIVE"

    echo "[OK] HelixScreen installed successfully."
fi

if [ ! -x "$HELIX_BIN" ]; then
    echo "[ERROR] HelixScreen verification failed: $HELIX_BIN"
    exit 1
fi

echo "[OK] HelixScreen verified."

echo
echo "========== KLIPPER CONFIGURATION =========="

"$PYTHON" - "$CONFIG_DIR" <<'PY'
import re
import sys
from pathlib import Path

config = Path(sys.argv[1])
macros = config / "oc-macros.cfg"
printer = config / "printer.base.cfg"

begin = "# BEGIN display-manager"
end = "# END display-manager"
ibegin = "# BEGIN display-manager include"
iend = "# END display-manager include"

block = """# BEGIN display-manager
[gcode_shell_command switch_grumpy]
command: sh -c "echo grumpy > /usr/data/opencreator/screen"
timeout: 5.
verbose: False

[gcode_shell_command switch_helix]
command: sh -c "echo helix > /usr/data/opencreator/screen"
timeout: 5.
verbose: False

[gcode_macro SCREEN_GRUMPY]
description: Switch to GrumpyScreen
gcode:
    RUN_SHELL_COMMAND CMD=switch_grumpy

[gcode_macro SCREEN_HELIX]
description: Switch to HelixScreen
gcode:
    RUN_SHELL_COMMAND CMD=switch_helix
# END display-manager"""

include = """# BEGIN display-manager include
[include oc-macros.cfg]
# END display-manager include"""

def update(path, start, finish, replacement, conflicts=()):
    text = path.read_text() if path.exists() else ""
    a, b = text.count(start), text.count(finish)

    if a != b or a > 1:
        raise SystemExit(f"Invalid markers in {path}")

    if a:
        pos = text.index(start)
        endpos = text.index(finish, pos) + len(finish)
        text = text[:pos] + replacement + text[endpos:]
    else:
        for pattern, name in conflicts:
            if re.search(pattern, text, re.M):
                raise SystemExit(
                    f"{name} already exists outside managed block in {path}"
                )

        if text and not text.endswith("\n"):
            text += "\n"
        if text:
            text += "\n"
        text += replacement + "\n"

    path.write_text(text)

config.mkdir(parents=True, exist_ok=True)

update(macros, begin, end, block, [
    (r"^\[gcode_shell_command\s+switch_grumpy\]", "switch_grumpy"),
    (r"^\[gcode_shell_command\s+switch_helix\]", "switch_helix"),
    (r"^\[gcode_macro\s+SCREEN_GRUMPY\]", "SCREEN_GRUMPY"),
    (r"^\[gcode_macro\s+SCREEN_HELIX\]", "SCREEN_HELIX"),
])

if not printer.is_file():
    raise SystemExit(f"Missing {printer}")

text = printer.read_text()
a, b = text.count(ibegin), text.count(iend)

if a != b or a > 1:
    raise SystemExit(f"Invalid include markers in {printer}")

if a:
    pos = text.index(ibegin)
    endpos = text.index(iend, pos) + len(iend)
    text = text[:pos] + include + text[endpos:]
elif not re.search(r"^\s*\[include\s+oc-macros\.cfg\s*\]", text, re.M):
    if text and not text.endswith("\n"):
        text += "\n"
    if text:
        text += "\n"
    text += include + "\n"

printer.write_text(text)
print("[OK] Klipper macros installed.")
PY

echo
echo "========== LEGACY STARTUP MIGRATION =========="

mkdir -p "$LEGACY_BACKUP_DIR"

for FILE in 40-grumpyscreen.sh 41-helixscreen.sh; do
    SOURCE_FILE="$LEGACY_DIR/$FILE"
    BACKUP_FILE="$LEGACY_BACKUP_DIR/$FILE"

    # Migrate backups created by the previous installer.
    OLD_BACKUP="$PLUGIN_DIR/$FILE.bak"

    if [ -f "$OLD_BACKUP" ] && [ ! -e "$BACKUP_FILE" ]; then
        mv "$OLD_BACKUP" "$BACKUP_FILE"
        echo "[OK] Migrated previous backup: $FILE"
    fi

    if [ -f "$SOURCE_FILE" ]; then
        if [ ! -e "$BACKUP_FILE" ]; then
            mv "$SOURCE_FILE" "$BACKUP_FILE"
            echo "[OK] Archived legacy startup script: $FILE"
        else
            echo "[WARNING] Existing backup preserved; legacy script left untouched: $FILE"
        fi
    fi
done

echo
echo "========== LEGACY SCRIPT CLEANUP =========="

# Remove only files previously owned by Display Manager.
# Never delete unrelated user scripts.
if [ -d "$SHARED_SCRIPTS" ]; then
    for FILE in \
        display-manager.sh \
        display-manager.sh.run \
        display-manager-supervisor.py
    do
        if [ -f "$SHARED_SCRIPTS/$FILE" ] || [ -L "$SHARED_SCRIPTS/$FILE" ]; then
            rm -f "$SHARED_SCRIPTS/$FILE"
            echo "[OK] Removed legacy shared file: $FILE"
        fi
    done
fi

echo
echo "========== INSTALLATION SUMMARY =========="
echo "[OK] GrumpyScreen: $GRUMPY_BIN"
echo "[OK] HelixScreen: $HELIX_BIN"
echo "[OK] Display Manager source: $SOURCE"
echo "[OK] Supervisor source: $SUPERVISOR_SOURCE"
echo "[OK] Legacy startup backups: $LEGACY_BACKUP_DIR"
echo "[OK] No files copied to opencreator/scripts."
echo "[OK] OpenCreator will start the native service from the manifest."
echo
echo "========== INSTALLATION COMPLETE =========="
