#!/bin/bash
set -euo pipefail

function usage() {
    echo "Usage: $(basename "$0") <rpm_dir>"
    exit 1
}

# Instructions for installing CRI-O:
# https://computingforgeeks.com/install-cri-o-container-runtime-on-ubuntu-linux/
function install_crio() {
    local -r os_id="xUbuntu_20.04"
    local -r crio_version=1.28

    echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$os_id/ /" > \
        /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
    echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$crio_version/$os_id/ /" > \
        "/etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:${crio_version}.list"

    curl -L https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$crio_version/$os_id/Release.key | \
        apt-key add -
    curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$os_id/Release.key | \
        apt-key add -

    apt-get update  -y -q
    apt-get install -y -q cri-o cri-tools cri-o-runc
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
if ! find "${RPM_DIR}" -type f -iname "microshift*.deb" | grep -q "." ; then
    echo "Error: No MicroShift Debian packages found in '${RPM_DIR}' directory"
    exit 1
fi

# Pre-install the required packages
export DEBIAN_FRONTEND=noninteractive
export TZ=Etc/UTC

apt-get update  -y -q
apt-get install -y -q tzdata curl gnupg1 systemd policycoreutils

install_crio

# Install the MicroShift Debian packages and fix the dependencies
find "${RPM_DIR}" -type f -iname "microshift*.deb" | sort | while read -r deb_package; do
    dpkg -i "${deb_package}"
done
apt-get install -y -q -f
