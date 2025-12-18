#!/bin/bash
set -euo pipefail

function usage() {
    echo "Usage: $(basename "$0") <deb_dir>"
    exit 1
}

# Helper function to determine the latest available version of a DEB package
# by trying descending patch/minor versions from an initial version.
#
# Inspired by:
# https://kubernetes.io/blog/2023/10/10/cri-o-community-package-infrastructure/#deb-based-distributions
#
# Arguments:
#   - debpkg (for reporting, e.g., "cri-o" or "kubectl")
#   - version (initial full version string, e.g., "1.28")
#   - relkey_base (base URL, e.g., "https://pkgs.k8s.io/addons:/cri-o:/stable:")
# Returns:
#   - Echoes the found version to stdout
#   - Exits with an error if the package is not found
function find_debpkg_version() {
    local debpkg="$1"
    local version="$2"
    local relkey_base="$3"

    for _ in 1 2 3 ; do
        local relkey
        relkey="${relkey_base}/v${version}/deb/Release.key"
        if ! curl -fsSL "${relkey}" -o /dev/null 2>/dev/null ; then
            echo "WARNING: The ${debpkg} package version '${version}' not found in the repository. Trying the previous version." >&2
            # Decrement the minor version component
            local xver="${version%%.*}"
            local yver="${version#*.}"
            if [ "${yver}" -lt 1 ] ; then
                echo "ERROR: The minor version component cannot be decremented below 0" >&2
                break
            fi
            version="${xver}.$(( yver - 1 ))"
        else
            echo "Found '${debpkg}' package version '${version}'" >&2
            echo "${version}"
            return
        fi
    done

    echo "ERROR: Failed to find the '${debpkg}' package in the repository" >&2
    exit 1
}

# Generic function for installing a DEB package from a repository.
#
# Inspired by:
# https://kubernetes.io/blog/2023/10/10/cri-o-community-package-infrastructure/#deb-based-distributions
#
# Arguments:
#   - debpkg: Name of the main package to install (single package)
#   - version: Version string of the package (e.g., "1.28")
#   - relkey: URL to the repository Release.key (GPG key)
#   - extra_packages: Additional package names to pass to apt-get install (optional)
# Returns:
#   - None
function install_debpkg() {
    local debpkg="$1"
    local version="$2"
    local relkey="$3"
    local extra_packages="${4:-}"

    local -r outname="${debpkg}-${version}"
    local -r gpgkey="/etc/apt/keyrings/${outname}-apt-keyring.gpg"

    # Download the GPG key and add it to the keyring
    rm -f "${gpgkey}"
    curl -fsSL "${relkey}" | gpg --batch --dearmor -o "${gpgkey}"

    # Add the repository to the sources.list.d directory
    echo "deb [signed-by=${gpgkey}] $(dirname "${relkey}") /" > \
        "/etc/apt/sources.list.d/${outname}.list"

    # Install the package and its dependencies
    apt-get update  -y -q
    # shellcheck disable=SC2086
    apt-get install -y -q --allow-downgrades "${debpkg}=${version}*" ${extra_packages}
}

function install_prereqs() {
    # Pre-install the required packages
    export DEBIAN_FRONTEND=noninteractive
    export TZ=Etc/UTC

    apt-get update  -y -q
    apt-get install -y -q tzdata curl gnupg1 policycoreutils sosreport
}

function install_firewall() {
    apt-get install -y -q ufw

    ufw route allow from 10.42.0.0/16
    ufw allow from 10.42.0.0/16
    ufw allow from 169.254.169.1
    ufw allow ssh

    # The 'enable' command may prompt for a confirmation
    echo y | ufw enable
    ufw reload
}

function install_crio() {
    # shellcheck source=/dev/null
    source "${DEB_DIR}/dependencies.txt"

    # Find the desired CRI-O package in the repository
    local -r pkgver="$(find_debpkg_version "cri-o" "${CRIO_VERSION}" "https://pkgs.k8s.io/addons:/cri-o:/stable:")"
    # Install the package of the found version and its dependencies
    local -r relkey="https://pkgs.k8s.io/addons:/cri-o:/stable:/v${pkgver}/deb/Release.key"
    install_debpkg "cri-o" "${pkgver}" "${relkey}" "crun containernetworking-plugins"

    # Disable all CNI plugin configuration files to allow Kindnet override
    find /etc/cni/net.d -name '*.conflist' -print 2>/dev/null | while read -r cl ; do
        mv "${cl}" "${cl}.disabled"
    done

    # Query the containernetworking-plugins package installation directory
    # and update the CRI-O configuration file to use it
    local -r cni_dir="$(dpkg -L containernetworking-plugins | grep -E '/portmap$' | tail -1 | xargs dirname)"
    cat > /etc/crio/crio.conf.d/14-microshift-cni.conf <<EOF
[crio.network]
plugin_dirs = [
    "${cni_dir}",
]
EOF
    # Enable and start the CRI-O service
    systemctl daemon-reload
    systemctl enable crio
    systemctl restart crio
}

function install_ctl_tools() {
    # shellcheck source=/dev/null
    source "${DEB_DIR}/dependencies.txt"

    # Find the desired kubectl package in the repository
    local -r pkgver="$(find_debpkg_version "kubectl" "${CRIO_VERSION}" "https://pkgs.k8s.io/core:/stable:")"
    # Install the package of the found version and its dependencies
    local -r relkey="https://pkgs.k8s.io/core:/stable:/v${pkgver}/deb/Release.key"
    install_debpkg "kubectl" "${pkgver}" "${relkey}" cri-tools

    # Create a symlink to the kubectl command as 'oc'
    if [ ! -f /usr/bin/oc ] ; then
        ln -s "$(which kubectl)" /usr/bin/oc
    fi

    # Set the kubectl configuration
    if [ ! -e ~/.kube/config ] && [ ! -L ~/.kube/config ] ; then
        mkdir -p ~/.kube
        ln -s /var/lib/microshift/resources/kubeadmin/kubeconfig ~/.kube/config
    fi
}

function install_microshift() {
    # Install the MicroShift Debian packages and fix the dependencies
    find "${DEB_DIR}" -maxdepth 1 -name 'microshift*.deb' -print 2>/dev/null | sort | while read -r deb_package; do
        dpkg -i "${deb_package}"
    done
    apt-get install -y -q -f

    # Enable the MicroShift service
    systemctl enable microshift
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

DEB_DIR="$1"
if ! find "${DEB_DIR}" -maxdepth 1 -name 'microshift*.deb' -print 2>/dev/null | grep -q . ; then
    echo "ERROR: No MicroShift Debian packages found in '${DEB_DIR}' directory"
    exit 1
fi
if ! [ -f "${DEB_DIR}/dependencies.txt" ] ; then
    echo "ERROR: No dependencies.txt file found in '${DEB_DIR}' directory"
    exit 1
fi

# System setup
install_prereqs
install_firewall
# Prerequisites
install_crio
install_ctl_tools
# MicroShift
install_microshift
