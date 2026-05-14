#!/bin/bash
set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-microshift-okd}"
LVM_DISK="/var/lib/microshift-okd/lvmdisk.image"
LVM_CONFIG="/etc/systemd/system/microshift.service.d/99-lvm-config.conf"
VG_NAME="myvg1"

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Clean up the MicroShift container and image
image_ref="$(podman inspect --format '{{.Image}}' "${CONTAINER_NAME}" 2>/dev/null || true)"
if [ -n "${image_ref:-}" ]; then
    podman rm -f --time 0 "${CONTAINER_NAME}" || true
    podman rmi -f "${image_ref}" || true
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
    if [ -z "${SUDO_USER:-}" ]; then
        echo "ERROR: SUDO_USER is not set. Run this script with 'sudo', not as root directly."
        exit 1
    fi

    # macOS: clean up LVM inside the podman machine VM
    # Podman machine is per-user; run as the invoking user, not root
    sudo -u "${SUDO_USER}" podman machine ssh "
        if [ -f '${LVM_DISK}' ]; then
            sudo lvremove -y '${VG_NAME}' || true
            sudo vgremove -y '${VG_NAME}' || true
            DEVICE_NAME=\$(sudo losetup -j '${LVM_DISK}' | cut -d: -f1)
            [ -n \"\${DEVICE_NAME}\" ] && sudo losetup -d \${DEVICE_NAME}
            sudo rm -rf '$(dirname "${LVM_DISK}")'
        fi
    " </dev/null
else
    # Linux: clean up MicroShift data and uninstall RPMs
    if rpm -q microshift &>/dev/null ; then
        echo y | microshift-cleanup-data --all

        # Remove the LVM configuration
        if [ -f "${LVM_CONFIG}" ] ; then
            rm -f "${LVM_CONFIG}"
            systemctl daemon-reload
        fi

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
fi
