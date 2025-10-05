#!/bin/bash
set -euo pipefail

LVM_DISK="/var/lib/microshift-okd/lvmdisk.image"
VG_NAME="myvg1"

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

image_ref="$(podman inspect --format '{{.Image}}' microshift-okd)"

# Stop and remove the container
podman rm -f --time 0 microshift-okd || true

# Remove the image
podman rmi -f "${image_ref}" || true

# Remove the LVM disk
if [ -f "${LVM_DISK}" ]; then
    lvremove -y "${VG_NAME}" || true
    vgremove -y "${VG_NAME}" || true
    DEVICE_NAME="$(losetup -j "${LVM_DISK}" | cut -d: -f1)"
    # shellcheck disable=SC2086
    [ -n "${DEVICE_NAME}" ] && losetup -d ${DEVICE_NAME}
    rm -rf "$(dirname "${LVM_DISK}")"
fi
