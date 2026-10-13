#!/bin/bash
# Keeps Mixxx running on the XDJ400 Pi. Started from the Openbox autostart
# (~/.config/openbox/autostart) in place of a bare "mixxx &", so a crash
# costs a few seconds instead of the rest of the set.
#
# Mixxx is relaunched only after it has been gone for MISSING_LIMIT
# consecutive checks. Hold-to-restart kills Mixxx and execs a new one itself
# within a fraction of a second, so it never looks missing for that long and
# the two never race into a second instance.
#
# Crashes land in the journal (journalctl -t mixxx-watchdog, and
# coredumpctl list mixxx for the core). Mixxx rotates its own log on start,
# so the crashed session's log is ~/.mixxx/mixxx.log.1.

CHECK_INTERVAL=1        # seconds between checks
MISSING_LIMIT=3         # checks Mixxx must be absent before a relaunch
BURST_WINDOW=120        # seconds
BURST_LIMIT=5           # launches within BURST_WINDOW before backing off
BACKOFF=30              # seconds to wait once the burst limit is hit

# One watchdog per session.
exec 9>"/tmp/mixxx-watchdog.$(id -u).lock"
if ! flock -n 9; then
    exit 0
fi

[ -n "$DISPLAY" ] || export DISPLAY=:0

log() {
    logger -t mixxx-watchdog -- "$*"
}

session_ending() {
    case "$(systemctl is-system-running 2>/dev/null)" in
        stopping) return 0 ;;
    esac
    # X is gone (logout or shutdown): nothing to show Mixxx on.
    local display="${DISPLAY#*:}"
    [ ! -S "/tmp/.X11-unix/X${display%%.*}" ]
}

mixxx_running() {
    pgrep -x -u "$(id -u)" mixxx >/dev/null
}

launches=()

launch() {
    local now
    now=$(date +%s)
    local recent=()
    for t in "${launches[@]}"; do
        if (( now - t < BURST_WINDOW )); then
            recent+=("$t")
        fi
    done
    launches=("${recent[@]}")
    if (( ${#launches[@]} >= BURST_LIMIT )); then
        log "Mixxx started ${#launches[@]} times in ${BURST_WINDOW}s; waiting ${BACKOFF}s"
        sleep "$BACKOFF"
        launches=()
        session_ending && exit 0
        mixxx_running && return
    fi
    launches+=("$(date +%s)")
    setsid mixxx </dev/null >/dev/null 2>&1 &
}

if ! mixxx_running; then
    log "starting Mixxx"
    launch
fi

missing=0
while sleep "$CHECK_INTERVAL"; do
    if mixxx_running; then
        missing=0
        continue
    fi
    missing=$((missing + 1))
    if (( missing < MISSING_LIMIT )); then
        continue
    fi
    session_ending && exit 0
    log "Mixxx is not running; restarting it"
    missing=0
    launch
done
