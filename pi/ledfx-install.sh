#!/bin/bash
# One-time LedFx setup for the XDJ400 Pi (safe to re-run).
#
#   sudo ./ledfx-install.sh
#
# Run from a checkout/copy of the pi/ directory (it installs the files next to
# it). It sets up:
#   * the ALSA loopback (snd-aloop as card 10, "Loopback"), loaded at boot;
#   * LedFx in its own venv at /opt/ledfx (built with uv), so the system
#     Python's packages are never touched;
#   * the "ledfx" systemd service (web UI on port 8888, niced, one core);
#   * a passwordless sudo rule so the settings menu's LEDS button can start
#     and stop the service.
# Mixxx's Booth output and the LedFx devices are then set by hand once; the
# steps are printed at the end.
set -euo pipefail

# LedFx 2.2 supports Python 3.11-3.14, so trixie's own 3.13 does; uv uses
# the system interpreter when it matches and downloads one otherwise.
LEDFX_PYTHON="3.13"

if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi
LEDFX_USER="${SUDO_USER:-rpims}"
if ! getent passwd "$LEDFX_USER" >/dev/null; then
    echo "ERROR: unknown user '$LEDFX_USER'" >&2
    exit 1
fi
HERE="$(cd "$(dirname "$0")" && pwd)"

# --- ALSA loopback -----------------------------------------------------------
echo "==> ALSA loopback (snd-aloop, card 10)"
install -m 644 "$HERE/ledfx-snd-aloop.conf" /etc/modprobe.d/ledfx-snd-aloop.conf
echo snd-aloop > /etc/modules-load.d/ledfx-snd-aloop.conf
modprobe snd-aloop
if ! grep -q '^10 \[Loopback' /proc/asound/cards; then
    echo "WARNING: Loopback is not card 10 (was snd-aloop already loaded with" \
         "other options?). Reboot and re-check 'aplay -l'." >&2
fi

# --- LedFx -------------------------------------------------------------------
echo "==> Build dependencies"
apt-get install -y --no-install-recommends \
    curl ca-certificates build-essential python3-dev \
    libportaudio2 portaudio19-dev libasound2-dev

echo "==> uv"
if ! command -v uv >/dev/null && [[ ! -x /usr/local/bin/uv ]]; then
    curl -LsSf https://astral.sh/uv/install.sh \
        | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh
fi
UV="$(command -v uv || echo /usr/local/bin/uv)"

echo "==> LedFx venv at /opt/ledfx (Python $LEDFX_PYTHON)"
export UV_PYTHON_INSTALL_DIR=/opt/uv-python
if [[ ! -x /opt/ledfx/bin/python ]]; then
    "$UV" venv --python "$LEDFX_PYTHON" /opt/ledfx
fi
"$UV" pip install --python /opt/ledfx/bin/python --upgrade ledfx
/opt/ledfx/bin/ledfx --version || true

# --- Service -----------------------------------------------------------------
echo "==> systemd service (User=$LEDFX_USER)"
sed "s/@USER@/$LEDFX_USER/" "$HERE/ledfx.service" > /etc/systemd/system/ledfx.service
chmod 644 /etc/systemd/system/ledfx.service
# Capture devices are group "audio"; the login user normally is in it already.
usermod -aG audio "$LEDFX_USER"
systemctl daemon-reload
systemctl enable ledfx
systemctl restart ledfx

# --- LEDS button -------------------------------------------------------------
# The settings menu's LEDS button runs "sudo -n systemctl start|stop ledfx"
# from Mixxx, which runs as the login user.
echo "==> sudoers rule for the LEDS button"
SUDOERS_TMP="$(mktemp)"
cat > "$SUDOERS_TMP" <<EOF
# Pioneered: LEDS button in the settings menu (pi/ledfx-install.sh)
$LEDFX_USER ALL=(root) NOPASSWD: /usr/bin/systemctl start ledfx, /usr/bin/systemctl stop ledfx
EOF
if visudo -cf "$SUDOERS_TMP" >/dev/null; then
    install -m 440 "$SUDOERS_TMP" /etc/sudoers.d/pioneered-ledfx
else
    echo "ERROR: generated sudoers rule failed visudo -c; not installed" >&2
fi
rm -f "$SUDOERS_TMP"

HOST="$(hostname)"
cat <<EOF

==> Done. LedFx is $(systemctl is-active ledfx).

One-time setup left:
  1. Mixxx > Preferences > Sound Hardware > Output:
       Booth = "Loopback: PCM (hw:10,0)", channels 1-2. Leave the DDJ-400 as
       the clock reference and the sample rate at 44100 Hz. Apply.
  2. From a computer on the same network open  http://$HOST.local:8888
       Settings > Audio Device: the Loopback capture device (hw:10,1)
       Devices > Add Device > WLED (found automatically, or enter its IP)
       Pick an effect for the device.
  3. The settings menu's LEDS button (green = running and online) needs a
     Pioneered Mixxx build with ledfx-status.patch.
EOF
