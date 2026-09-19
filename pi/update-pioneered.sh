#!/bin/bash
# One-shot Pioneered updater for the XDJ400 Pi.
#
#   sudo ./update-pioneered.sh              # install the latest GitHub release
#   sudo ./update-pioneered.sh v2.5.0-r18   # install a specific release (also allows rollback)
#   sudo ./update-pioneered.sh --no-reboot  # install, but leave rebooting to the caller
#
# Fetches the release's three Mixxx debs and the matching skin from GitHub,
# installs them non-interactively, re-holds the packages, refreshes the pi/
# helper layer, then reboots (Ctrl-C during the countdown to skip the reboot).
#
# --no-reboot is what the settings menu's UPDATE button uses: it runs this
# script and shows the output on screen, then offers a RESTART button, since
# there is no terminal there to press Ctrl-C in.
set -euo pipefail

# The repository was renamed from ogg755/Pioneered; GitHub still redirects the
# old name, but a redirect only lasts until someone else claims it, and every
# release this script installs comes through here.
REPO="marcosseris/Pioneered"

# Root is needed for apt; the skin belongs to the login user.
if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@"
fi
SKIN_USER="${SUDO_USER:-rpims}"
SKIN_HOME="$(getent passwd "$SKIN_USER" | cut -d: -f6)"
if [[ -z "$SKIN_HOME" ]]; then
    echo "ERROR: cannot resolve home directory for user '$SKIN_USER'" >&2
    exit 1
fi

WORKDIR="$(mktemp -d /tmp/pioneered-update.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

# --- Arguments ---------------------------------------------------------------
NO_REBOOT=0
TAG=""
for arg in "$@"; do
    case "$arg" in
        --no-reboot) NO_REBOOT=1 ;;
        -h|--help)
            sed -n '2,12p' "$0"
            exit 0
            ;;
        -*)
            echo "ERROR: unknown option '$arg'" >&2
            exit 2
            ;;
        *)
            if [[ -n "$TAG" ]]; then
                echo "ERROR: more than one release given ('$TAG', '$arg')" >&2
                exit 2
            fi
            TAG="$arg"
            ;;
    esac
done

# --- Resolve release ---------------------------------------------------------
if [[ -n "$TAG" ]]; then
    API_URL="https://api.github.com/repos/$REPO/releases/tags/$TAG"
else
    API_URL="https://api.github.com/repos/$REPO/releases/latest"
fi
echo "==> Querying $API_URL"
curl -fsSL "$API_URL" -o release.json

TAG="$(grep -m1 -o '"tag_name": *"[^"]*"' release.json | sed 's/.*: *"//;s/"//')"
if [[ -z "$TAG" ]]; then
    echo "ERROR: could not resolve a release (no tag_name in API response)" >&2
    exit 1
fi
echo "==> Release: $TAG"

mapfile -t DEB_URLS < <(grep -o '"browser_download_url": *"[^"]*\.deb"' release.json \
        | sed 's/.*: *"//;s/"//')
if [[ ${#DEB_URLS[@]} -lt 3 ]]; then
    echo "ERROR: release $TAG has ${#DEB_URLS[@]} .deb assets (expected 3:" \
         "mixxx, mixxx-data, mixxx-dbgsym). Was the release published with debs attached?" >&2
    exit 1
fi

# --- Download ----------------------------------------------------------------
for url in "${DEB_URLS[@]}"; do
    echo "==> Downloading ${url##*/}"
    curl -fL --retry 3 -o "${url##*/}" "$url"
done

echo "==> Downloading skin source for $TAG"
curl -fL --retry 3 -o skin.tar.gz "https://github.com/$REPO/archive/refs/tags/$TAG.tar.gz"
tar -xzf skin.tar.gz          # extracts to Pioneered-<tag without v>/
SKIN_SRC="$(find . -maxdepth 1 -type d -name 'Pioneered-*' | head -1)"
if [[ -z "$SKIN_SRC" || ! -f "$SKIN_SRC/skin.xml" ]]; then
    echo "ERROR: skin source missing skin.xml after extraction" >&2
    exit 1
fi

# --- Install debs ------------------------------------------------------------
echo "==> Installing Mixxx packages"
apt-mark unhold mixxx mixxx-data mixxx-dbgsym 2>/dev/null || true
DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades \
    "$WORKDIR"/mixxx_*_arm64.deb \
    "$WORKDIR"/mixxx-data_*_all.deb \
    "$WORKDIR"/mixxx-dbgsym_*_arm64.deb
apt-mark hold mixxx mixxx-data mixxx-dbgsym 2>/dev/null || true

# --- Install skin ------------------------------------------------------------
echo "==> Installing skin to $SKIN_HOME/.mixxx/skins/Pioneered"
mkdir -p "$SKIN_HOME/.mixxx/skins"
rm -rf "$SKIN_HOME/.mixxx/skins/Pioneered"
cp -r "$SKIN_SRC" "$SKIN_HOME/.mixxx/skins/Pioneered"
chown -R "$SKIN_USER:" "$SKIN_HOME/.mixxx/skins/Pioneered"

# --- Install USB auto-mount layer -------------------------------------------
# The mount script carries fixes of its own (r28: UTF-8 filenames on FAT
# sticks), so keep the installed copies in step with the release. Idempotent;
# the reboot below remounts any stick with the new options.
echo "==> Installing USB auto-mount layer"
install -m 755 "$SKIN_SRC/pi/usb-mount.sh" "$SKIN_SRC/pi/usb-umount.sh" /usr/local/bin/
install -m 644 "$SKIN_SRC/pi/99-usb-automount.rules" /etc/udev/rules.d/
install -m 644 "$SKIN_SRC/pi/usb-mount@.service" /etc/systemd/system/
udevadm control --reload
systemctl daemon-reload

# --- Install this script ------------------------------------------------------
# So /usr/local/bin/update-pioneered.sh is always the newest one, and the
# settings menu's UPDATE button has a fixed path to call.
#
# Written to a temp file and renamed rather than copied over: this script may
# BE /usr/local/bin/update-pioneered.sh, and bash reads a script as it runs.
# Overwriting it in place would feed the running shell the tail of the new
# file at the old offset. A rename leaves the open inode alone.
echo "==> Installing the updater to /usr/local/bin/update-pioneered.sh"
SELF_TMP="$(mktemp /usr/local/bin/.update-pioneered.XXXXXX)"
cat "$SKIN_SRC/pi/update-pioneered.sh" > "$SELF_TMP"
chmod 755 "$SELF_TMP"
mv -f "$SELF_TMP" /usr/local/bin/update-pioneered.sh

# --- Report + reboot ---------------------------------------------------------
echo
echo "==> Installed: $(dpkg-query -W -f='${Package} ${Version}\n' mixxx)"
echo "==> Skin updated from release $TAG"
echo
if [[ $NO_REBOOT -eq 1 ]]; then
    echo "Not rebooting (--no-reboot). Restart to finish the update."
    exit 0
fi
echo "Rebooting in 10 seconds so Mixxx restarts on the new build."
echo "Press Ctrl-C to skip the reboot (then restart Mixxx yourself)."
sleep 10
reboot
