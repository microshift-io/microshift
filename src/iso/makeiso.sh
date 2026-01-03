#!/bin/bash
set -euo pipefail

BIB_IMAGE="quay.io/centos-bootc/bootc-image-builder:latest"

usage() {
    echo "Usage: ${0} <local_bootc_image:tag> <iso_output_path>"
    exit 1
}

#
# Main
#

if [ $# -ne 2 ] ; then
    usage
fi

IMAGE_IN="${1}"
ISO_OUT="${2}"

if ! sudo podman image exists "${IMAGE_IN}" ; then
    echo "ERROR: '${IMAGE_IN}' is not a valid image"
    exit 1
fi

if [ ! -d "${ISO_OUT}" ] ; then
    echo "ERROR: '${ISO_OUT}' is not a directory"
    exit 1
fi

echo "Creating ISO image from '${IMAGE_IN}'"
echo "Output ISO path: '${ISO_OUT}'"

# Pull the bootc image builder image
sudo podman pull "${BIB_IMAGE}"

# Create the ISO image
sudo podman run --rm -i \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    -v "${ISO_OUT}:/output" \
    "${BIB_IMAGE}" \
    --type anaconda-iso \
    "${IMAGE_IN}"

ISO_FILE="$(find "${ISO_OUT}" -name "install.iso")"
if [ -z "${ISO_FILE}" ] ; then
    echo "ERROR: ISO image not found in '${ISO_OUT}'"
    exit 1
fi

# Exit with the status of the ISO image creation
echo "ISO image created at '${ISO_FILE}'"
