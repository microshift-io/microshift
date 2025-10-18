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
# https://kubernetes.io/blog/2023/10/10/cri-o-community-package-infrastructure/#deb-based-distributions
function install_crio() {
    source "${RPM_DIR}/deb/dependencies.txt"
    local crio_version="${CRIO_VERSION}"
    local relkey

    # Find the desired CRI-O package in the repository.
    # Fall back to the previous version if not found.
    local crio_found=false
    for _ in 1 2 3 ; do
        relkey="https://pkgs.k8s.io/addons:/cri-o:/stable:/v${crio_version}/deb/Release.key"
        if ! curl -fsSL "${relkey}" -o /dev/null 2>/dev/null ; then
            echo "Warning: The CRI-O package version '${crio_version}' not found in the repository. Trying the previous version."
            crio_version="$(awk -F. '{printf "%d.%d", $1, $2-1}' <<<"$crio_version")"
        else
            echo "Installing CRI-O package version '${crio_version}'"
            crio_found=true
            break
        fi
    done
    if ! "${crio_found}" ; then
        echo "Error: Failed to find the CRI-O package in the repository"
        exit 1
    fi

    # Set up the CRI-O repository
    local -r gpgkey="/etc/apt/keyrings/cri-o-${crio_version}-apt-keyring.gpg"
    rm -f "${gpgkey}"
    curl -fsSL "${relkey}" | gpg --batch --dearmor -o "${gpgkey}"
    echo "deb [signed-by=${gpgkey}] $(dirname "${relkey}") /" > \
        "/etc/apt/sources.list.d/cri-o-${crio_version}.list"

    # Install the CRI-O package and dependencies
    apt-get update  -y -q
    apt-get install -y -q cri-o crun containernetworking-plugins

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
