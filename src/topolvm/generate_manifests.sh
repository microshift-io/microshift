#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
ASSETS_DIR="${SCRIPT_DIR}/assets"
RELEASE_DIR="${SCRIPT_DIR}/release"

# Prepares manifests and release info for TopoLVM upstream running on MicroShift
CERT_MANAGER_VERSION=v1.16.1
TOPO_LVM_VERSION=v15.5.2

generate_manifests() {
  # Create a namespace for TopoLVM
  cat >"${ASSETS_DIR}/01-namespace.yaml" <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: topolvm-system
  labels:
    openshift.io/run-level: "0"
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
EOF

  # Install cert-manager from the released manifest
  curl -fsSL -o "${ASSETS_DIR}/02-cert-manager.yaml" \
    https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml

  # Generate manifests using helm
  # NOTE: this will produce multi-arch manifest, support both amd64 and arm64
  helm repo add topolvm https://topolvm.github.io/topolvm/
  helm repo update
  helm template --include-crds --namespace=topolvm-system --version=${TOPO_LVM_VERSION} topolvm topolvm/topolvm >"${ASSETS_DIR}/03-topolvm.yaml"
  helm repo remove topolvm

  # Patch replicas to 1
  # shellcheck disable=SC2016
  yq 'select(.kind == "Deployment").spec.replicas = 1' -i "${ASSETS_DIR}/03-topolvm.yaml"
  
  # Patch topolvm-controller manifest with longer startup delay to allow dns to start
  yq 'select(.kind == "Deployment" and .metadata.name == "topolvm-controller").spec.template.spec.containers[0] |= (
  .livenessProbe.failureThreshold = 3 | 
  .readinessProbe.timeoutSeconds = 3 |
  .readinessProbe.failureThreshold = 3 |
  .readinessProbe.periodSeconds = 60 |
  .startupProbe = {
      "failureThreshold": 3,
      "periodSeconds": 60,
      "timeoutSeconds": 3,
      "httpGet": {
        "port": "healthz",
        "path": "/healthz"}
      }
  )' -i "${ASSETS_DIR}/03-topolvm.yaml"

  # Generate kustomize
  cat >"${ASSETS_DIR}/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - 01-namespace.yaml
  - 02-cert-manager.yaml
  - 03-topolvm.yaml
EOF

  cat >"${ASSETS_DIR}/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - 01-namespace.yaml
  - 02-cert-manager.yaml
  - 03-topolvm.yaml
EOF
}

generate_release_file() {
  local -r rel_arch=$1
  local -r rel_file="${RELEASE_DIR}/release-topolvm-${rel_arch}.json"
  local -r tmp_file=$(mktemp /tmp/topolvm-release-XXXXXX.txt)

  for file in ${ASSETS_DIR}/02-cert-manager.yaml ${ASSETS_DIR}/03-topolvm.yaml ; do
    images="$(yq -r '.spec.template.spec.containers[].image' "${file}" | grep -v '^---$')"
    for image in ${images}; do
        echo "${image}" >> "${tmp_file}"
    done
  done

  mapfile -t images < <(sort -u "${tmp_file}")
  local last_index=$(( ${#images[@]} - 1 ))

  echo -en "{\n  \"images\": {\n" > "${rel_file}"
  for i in "${!images[@]}"; do
    local image name
    image="${images[$i]}"
    name="$(basename "${image}" | cut -d ':' -f 1)"

    echo "Processing image for ${rel_arch}: ${image}"
    echo -n "    \"${name}\": \"${image}\"" >> "${rel_file}"
    if [ "${i}" -eq "${last_index}" ]; then
      echo "" >> "${rel_file}"
    else
      echo "," >> "${rel_file}"
    fi
  done
  echo -en "  }\n}\n" >> "${rel_file}"

  rm -f "${tmp_file}"
}

#
# Main
#
if ! helm version &>/dev/null ; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

mkdir -p "${ASSETS_DIR}" "${RELEASE_DIR}"
generate_manifests
generate_release_file "x86_64"
generate_release_file "aarch64"

echo ""
echo "Manifests generated in ${ASSETS_DIR}"
echo "Release info generated in ${RELEASE_DIR}"
