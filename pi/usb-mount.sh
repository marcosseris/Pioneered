#!/bin/bash
# Mounts a USB partition at the first free slot of /media/USBA, /media/USBB.
# Invoked by usb-mount@.service (see 99-usb-automount.rules).
#
# Slot selection is serialized with flock: two sticks inserted simultaneously
# (e.g. both present at boot) race their usb-mount@ instances, both used to
# see USBA free and both mounted there -- the second mount silently stacked
# on top of the first, shadowing it, and /media/USBB was never used.
DEVICE="$1"
[ -z "$DEVICE" ] && { echo "Usage: $0 <device>" >&2; exit 1; }

MOUNT_POINTS=("/media/USBA" "/media/USBB")

for mp in "${MOUNT_POINTS[@]}"; do
    mkdir -p "$mp"
done

exec 9>/run/lock/usb-mount.lock
flock 9

# Already mounted? nothing to do
if findmnt -S "/dev/$DEVICE" >/dev/null 2>&1; then
    echo "/dev/$DEVICE already mounted"
    exit 0
fi

# Mount options. FAT sticks -- what rekordbox exports to -- additionally get
# utf8=1: without it the kernel presents filenames in its default charset
# (iso8859-1 or ascii on Pi kernels), so a title with an accented character
# ("La Mamá") is not the UTF-8 name rekordbox wrote into export.pdb, Mixxx
# cannot find the file, and LOAD silently does nothing for that track. exFAT,
# NTFS and HFS+ already default to UTF-8 names and take no such option.
OPTS="uid=1000,gid=1000,umask=022"
FSTYPE="$(blkid -o value -s TYPE "/dev/$DEVICE" 2>/dev/null)"
case "$FSTYPE" in
    vfat|msdos) OPTS="$OPTS,utf8=1" ;;
esac

for mp in "${MOUNT_POINTS[@]}"; do
    if ! mountpoint -q "$mp"; then
        if mount -o "$OPTS" "/dev/$DEVICE" "$mp"; then
            echo "Mounted /dev/$DEVICE at $mp"
            exit 0
        fi
        echo "Failed to mount /dev/$DEVICE at $mp, trying next slot" >&2
    fi
done

echo "No available mount point for /dev/$DEVICE" >&2
exit 1
