#!/bin/bash
set -euo pipefail

OWNER=${OWNER:-microshift-io}
REPO=${REPO:-microshift}
TAG=${TAG:-latest}
IMAGE_REF="ghcr.io/${OWNER}/${REPO}:${TAG}"

LVM_DISK="/var/lib/microshift-okd/lvmdisk.image"
VG_NAME="myvg1"

function pull_bootc_image() {
    local -r image_ref="$1"

    echo "Pulling '${image_ref}'"
    podman pull "${image_ref}"
}

function prepare_lvm_disk() {
    local -r lvm_disk="$1"
    local -r vg_name="$2"

    if [ -f "${lvm_disk}" ]; then
        echo "INFO: '${lvm_disk}' already exists. Clearing and reusing it."
        dd if=/dev/zero of="${lvm_disk}" bs=1M count=100 >/dev/null
        return 0
    fi

    mkdir -p "$(dirname "${lvm_disk}")"
    truncate --size=1G "${lvm_disk}"

    local -r device_name="$(losetup --find --show --nooverlap "${lvm_disk}")"
    vgcreate -f -y "${vg_name}" "${device_name}"
}

function run_bootc_image() {
    local -r image_ref="$1"

    # Prerequisites for running the MicroShift container:
    # - If the OVN-K CNI driver is used (`WITH_KINDNET=0` non-default image build
    #   option), the `openvswitch` module must be loaded on the host.
    # - If the TopoLVM CSI driver is used (`WITH_TOPOLVM=1` default image build
    #   option), the /dev/dm-* device must be shared with the container.
    echo "Running '${image_ref}'"
    modprobe openvswitch || true

    # Share the /dev directory with the container to enable TopoLVM CSI driver.
    # Mask the devices that may conflict with the host by sharing them on a
    # temporary file system. Note that a pseudo-TTY is also allocated to
    # prevent the container from using host consoles.
    local vol_opts="--tty --volume /dev:/dev"
    for device in input snd dri; do
        [ -d "/dev/${device}" ] && vol_opts="${vol_opts} --tmpfs /dev/${device}"
    done
    # shellcheck disable=SC2086
    podman run --privileged --rm -d \
        --replace \
        ${vol_opts} \
        --name microshift-okd \
        --hostname 127.0.0.1.nip.io \
        "${image_ref}"

    echo "Waiting for MicroShift to start"
    local -r kubeconfig="/var/lib/microshift/resources/kubeadmin/kubeconfig"
    while true ; do
        if podman exec microshift-okd /bin/test -f "${kubeconfig}" &>/dev/null ; then
            break
        fi
        sleep 1
    done
}

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Run the procedures
pull_bootc_image     "${IMAGE_REF}"
prepare_lvm_disk     "${LVM_DISK}" "${VG_NAME}"
run_bootc_image      "${IMAGE_REF}"

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
echo " - curl -s https://${OWNER}.github.io/${REPO}/quickclean.sh | sudo bash"
