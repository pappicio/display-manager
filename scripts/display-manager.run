

#!/opt/bin/sh

OPENCREATOR="/usr/data/opencreator"
SCREEN_FILE="$OPENCREATOR/screen"
PID_FILE="/tmp/oc-display-manager.pid"

PLUGIN_DIR="$OPENCREATOR/plugins/display-manager"
STARTUP_SCRIPTS="$OPENCREATOR/startup/scripts"
API_CONFIG="$OPENCREATOR/api-server.json"

GRUMPY="/usr/data/grumpyscreen/grumpyscreen"
GRUMPY_DEFAULT="/usr/data/grumpyscreen/grumpyscreen.cfg"
GRUMPY_CONFIG_DIR="$OPENCREATOR/klipper/config"
GRUMPY_CFG="$GRUMPY_CONFIG_DIR/grumpyscreen.cfg"

HELIX_DIR="/usr/data/helixscreen"
HELIX_LAUNCHER="$HELIX_DIR/bin/helix-launcher.sh"
HELIX_WATCHDOG="$HELIX_DIR/bin/helix-watchdog"

LOG="/tmp/oc-display-manager.log"

DISPLAY_PID=""
CURRENT=""
DISPLAY_TYPE=""
STOPPING=0

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

# Archive new legacy startup scripts without deleting old backups unnecessarily.
migrate_startup_scripts() {
    [ -d "$PLUGIN_DIR" ] || {
        log "ERROR: Display Manager plugin directory not found: $PLUGIN_DIR"
        return 1
    }

    for NAME in 40-grumpyscreen.sh 41-helixscreen.sh; do
        SOURCE="$STARTUP_SCRIPTS/$NAME"
        DESTINATION="$PLUGIN_DIR/$NAME.bak"

        # Preserve the existing backup if there is no new source script.
        [ -f "$SOURCE" ] || continue

        # Replace the previous backup only when a new source exists.
        rm -f "$DESTINATION"

        if mv "$SOURCE" "$DESTINATION"; then
            log "Legacy startup script archived: $SOURCE -> $DESTINATION"
        else
            log "ERROR: Failed to archive startup script: $SOURCE"
            return 1
        fi
    done

    return 0
}

detect_touch() {
    awk '
        /^N: Name=/ { name = tolower($0) }
        /^H: Handlers=/ && name ~ /goodix|touch/ {
            for (i = 2; i <= NF; i++)
                if ($i ~ /^event[0-9]+$/) {
                    print "/dev/input/" $i
                    exit
                }
        }
    ' /proc/bus/input/devices 2>/dev/null
}

# Archive legacy scripts before starting the display manager.
migrate_startup_scripts || exit 1

# Avoid multiple instances.
if [ -f "$PID_FILE" ]; then
    OLD_PID="$(cat "$PID_FILE" 2>/dev/null)"

    case "$OLD_PID" in
        ''|*[!0-9]*) ;;
        *)
            if kill -0 "$OLD_PID" 2>/dev/null &&
               tr '\000' '\n' < "/proc/$OLD_PID/cmdline" 2>/dev/null |
                   grep -q 'display-manager.sh'; then
                exit 0
            fi
            ;;
    esac

    rm -f "$PID_FILE"
fi

echo "$$" > "$PID_FILE"

# Detect operating mode once.
if [ "${OC_TUNNELED+x}" = "x" ]; then
    if [ "$OC_TUNNELED" = "1" ]; then
        MODE="tunneled"
    else
        MODE="soc"
    fi
elif [ -x "$OPENCREATOR/tunneled/tunneled.sh" ]; then
    MODE="tunneled"
else
    MODE="soc"
fi

# Resolve the External Host IP dynamically from api-server.json.
get_remote_host() {
    PYTHON="$OPENCREATOR/klipper/klippy-env/bin/python"

    if [ ! -x "$PYTHON" ]; then
        PYTHON="$(command -v python3 2>/dev/null)"
    fi

    if [ -z "$PYTHON" ] || [ ! -x "$PYTHON" ]; then
        PYTHON="$(command -v python 2>/dev/null)"
    fi

    if [ -z "$PYTHON" ] || [ ! -x "$PYTHON" ]; then
        log "ERROR: Python interpreter not found"
        return 1
    fi

    if [ ! -r "$API_CONFIG" ]; then
        log "ERROR: API configuration not found: $API_CONFIG"
        return 1
    fi

    REMOTE_HOST=$("$PYTHON" -c '
import json
import sys

try:
    with open(sys.argv[1], "r") as f:
        config = json.load(f)
    host = config.get("remote_host", "")
    if isinstance(host, str):
        print(host.strip())
except Exception:
    sys.exit(1)
' "$API_CONFIG" 2>/dev/null) || {
        log "ERROR: Cannot read remote_host from API configuration"
        return 1
    }

    case "$REMOTE_HOST" in
        ''|*[!A-Za-z0-9._:-]*)
            log "ERROR: Invalid remote_host in API configuration"
            return 1
            ;;
    esac

    printf '%s' "$REMOTE_HOST"
}

