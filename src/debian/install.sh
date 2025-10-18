#!/bin/bash
set -euo pipefail

function usage() {
    echo "Usage: $(basename "$0") <rpm_dir>"
    exit 1
}

function install_prereqs() {
    # Pre-install the required packages
    export DEBIAN_FRONTEND=noninteractive
    export TZ=Etc/UTC

    apt-get update  -y -q
    apt-get install -y -q tzdata curl gnupg1 policycoreutils sosreport
}

function configure_firewall() {
    apt-get install -y -q ufw

    ufw allow from 10.42.0.0/16
    ufw allow from 169.254.169.1

    # The 'enable' command may prompt for a confirmation
    echo y | ufw enable
    ufw reload
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
    apt-get install -y -q cri-o cri-tools cri-o-runc containernetworking-plugins

    # The containernetworking-plugins package is installed at /opt/cni/bin
    cat > /etc/crio/crio.conf.d/14-microshift-cni.conf <<EOF
[crio.network]
plugin_dirs = [
    "/opt/cni/bin",
]
EOF
    # Enable and start the CRI-O service
    systemctl daemon-reload
    systemctl enable crio
    systemctl restart crio
}

function install_microshift() {
    # Install the MicroShift Debian packages and fix the dependencies
    find "${RPM_DIR}" -type f -iname "microshift*.deb" | sort | while read -r deb_package; do
        dpkg -i "${deb_package}"
    done
    apt-get install -y -q -f

    # Enable and start the MicroShift services
    systemctl enable microshift
    systemctl restart --no-block microshift
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

install_prereqs
configure_firewall
install_crio
install_microshift
