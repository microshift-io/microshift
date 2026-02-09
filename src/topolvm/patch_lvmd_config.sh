#!/bin/bash
# Patches TopoLVM ConfigMap with user-specified VG_NAME and SPARE_GB
# This script is executed as ExecStartPre in the microshift.service to
# configure TopoLVM with custom volume group name and spare-gb settings.
set -euo pipefail

# Read environment variables from /proc/1/environ (container's init process)
# since systemd services don't automatically inherit container environment
if [ -f /proc/1/environ ]; then
    for var in VG_NAME SPARE_GB; do
        value=$(tr '\0' '\n' < /proc/1/environ | grep "^${var}=" | cut -d= -f2- || true)
        if [ -n "${value}" ]; then
            export "${var}=${value}"
        fi
    done
fi

VG_NAME="${VG_NAME:-myvg1}"
SPARE_GB="${SPARE_GB:-10}"

PATCH_DIR="/etc/microshift/manifests.d/001-microshift-topolvm"

# Only create the patch if non-default values are specified
if [ "${VG_NAME}" = "myvg1" ] && [ "${SPARE_GB}" = "10" ]; then
    # Clean up any stale patch files from previous runs with custom values
    rm -rf "${PATCH_DIR}"
    exit 0
fi

mkdir -p "${PATCH_DIR}"

# Create ConfigMap as a resource (not a patch) for MicroShift to apply
cat > "${PATCH_DIR}/topolvm-lvmd-configmap.yaml" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: topolvm-lvmd-0
  namespace: topolvm-system
  labels:
    app.kubernetes.io/instance: topolvm
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/name: topolvm
    idx: "0"
data:
  lvmd.yaml: |
    socket-name: /run/topolvm/lvmd.sock
    device-classes:
      - default: true
        name: ssd
        spare-gb: ${SPARE_GB}
        volume-group: ${VG_NAME}
EOF

cat > "${PATCH_DIR}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - topolvm-lvmd-configmap.yaml
EOF
