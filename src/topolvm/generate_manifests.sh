#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
ASSETS_DIR="${SCRIPT_DIR}/assets"
RELEASE_DIR="${SCRIPT_DIR}/release"

# Prepares manifests and release info for TopoLVM upstream running on MicroShift
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

  # Generate manifests using helm
  # NOTE: this will produce multi-arch manifest, support both amd64 and arm64
  helm repo add topolvm https://topolvm.github.io/topolvm/
  helm repo update
  helm template --include-crds --namespace=topolvm-system \
  --set "cert-manager.enabled=false" \
  --set "webhook.podMutatingWebhook.enabled=false" \
  --set webhook.caBundle="dummy" \
  --set webhook.tlsSecretName=topolvm-webhook-cert \
  --version=${TOPO_LVM_VERSION} \
  topolvm topolvm/topolvm >"${ASSETS_DIR}/02-topolvm.yaml"
  
  helm repo remove topolvm

  # remove the caBundle from the mutatingwebhookconfiguration
  yq -i 'del(.webhooks.0.clientConfig.caBundle)' "${ASSETS_DIR}/02-topolvm.yaml"

  # Patch replicas to 1
  # shellcheck disable=SC2016
  yq 'select(.kind == "Deployment").spec.replicas = 1' -i "${ASSETS_DIR}/02-topolvm.yaml"
  
  # Patch topolvm-controller manifest with longer startup delay to allow dns to start
  yq 'with(select(.kind == "Deployment" and .metadata.name == "topolvm-controller").spec.template.spec.containers[] | select(.name == "topolvm-controller");
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
  )' -i "${ASSETS_DIR}/02-topolvm.yaml"

  # Patch topolvm-node DaemonSet with probes
  # echo 'Patching topolvm-node DaemonSet with longer startup delay to allow dns to start'
  yq 'with(select(.kind == "DaemonSet" and .metadata.name == "topolvm-node").spec.template.spec.containers[] | select(.name == "topolvm-node");
  .startupProbe = {
      "failureThreshold": 60,
      "periodSeconds": 2,
      "timeoutSeconds": 3,
      "httpGet": {
        "port": "healthz",
        "path": "/healthz"
      }
    })' -i "${ASSETS_DIR}/02-topolvm.yaml"
  # Generate Patch with annotation to dynamically inject the CA bundle
  cat >"${ASSETS_DIR}/topolvm_mutatingwebhook_patch.yaml" <<'EOF'
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: topolvm-hook
  annotations:
    service.beta.openshift.io/inject-cabundle: "true"
webhooks:
  - name: pvc-hook.topolvm.io
EOF

  cat >"${ASSETS_DIR}/topolvm_service_patch.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: topolvm-controller
  namespace: topolvm-system
  annotations:
    service.beta.openshift.io/serving-cert-secret-name: topolvm-mutatingwebhook
EOF

# Generate kustomize
  cat >"${ASSETS_DIR}/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - 01-namespace.yaml
  - 02-topolvm.yaml
patches:
  - path: topolvm_mutatingwebhook_patch.yaml
  - path: topolvm_service_patch.yaml
EOF
}

generate_release_file() {
  local -r rel_arch=$1
  local -r rel_file="${RELEASE_DIR}/release-topolvm-${rel_arch}.json"
  local -r tmp_file=$(mktemp /tmp/topolvm-release-XXXXXX)

  for file in ${ASSETS_DIR}/02-topolvm.yaml ; do
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
