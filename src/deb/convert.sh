#!/bin/bash
set -euo pipefail

RPM2DEB_IMAGE="docker.io/library/ubuntu:24.04"

function usage() {
    echo "Usage: $(basename "$0") <rpm_dir>"
    exit 1
}

#
# Main
#
if [ $# -ne 1 ]; then
    usage
fi

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

RPM_DIR="$1"
if ! find "${RPM_DIR}" -type f -iname "microshift*.rpm" | grep -q "." ; then
    echo "ERROR: No MicroShift RPMs found in '${RPM_DIR}' directory"
    exit 1
fi

# Note that:
# - The OVN-K and Greenboot packages are not supported on Ubuntu
# - The MicroShift source RPM is ignored to avoid overwriting the binary RPM
echo "Converting the MicroShift RPMs to Debian packages"
podman run --rm -i \
    --volume "${RPM_DIR}:/mnt:Z" \
    "${RPM2DEB_IMAGE}" bash <<'EOF'
set -euo pipefail

apt-get update -y -q && apt-get install -y -qq alien

rm -rf /mnt/deb && mkdir -p /mnt/deb && cd /mnt/deb

CRIO_VERSIONS="$(mktemp)"
trap 'rm -f "${CRIO_VERSIONS}"' EXIT
for rpm in $(find /mnt -type f -iname "*.rpm" -not -iname "*.src.rpm" | sort -u) ; do
    echo "Converting '${rpm}' to Debian package..."
    # Omit the --scripts option because some of them do not work on Ubuntu
    if ! alien --to-deb --keep-version "${rpm}" ; then
        echo "ERROR: Failed to convert '${rpm}' to Debian package"
        exit 1
    fi
    # Collect the CRI-O dependency version of the package.
    #
    # Note that the 'cri-o' requirement follows the downstream OpenShift
    # versioning scheme (e.g. 'cri-o >= 5.1.0'), while the community packages
    # are versioned after the Kubernetes release they belong to (e.g. 1.36).
    # The 'cri-tools' requirement still uses the upstream versioning, so it is
    # the reliable source for the CRI-O and kubectl versions to install.
    #
    # Only the lower bound of the requirement is of interest. The upper bound
    # is exclusive ('cri-tools < 1.37.0'), so it denotes the first version that
    # must not be installed.
    rpm -qpR "${rpm}" | awk '$1 == "cri-tools" && ($2 == ">=" || $2 == "=") {print $3}' >> "${CRIO_VERSIONS}"
done

# The packages are installed together, so the version to install is the highest
# version any of them requires.
crio_ver="$(sort -uV "${CRIO_VERSIONS}" | tail -1 | cut -d. -f1,2)"
if [ -z "${crio_ver}" ] ; then
    echo "ERROR: No 'cri-tools' requirement found in the MicroShift packages"
    exit 1
fi
echo "CRIO_VERSION=${crio_ver}" > "dependencies.txt"

rm -f /mnt/deb/microshift-networking*.deb
rm -f /mnt/deb/microshift-greenboot*.deb
EOF
