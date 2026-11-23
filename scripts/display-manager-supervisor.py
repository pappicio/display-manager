#!/usr/data/python-hf/bin/python3

# OC_RUNNER: persistent

import os
import signal
import subprocess
import time
from pathlib import Path

MANAGER = "/usr/data/opencreator/scripts/display-manager.sh.run"
PID_FILE = "/tmp/oc-display-manager-supervisor.pid"
LOG = "/tmp/oc-display-manager-supervisor.log"

STOP = False
child = None


def log(message):
    with open(LOG, "a") as f:
        f.write(time.strftime("%Y-%m-%d %H:%M:%S") + " " + message + "\n")


def get_processes():
    found = []

    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue

        pid = int(entry.name)
        if pid == os.getpid():
            continue

        try:
            cmd = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode(
                errors="replace"
            ).strip()
        except OSError:
            continue

        if not cmd:
            continue

        if (
            "display-manager.sh" in cmd
            or "40-grumpyscreen.sh" in cmd
            or "41-helixscreen.sh" in cmd
            or "/usr/data/grumpyscreen/grumpyscreen" in cmd
            or "/usr/data/helixscreen/bin/helix-launcher.sh" in cmd
            or "/usr/data/helixscreen/bin/helix-watchdog" in cmd
            or "/usr/data/helixscreen/bin/helix-screen" in cmd
            or "/usr/data/helixscreen/bin/helix-splash" in cmd
        ):
            found.append((pid, cmd))

    return found


def cleanup_displays():
    processes = get_processes()

    if not processes:
        log("Nessun processo residuo dei display")
        return

    for pid, cmd in processes:
        log("TERM PID={} {}".format(pid, cmd[:140]))
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        except OSError as exc:
            log("Errore TERM PID={}: {}".format(pid, exc))

    time.sleep(2)

    for pid, cmd in processes:
        try:
            os.kill(pid, 0)
            os.kill(pid, signal.SIGKILL)
            log("KILL PID={} {}".format(pid, cmd[:140]))
        except ProcessLookupError:
            pass
        except OSError:
            pass

    time.sleep(1)

    remaining = get_processes()
    if remaining:
        log("ATTENZIONE: processi ancora presenti: {}".format(
            [pid for pid, _ in remaining]
        ))
    else:
        log("Pulizia display completata")


def stop_handler(signum, frame):
    global STOP
    STOP = True


def process_matches(pid):
    try:
        cmd = Path("/proc/{}/cmdline".format(pid)).read_bytes()
        return b"display-manager-supervisor.py" in cmd
    except OSError:
        return False


def already_running():
    try:
        pid = int(Path(PID_FILE).read_text().strip())
        if pid != os.getpid() and process_matches(pid):
            log("Supervisor gia' attivo: PID={}".format(pid))
            return True
    except (ValueError, OSError):
        pass
    return False


def cleanup():
    global child

    if child is not None and child.poll() is None:
        log("Arresto Display Manager")
        child.terminate()
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()

    cleanup_displays()

    try:
        if Path(PID_FILE).read_text().strip() == str(os.getpid()):
            Path(PID_FILE).unlink()
    except OSError:
        pass

    log("Supervisor arrestato")


def main():
    global child

    if already_running():
        return

    Path(PID_FILE).write_text(str(os.getpid()))
    log("Supervisor avviato")

    try:
        while not STOP:
            if not os.path.isfile(MANAGER):
                log("ERRORE: Display Manager non trovato: " + MANAGER)
                time.sleep(5)
                continue

            log("Preparazione avvio Display Manager")
            cleanup_displays()

            with open(LOG, "a") as output:
                child = subprocess.Popen(
                    ["/opt/bin/sh", MANAGER],
                    stdout=output,
                    stderr=subprocess.STDOUT,
                    close_fds=True
                )

            log("Display Manager avviato PID={}".format(child.pid))

            while child.poll() is None and not STOP:
                time.sleep(1)

            if STOP:
                break

            rc = child.poll()
            log("Display Manager terminato: exit={}".format(rc))
            child = None

            cleanup_displays()
            time.sleep(3)

    finally:
        cleanup()


signal.signal(signal.SIGTERM, stop_handler)
signal.signal(signal.SIGINT, stop_handler)

main()
