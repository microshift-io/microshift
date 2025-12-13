#!/bin/bash
#
# Install Sonobuoy for running CNCF conformance tests
#
# Usage: install_sonobuoy.sh [ARCH]
#   ARCH: CPU architecture (amd64 or arm64), defaults to auto-detection
#

set -euo pipefail

# Detect architecture if not provided
ARCH="${1:-}"
if [ -z "${ARCH}" ]; then
    case "$(uname -m)" in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        *)
            echo "ERROR: Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac
fi

# Install Sonobuoy
SONOBUOY_VERSION="0.57.3"
DOWNLOAD_URL="https://github.com/vmware-tanzu/sonobuoy/releases/download/v${SONOBUOY_VERSION}/sonobuoy_${SONOBUOY_VERSION}_linux_${ARCH}.tar.gz"

echo "Installing Sonobuoy ${SONOBUOY_VERSION} for ${ARCH}..."
wget -qO- "${DOWNLOAD_URL}" | tar xz
sudo mv sonobuoy /usr/local/bin/
sonobuoy version
echo "Sonobuoy installation completed successfully"
