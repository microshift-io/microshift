#!/bin/bash
set -euo pipefail

LVM_DISK="/var/lib/microshift-okd/lvmdisk.image"
LVM_CONFIG="/etc/systemd/system/microshift.service.d/99-lvm-config.conf"
TOPOLVM_CONFIG="/etc/systemd/system/microshift.service.d/00-patch-lvmd.conf"
TOPOLVM_PATCH_SCRIPT="/usr/local/bin/patch_lvmd_config.sh"
TOPOLVM_PATCH_DIR="/etc/microshift/manifests.d/001-microshift-topolvm"
VG_NAME="${VG_NAME:-myvg1}"

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

    # Remove the LVM configuration
    if [ -f "${LVM_CONFIG}" ] ; then
        rm -f "${LVM_CONFIG}"
    fi

    # Remove the TopoLVM configuration
    rm -f "${TOPOLVM_CONFIG}"
    rm -f "${TOPOLVM_PATCH_SCRIPT}"
    rm -rf "${TOPOLVM_PATCH_DIR}"
    systemctl daemon-reload

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
