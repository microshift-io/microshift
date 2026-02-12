#!/bin/bash
set -euo pipefail
set -x

# See the following for more information:
# https://docs.redhat.com/en/documentation/red_hat_build_of_microshift/4.19/html/networking/microshift-disconnected-network-config
configure_offline_network() {
  local -r subnet=$1

  IP="${subnet}.0.1"
  nmcli con add type loopback con-name stable-microshift ifname lo ip4 "${IP}/32"

  nmcli conn modify stable-microshift ipv4.ignore-auto-dns yes
  nmcli conn modify stable-microshift ipv4.dns "${subnet}.1.1"

  NAME="$(hostnamectl hostname)"
  echo "${IP} ${NAME}" >> /etc/hosts

  cat > /etc/microshift/config.d/10-hostname.yaml <<EOF
  node:
    hostnameOverride: ${NAME}
    nodeIP: ${IP}
EOF
}

wait_for_network_manager() {
  for _ in {1..30}; do
    if systemctl is-active --quiet NetworkManager; then
      echo "NetworkManager is running"
      break
    fi
    echo "Waiting for NetworkManager..."
    sleep 1
  done
  if ! systemctl is-active --quiet NetworkManager; then
    echo "ERROR: NetworkManager is not running"
    exit 1
  fi
}

#
# Main
#

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

wait_for_network_manager

# Cleanup the configuration and stop the MicroShift service
echo 1 | microshift-cleanup-data --all

# Select the appropriate network configuration
if rpm -q microshift-kindnet &>/dev/null; then
  configure_offline_network "10.43"
else
  configure_offline_network "10.44"
fi

# Restart the NetworkManager service to apply the new network configuration
systemctl restart NetworkManager
wait_for_network_manager

# Enable and restart the MicroShift service
systemctl enable microshift
systemctl restart --no-block microshift