if [ "$MODE" = "tunneled" ]; then
    MOONRAKER_HOST="$(get_remote_host)" || {
        log "ERROR: Cannot resolve External Host Moonraker address"
        rm -f "$PID_FILE"
        exit 1
    }
else
    MOONRAKER_HOST="127.0.0.1"
fi

log "Display Manager started: mode=$MODE Moonraker=$MOONRAKER_HOST:7125"

[ -f "$SCREEN_FILE" ] || printf 'grumpy\n' > "$SCREEN_FILE"

read_screen() {
    VALUE="$(cat "$SCREEN_FILE" 2>/dev/null)"

    case "$VALUE" in
        grumpy|helix) printf '%s' "$VALUE" ;;
        *) printf 'grumpy' ;;
    esac
}

# Update only the host in the [moonraker] section of Grumpy.
prepare_grumpy() {
    if [ -d "$GRUMPY_CONFIG_DIR" ]; then
        if [ ! -f "$GRUMPY_CFG" ]; then
            cp "$GRUMPY_DEFAULT" "$GRUMPY_CFG" || return 1
        fi
        CFG="$GRUMPY_CFG"
    else
        CFG="$GRUMPY_DEFAULT"
    fi

    [ -f "$CFG" ] || {
        log "ERROR: Grumpy configuration not found"
        return 1
    }

    TMP="${CFG}.tmp"

    awk -v host="$MOONRAKER_HOST" '
        /^\[moonraker\][[:space:]]*$/ {
            section=1
            print
            next
        }

        /^\[/ { section=0 }

        section && /^[[:space:]]*host[[:space:]]*:/ {
            sub(/host:[[:space:]]*[^[:space:]#]+/, "host: " host)
            found=1
        }

        { print }

        END {
            if (!found)
                exit 2
        }
    ' "$CFG" > "$TMP"

    RESULT=$?

    if [ "$RESULT" -ne 0 ]; then
        rm -f "$TMP"
        log "ERROR: Host not found in Grumpy configuration"
        return 1
    fi

    mv "$TMP" "$CFG" || return 1

    log "Grumpy configuration updated: $CFG ($MOONRAKER_HOST)"
}

start_grumpy() {
    [ -x "$GRUMPY" ] || {
        log "ERROR: Grumpy executable not found"
        return 1
    }

    prepare_grumpy || return 1

    TOUCH="$(detect_touch)"

    (
        export LVGL_EVDEV_DEV="${TOUCH:-/dev/input/event2}"
        export CONFIG_FILE="$GRUMPY_CFG"
        exec "$GRUMPY"
    ) >> /tmp/grumpyscreen.log 2>&1 &

    DISPLAY_PID=$!
    DISPLAY_TYPE="grumpy"

    log "Grumpy started PID=$DISPLAY_PID"
}

is_descendant() {
    CHILD="$1"
    ROOT="$2"
    COUNT=0

    while [ "$CHILD" -gt 1 ] 2>/dev/null && [ "$COUNT" -lt 20 ]; do
        [ "$CHILD" = "$ROOT" ] && return 0

        STATUS="/proc/$CHILD/status"
        [ -r "$STATUS" ] || return 1

        PARENT=$(sed -n 's/^PPid:[[:space:]]*//p' "$STATUS")
        [ -n "$PARENT" ] || return 1

        CHILD="$PARENT"
        COUNT=$((COUNT + 1))
    done

    [ "$CHILD" = "$ROOT" ]
}

stop_stock_helix() {
    log "Searching for original Helix..."

    ROOTS=""

    for PROC in /proc/[0-9]*; do
        [ -d "$PROC" ] || continue
        PID=${PROC##*/}
        CMDLINE=$(tr '\000' ' ' < "$PROC/cmdline" 2>/dev/null)

        case "$CMDLINE" in
            *41-helixscreen.sh*)
                ROOTS="$ROOTS $PID"
                ;;
        esac
    done

    for ROOT_PID in $ROOTS; do
        PIDS="$ROOT_PID"

        for PROC in /proc/[0-9]*; do
            [ -d "$PROC" ] || continue
            PID=${PROC##*/}
            [ "$PID" = "$ROOT_PID" ] && continue

            CMDLINE=$(tr '\000' ' ' < "$PROC/cmdline" 2>/dev/null)

            case "$CMDLINE" in
                *helix-launcher*|*helix-watchdog*|*helix-screen*)
                    if is_descendant "$PID" "$ROOT_PID"; then
                        PIDS="$PIDS $PID"
                    fi
                    ;;
            esac
        done

        log "Stopping original Helix supervisor PID=$ROOT_PID"

        kill -TERM $PIDS 2>/dev/null
        sleep 2

        for PID in $PIDS; do
            if kill -0 "$PID" 2>/dev/null; then
                kill -KILL "$PID" 2>/dev/null
            fi
        done
    done
}

find_helix_watchdog() {
    TARGET_LAUNCHER="$1"

    for PROC in /proc/[0-9]*; do
        [ -d "$PROC" ] || continue
        PID=${PROC##*/}

        CMDLINE=$(tr '\000' ' ' < "$PROC/cmdline" 2>/dev/null)
        case "$CMDLINE" in
            *helix-watchdog*) ;;
            *) continue ;;
        esac

        PPID_VALUE=$(sed -n 's/^PPid:[[:space:]]*//p' "$PROC/status" 2>/dev/null)

        if [ "$PPID_VALUE" = "$TARGET_LAUNCHER" ]; then
            echo "$PID"
            return 0
        fi
    done

    return 1
}

start_helix() {
    stop_stock_helix

    log "Starting Helix with Moonraker $MOONRAKER_HOST:7125"

    "$HELIX_LAUNCHER" --moonraker "ws://$MOONRAKER_HOST:7125" &
    LAUNCHER_PID=$!

    WATCHDOG_PID=""

    COUNT=0
    while [ "$COUNT" -lt 10 ]; do
        WATCHDOG_PID=$(find_helix_watchdog "$LAUNCHER_PID")
        [ -n "$WATCHDOG_PID" ] && break
        sleep 1
        COUNT=$((COUNT + 1))
    done

    if [ -z "$WATCHDOG_PID" ]; then
        log "ERROR: Helix watchdog not found"
        kill -TERM "$LAUNCHER_PID" 2>/dev/null
        return 1
    fi

    DISPLAY_PID="$WATCHDOG_PID"
    DISPLAY_TYPE="helix"

    log "Helix started: watchdog PID=$DISPLAY_PID Moonraker=$MOONRAKER_HOST:7125"
    return 0
}

stop_display() {
    [ -n "$DISPLAY_PID" ] || return 0

    log "Stopping display $DISPLAY_TYPE PID=$DISPLAY_PID"

    if [ "$DISPLAY_TYPE" = "helix" ]; then
        kill -TERM "$DISPLAY_PID" 2>/dev/null

        COUNT=0
        while kill -0 "$DISPLAY_PID" 2>/dev/null && [ "$COUNT" -lt 5 ]; do
            sleep 1
            COUNT=$((COUNT + 1))
        done

        if kill -0 "$DISPLAY_PID" 2>/dev/null; then
            kill -KILL "$DISPLAY_PID" 2>/dev/null
        fi
    else
        kill -TERM "$DISPLAY_PID" 2>/dev/null
        sleep 2
        kill -KILL "$DISPLAY_PID" 2>/dev/null
    fi

    DISPLAY_PID=""
    DISPLAY_TYPE=""
}

start_display() {
    case "$1" in
        grumpy) start_grumpy ;;
        helix)  start_helix ;;
        *) return 1 ;;
    esac
}

