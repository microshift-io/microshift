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

# Stop greenboot before reconfiguring the network. This prevents a race
# condition where greenboot checks MicroShift health during reconfiguration.
# MicroShift is stopped by the cleanup command below.
systemctl stop greenboot-healthcheck 2>/dev/null || true

# Cleanup the configuration and stop the MicroShift service
echo 1 | microshift-cleanup-data --all

# Configure the network with 10.44 prefix (outside the service CIDR
# 10.43.0.0/16) to avoid a conflict in containers where the router-default
# LoadBalancer claims the same IP as the kubernetes ClusterIP (issue #94).
configure_offline_network "10.44"

# Kindnet requires a persistent route for the service CIDR via loopback
# so that ClusterIP traffic reaches the kube-proxy iptables rules.
if rpm -q microshift-kindnet &>/dev/null; then
  nmcli conn modify stable-microshift +ipv4.routes "10.43.0.0/16"
fi

# Restart the NetworkManager service to apply the new network configuration
systemctl restart NetworkManager
wait_for_network_manager

# Enable MicroShift to start on boot. A container or system restart is
# needed to start MicroShift and re-trigger greenboot health checks.
systemctl enable microshift
echo "Restart the container or reboot to start MicroShift and greenboot."
