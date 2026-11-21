
#!/opt/bin/sh

OPENCREATOR="/usr/data/opencreator"
SCREEN_FILE="$OPENCREATOR/screen"
PID_FILE="/tmp/oc-display-manager.pid"

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

# Evita istanze multiple.
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

# Modalità rilevata una sola volta.
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

if [ "$MODE" = "tunneled" ]; then
    MOONRAKER_HOST="192.168.1.197"
else
    MOONRAKER_HOST="127.0.0.1"
fi

log "Avvio Display Manager: modalità=$MODE Moonraker=$MOONRAKER_HOST:7125"

[ -f "$SCREEN_FILE" ] || printf 'grumpy\n' > "$SCREEN_FILE"

read_screen() {
    VALUE="$(cat "$SCREEN_FILE" 2>/dev/null)"

    case "$VALUE" in
        grumpy|helix) printf '%s' "$VALUE" ;;
        *) printf 'grumpy' ;;
    esac
}

# Aggiorna esclusivamente host nella sezione [moonraker] di Grumpy.
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
        log "ERRORE: configurazione Grumpy non trovata"
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
        log "ERRORE: host non trovato nella configurazione Grumpy"
        return 1
    fi

    mv "$TMP" "$CFG" || return 1

    log "Configurazione Grumpy aggiornata: $CFG ($MOONRAKER_HOST)"
}

start_grumpy() {
    [ -x "$GRUMPY" ] || {
        log "ERRORE: eseguibile Grumpy non trovato"
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

    log "Grumpy avviato PID=$DISPLAY_PID"
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
    log "Ricerca Helix originale..."

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

        log "Arresto Helix originale: supervisore PID=$ROOT_PID"

        kill -TERM $PIDS 2>/dev/null
        sleep 2

        for PID in $PIDS; do
            if kill -0 "$PID" 2>/dev/null; then
                kill -KILL "$PID" 2>/dev/null
            fi
        done
    done
}

start_helix() {
    stop_stock_helix

    log "Avvio Helix con Moonraker $MOONRAKER_HOST:7125"

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
        log "ERRORE: watchdog Helix non trovato"
        kill -TERM "$LAUNCHER_PID" 2>/dev/null
        return 1
    fi

    DISPLAY_PID="$WATCHDOG_PID"
    DISPLAY_TYPE=helix

    log "Helix avviato: watchdog PID=$DISPLAY_PID Moonraker=$MOONRAKER_HOST:7125"
    return 0
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

stop_display() {
    [ -n "$DISPLAY_PID" ] || return 0

    log "Arresto display $DISPLAY_TYPE PID=$DISPLAY_PID"

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

    log "Display Manager arrestato"
    exit 0
}

trap cleanup INT TERM

while :; do

    DESIRED="$(read_screen)"

    if [ "$DESIRED" != "$CURRENT" ]; then

        stop_display

        CURRENT="$DESIRED"

        log "Cambio display: $CURRENT"

        if ! start_display "$CURRENT"; then
            log "Errore avvio $CURRENT"
            sleep 3
        fi

    elif [ -z "$DISPLAY_PID" ] ||
         ! kill -0 "$DISPLAY_PID" 2>/dev/null; then

        if [ -n "$DISPLAY_PID" ]; then
            wait "$DISPLAY_PID" 2>/dev/null
            log "$CURRENT terminato"
            DISPLAY_PID=""
            DISPLAY_TYPE=""
        fi

        log "Riavvio $CURRENT tra 3 secondi"
        sleep 3

        [ "$STOPPING" = "1" ] && break

        DESIRED="$(read_screen)"

        [ "$DESIRED" = "$CURRENT" ] || continue

        if ! start_display "$CURRENT"; then
            log "Errore riavvio $CURRENT"
        fi
    fi

    sleep 1
done

cleanup
