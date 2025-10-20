#!/bin/bash
set -euo pipefail

function usage() {
    echo "Usage: $(basename "$0") <deb_dir>"
    exit 1
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

    ufw allow from 10.42.0.0/16
    ufw allow from 169.254.169.1
    ufw allow ssh

    # The 'enable' command may prompt for a confirmation
    echo y | ufw enable
    ufw reload
}

# Instructions for installing CRI-O:
# https://kubernetes.io/blog/2023/10/10/cri-o-community-package-infrastructure/#deb-based-distributions
function install_crio() {
    # shellcheck source=/dev/null
    source "${DEB_DIR}/dependencies.txt"
    local criver="${CRIO_VERSION}"
    local relkey

    # Find the desired CRI-O package in the repository.
    # Fall back to the previous version if not found.
    local crio_found=false
    for _ in 1 2 3 ; do
        relkey="https://pkgs.k8s.io/addons:/cri-o:/stable:/v${criver}/deb/Release.key"
        if ! curl -fsSL "${relkey}" -o /dev/null 2>/dev/null ; then
            echo "WARNING: The CRI-O package version '${criver}' not found in the repository. Trying the previous version."
            criver="$(awk -F. '{printf "%d.%d", $1, $2-1}' <<<"$criver")"
        else
            echo "Installing CRI-O package version '${criver}'"
            crio_found=true
            break
        fi
    done
    if [ "${crio_found}" != "true" ] ; then
        echo "ERROR: Failed to find the CRI-O package in the repository"
        exit 1
    fi

    # Set up the CRI-O repository
    local -r gpgkey="/etc/apt/keyrings/cri-o-${criver}-apt-keyring.gpg"
    rm -f "${gpgkey}"
    curl -fsSL "${relkey}" | gpg --batch --dearmor -o "${gpgkey}"
    echo "deb [signed-by=${gpgkey}] $(dirname "${relkey}") /" > \
        "/etc/apt/sources.list.d/cri-o-${criver}.list"

    # Install the CRI-O package and dependencies
    apt-get update  -y -q
    apt-get install -y -q cri-o crun containernetworking-plugins

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

function install_kubectl() {
    # shellcheck source=/dev/null
    source "${DEB_DIR}/dependencies.txt"
    local kubever="${CRIO_VERSION}"
    local relkey

    # Find the desired Kubectl package in the repository.
    # Fall back to the previous version if not found.
    local kubectl_found=false
    for _ in 1 2 3 ; do
        relkey="https://pkgs.k8s.io/core:/stable:/v${kubever}/deb/Release.key"
        if ! curl -fsSL "${relkey}" -o /dev/null 2>/dev/null ; then
            echo "WARNING: The kubectl package version '${kubever}' not found in the repository. Trying the previous version."
            kubever="$(awk -F. '{printf "%d.%d", $1, $2-1}' <<<"$kubever")"
        else
            echo "Installing kubectl package version '${kubever}'"
            kubectl_found=true
            break
        fi
    done

    if [ "${kubectl_found}" != "true" ] ; then
        echo "ERROR: Failed to find the kubectl package in the repository"
        exit 1
    fi

    # Set up the Kubernetes repository
    local -r gpgkey="/etc/apt/keyrings/kubernetes-${kubever}-apt-keyring.gpg"
    rm -f "${gpgkey}"
    curl -fsSL "${relkey}" | gpg --batch --dearmor -o "${gpgkey}"
    echo "deb [signed-by=${gpgkey}] $(dirname "${relkey}") /" > \
        "/etc/apt/sources.list.d/kubernetes-${kubever}.list"

    # Install the Kubectl package and dependencies
    apt-get update  -y -q
    apt-get install -y -q kubectl

    # Create a symlink to the kubectl command as 'oc'
    if [ ! -f /usr/bin/oc ] ; then
        ln -s "$(which kubectl)" /usr/bin/oc
    fi

    # Set the kubectl configuration
    if [ ! -f ~/.kube/config ] ; then
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
install_kubectl
# MicroShift
install_microshift
