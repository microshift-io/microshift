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
for rpm in $(find /mnt -type f -iname "*.rpm" -not -iname "*.src.rpm" | sort -u) ; do
    echo "Converting '${rpm}' to Debian package..."
    # Omit the --scripts option because some of them do not work on Ubuntu
    if ! alien --to-deb --keep-version "${rpm}" ; then
        echo "ERROR: Failed to convert '${rpm}' to Debian package"
        exit 1
    fi
    # Save cri-o dependency to a file
    crio_ver="$(rpm -qpR "${rpm}" | awk '/cri-o/ {print $3}' | sort -uV | head -1 | cut -d. -f1,2)"
    [ -n "${crio_ver}" ] && echo "CRIO_VERSION=${crio_ver}" >> "dependencies.txt"
done

rm -f /mnt/deb/microshift-networking*.deb
rm -f /mnt/deb/microshift-greenboot*.deb
EOF
