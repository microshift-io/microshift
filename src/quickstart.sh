#!/bin/bash
set -euo pipefail

OWNER=microshift-io
REPO=microshift
BOOTC_ARCHIVE=""

LVM_DISK="/var/lib/microshift-okd/lvmdisk.image"
VG_NAME="myvg1"

TMPDIR="$(mktemp -d /tmp/microshift-okd-XXXXXX)"
trap 'rm -rf ${TMPDIR} &>/dev/null' EXIT

function download_bootc_image() {
    local -r filter="$1"

    pushd "${TMPDIR}" >/dev/null
    local -r url=$(curl -s https://api.github.com/repos/$OWNER/$REPO/releases/latest \
        | grep "browser_download_url" \
        | cut -d '"' -f 4 \
        | grep "${filter}")

    if [ -z "${url}" ]; then
        echo "ERROR: No packages found for '${filter}'"
        return 1
    fi

    echo "Downloading '${url}'"
    curl -L --progress-bar -O "${url}"
    popd >/dev/null

    BOOTC_ARCHIVE="${TMPDIR}/$(basename "${url}")"
}

function install_bootc_image() {
    local -r image_file="$1"

    echo "Installing '${image_file}'"
    podman load -q -i "${image_file}"
}

function prepare_lvm_disk() {
    local -r lvm_disk="$1"
    local -r vg_name="$2"

    if [ -f "${lvm_disk}" ]; then
        echo "INFO: '${lvm_disk}' already exists. Reusing it."
        return 0
    fi

    mkdir -p "$(dirname "${lvm_disk}")"
    truncate --size=1G "${lvm_disk}"
    losetup -f "${lvm_disk}"

    local -r device_name="$(losetup -j "${lvm_disk}" | cut -d: -f1)"
    vgcreate -f -y "${vg_name}" "${device_name}"
}

function run_bootc_image() {
    local -r image_name="$1"

    echo "Running '${image_name}'"
    modprobe openvswitch || true
    podman run --privileged --rm -d \
        --replace \
        --name microshift-okd \
  		--volume /dev:/dev:rslave \
        --hostname 127.0.0.1.nip.io \
        "${image_name}"
}

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Run the procedures
download_bootc_image "microshift-bootc-image-$(uname -m)"
install_bootc_image  "${BOOTC_ARCHIVE}"
prepare_lvm_disk     "${LVM_DISK}" "${VG_NAME}"
run_bootc_image      "localhost/microshift-okd:latest"

# Follow-up instructions
echo
echo "MicroShift is running in a bootc container"
echo "Hostname:  127.0.0.1.nip.io"
echo "Container: microshift-okd"
echo "LVM disk:  ${LVM_DISK}"
echo "VG name:   ${VG_NAME}"
echo
echo "To access the container, run the following command:"
echo " - sudo podman exec -it microshift-okd /bin/bash"
echo
echo "To verify that MicroShift pods are up and running, run the following command:"
echo " - sudo podman exec -it microshift-okd oc get pods -A"
echo
echo "To uninstall MicroShift, run the following command:"
echo " - curl -s https://raw.githubusercontent.com/${OWNER}/${REPO}/main/src/quickclean.sh | sudo bash"
