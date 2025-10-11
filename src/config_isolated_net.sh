#!/bin/bash
set -euo pipefail
set -x

configure_kindnet() {
  # TODO: Add support for isolated network with MicroShift Kindnet
  echo "Error: Isolated network is not supported with MicroShift Kindnet"
  exit 1
}

# See the following for more information:
# https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.19/html/networking/microshift-disconnected-network-config
configure_ovn() {
  IP="10.44.0.1"
  nmcli con add type loopback con-name stable-microshift ifname lo ip4 ${IP}/32

  nmcli conn modify stable-microshift ipv4.ignore-auto-dns yes
  nmcli conn modify stable-microshift ipv4.dns "10.44.1.1"

  NAME="$(hostnamectl hostname)"
  echo "${IP} ${NAME}" >> /etc/hosts

  cat > /etc/microshift/config.d/10-hostname.yaml <<EOF
  node:
    hostnameOverride: ${NAME}
    nodeIP: ${IP}
EOF
}

#
# Main
#

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Wait until the NetworkManager is ready
for _ in {1..30}; do
    if systemctl is-active --quiet NetworkManager; then
        echo "NetworkManager is running"
        break
    fi
    echo "Waiting for NetworkManager..."
    sleep 1
done

if ! systemctl is-active --quiet NetworkManager; then
  echo "Error: NetworkManager is not running"
  exit 1
fi

# Cleanup the configuration and stop the MicroShift service
echo 1 | microshift-cleanup-data --all

# Select the appropriate network configuration
if rpm -q microshift-kindnet &>/dev/null; then
  configure_kindnet
else
  configure_ovn
fi

# Restart system services and MicroShift
systemctl enable microshift
for unit in NetworkManager microshift greenboot-healthcheck ; do
  systemctl restart --no-block ${unit}
done