cleanup() {
    STOPPING=1
    stop_display

    if [ "$(cat "$PID_FILE" 2>/dev/null)" = "$$" ]; then
        rm -f "$PID_FILE"
    fi

    log "Display Manager stopped"
    exit 0
}

trap cleanup INT TERM

while :; do

    DESIRED="$(read_screen)"

    if [ "$DESIRED" != "$CURRENT" ]; then

        stop_display

        CURRENT="$DESIRED"

        log "Display change: $CURRENT"

        if ! start_display "$CURRENT"; then
            log "Failed to start $CURRENT"
            sleep 3
        fi

    elif [ -z "$DISPLAY_PID" ] ||
         ! kill -0 "$DISPLAY_PID" 2>/dev/null; then

        if [ -n "$DISPLAY_PID" ]; then
            wait "$DISPLAY_PID" 2>/dev/null
            log "$CURRENT terminated"
            DISPLAY_PID=""
            DISPLAY_TYPE=""
        fi

        log "Restarting $CURRENT in 3 seconds"
        sleep 3

        [ "$STOPPING" = "1" ] && break

        DESIRED="$(read_screen)"

        [ "$DESIRED" = "$CURRENT" ] || continue

        if ! start_display "$CURRENT"; then
            log "Failed to restart $CURRENT"
        fi
    fi

    sleep 1
done

cleanup
