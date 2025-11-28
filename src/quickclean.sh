#!/bin/bash
set -euo pipefail

LVM_DISK="/var/lib/microshift-okd/lvmdisk.image"
VG_NAME="myvg1"

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Clean up the MicroShift container and image
image_ref="$(podman inspect --format '{{.Image}}' microshift-okd 2>/dev/null || true)"
if [ -n "${image_ref:-}" ]; then
    podman rm -f --time 0 microshift-okd || true
    podman rmi -f "${image_ref}" || true
fi

# Clean up the MicroShift data and uninstall RPMs
if rpm -q microshift &>/dev/null ; then
    echo y | microshift-cleanup-data --all
    dnf remove -y 'microshift*'
    # Undo post-installation configuration
    rm -f /etc/sysctl.d/99-microshift.conf
    rm -f /root/.kube/config
fi

# Remove the LVM disk
if [ -f "${LVM_DISK}" ]; then
    lvremove -y "${VG_NAME}" || true
    vgremove -y "${VG_NAME}" || true
    DEVICE_NAME="$(losetup -j "${LVM_DISK}" | cut -d: -f1)"
    # shellcheck disable=SC2086
    [ -n "${DEVICE_NAME}" ] && losetup -d ${DEVICE_NAME}
    rm -rf "$(dirname "${LVM_DISK}")"
fi
