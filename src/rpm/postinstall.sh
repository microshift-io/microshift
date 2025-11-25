#!/bin/bash
set -euo pipefail
set -x

install_cni_plugins() {
    # If containernetworking-plugins is already installed, exit
    if rpm -q containernetworking-plugins &>/dev/null; then
        return 0
    fi

    # Set the package version and name
    CNP_VER=v1.8.0
    CNP_PKG="cni-plugins-linux-amd64-${CNP_VER}.tgz"
    [ "$(uname -m)" = "aarch64" ] && CNP_PKG="cni-plugins-linux-arm64-${CNP_VER}.tgz"

    # Download the package
    curl -sSL --retry 5 -o "/tmp/${CNP_PKG}" \
        "https://github.com/containernetworking/plugins/releases/download/${CNP_VER}/${CNP_PKG}"

    # Extract the package into the CNI plugins directory as defined
    # in the crio.conf.d/13-microshift-kindnet.conf file.
    mkdir -p /usr/libexec/cni
    tar zxvf "/tmp/${CNP_PKG}" -C /usr/libexec/cni && \

    # Clean up
    rm -f "/tmp/${CNP_PKG}"
}

#
# Main
#
# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Configure network and add some useful utilities
dnf install -y firewalld jq bash-completion
firewall-offline-cmd --zone=trusted --add-source=10.42.0.0/16
firewall-offline-cmd --zone=trusted --add-source=169.254.169.1
# Multinode clusters require connectivity on both apiserver and etcd
firewall-offline-cmd --zone=public --add-port=6443/tcp
firewall-offline-cmd --zone=public --add-port=2379/tcp
firewall-offline-cmd --zone=public --add-port=2380/tcp

# Configure limits for cAdvisor and kubelet
cat > /etc/sysctl.d/99-microshift.conf <<EOF
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 16384
EOF

# With kindnet present:
# - No need for openvswitch service which is enabled by default once MicroShift
#   is installed. Disable the service to avoid the need to configure it.
# - Need to disable systemd-resolved service to allow proper host name resolution
#   in Bootc containers running in privileged mode.
# - May need to install the containernetworking-plugins package from the package
#   GitHub release page (e.g. CentOS 10).
if rpm -q microshift-kindnet &>/dev/null; then
    systemctl disable openvswitch      &>/dev/null || true
    systemctl disable systemd-resolved &>/dev/null || true

    install_cni_plugins
fi

# Create a link to the default kubeconfig.
# Note that the /root directory may be a symlink to /var/roothome and the target
# directory may not exist, depending on the operating system.
if [ ! -f /root/.kube/config ] ; then
    mkdir -p "$(readlink -f /root)/.kube"
    ln -s /var/lib/microshift/resources/kubeadmin/kubeconfig /root/.kube/config
fi

# Enable the MicroShift service
systemctl enable microshift
