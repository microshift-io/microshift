#!/bin/bash
set -euo pipefail
set -x

# If containernetworking-plugins is already installed, exit
if rpm -q containernetworking-plugins &>/dev/null; then
    exit 0
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
