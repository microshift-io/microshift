#!/bin/bash
# Run against a ready MicroShift bootc node: CONTAINER=microshift-okd-1 ./src/crio_config_test.sh
# Offline mode checks storage using the embedded busybox image and skips registry pulls.
set -euo pipefail

if [ "$#" -gt 1 ] || [[ "${1:-online}" != @(online|offline) ]]; then
    echo "Usage: $0 [online|offline]" >&2
    exit 2
fi

readonly MODE=${1:-online}
readonly CONTAINER=${CONTAINER:-microshift-okd-1}
readonly TEST_IMAGE=${TEST_IMAGE:-quay.io/microshift/busybox:1.36}
# Multi-architecture UBI 9.6 index; override with another signed, uncached Red Hat image.
readonly SIGNED_TEST_IMAGE=${SIGNED_TEST_IMAGE:-registry.access.redhat.com/ubi9/ubi-micro@sha256:990002083442f6a93cd3249da32ecb7c3f6be778a1bec3a73a9c17fbc40edc15}
readonly TEST_NAMESPACE=crio-config-test
namespace_created=0
signed_image_added=0
container_id=""
container_pid=""
signature_workdir=""
signature_policy_file=""

run_on_node() {
    sudo podman exec -i "${CONTAINER}" "$@"
}

kube() {
    run_on_node kubectl --request-timeout=30s "$@"
}

diagnose() {
    echo "=== CRI-O configuration test diagnostics ==="
    run_on_node crio --version || true
    run_on_node rpm -q containers-common || true
    run_on_node cat /etc/containers/storage.conf || true
    run_on_node crio status config || true
    run_on_node journalctl -u crio --no-pager -n 100 || true
    if [ -n "${signature_policy_file}" ]; then
        run_on_node cat "${signature_policy_file}" || true
    fi
    if [ -n "${container_id}" ]; then
        run_on_node crictl inspect "${container_id}" || true
    fi
    if [ -n "${container_pid}" ]; then
        run_on_node cat "/proc/${container_pid}/mountinfo" || true
    fi
    if [ "${namespace_created}" -eq 1 ]; then
        kube describe pods -n "${TEST_NAMESPACE}" || true
        kube get events -n "${TEST_NAMESPACE}" --sort-by=.lastTimestamp || true
    fi
}

cleanup() {
    local status=$?
    trap - EXIT
    if [ "${status}" -ne 0 ]; then
        diagnose
    fi
    if [ "${namespace_created}" -eq 1 ]; then
        if ! run_on_node kubectl --request-timeout=70s delete namespace "${TEST_NAMESPACE}" \
            --wait=true --timeout=60s; then
            echo "ERROR: Could not delete test namespace '${TEST_NAMESPACE}'" >&2
            status=1
        fi
    fi
    # Remove only the signed image introduced by this test, never a pre-existing image.
    if [ "${signed_image_added}" -eq 1 ]; then
        if ! run_on_node timeout 60s crictl rmi "${SIGNED_TEST_IMAGE}"; then
            echo "ERROR: Could not remove the signed test image" >&2
            status=1
        fi
    fi
    if [ -n "${signature_policy_file}" ]; then
        if ! run_on_node rm -f -- "${signature_policy_file}"; then
            echo "ERROR: Could not remove the test signature policy" >&2
            status=1
        fi
    fi
    if [ -n "${signature_workdir}" ]; then
        if ! run_on_node rm -rf -- "${signature_workdir}"; then
            echo "ERROR: Could not remove the signature test directory" >&2
            status=1
        fi
    fi
    exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

verify_storage() {
    local node_name pull_policy runtime_id inspection root_mount filesystem options
    node_name=$(run_on_node hostname)
    kube get node "${node_name}" -o name
    pull_policy=IfNotPresent
    [ "${MODE}" = offline ] && pull_policy=Never

    if ! kube create namespace "${TEST_NAMESPACE}"; then
        echo "ERROR: Refusing to reuse namespace '${TEST_NAMESPACE}'" >&2
        return 1
    fi
    namespace_created=1
    kube create -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: storage-probe
  namespace: ${TEST_NAMESPACE}
spec:
  nodeName: ${node_name}
  restartPolicy: Never
  terminationGracePeriodSeconds: 0
  containers:
  - name: test
    image: ${TEST_IMAGE}
    imagePullPolicy: ${pull_policy}
    command: ["/bin/sh", "-c", "sleep 600"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      runAsNonRoot: true
      runAsUser: 1001
      runAsGroup: 1001
      seccompProfile:
        type: RuntimeDefault
EOF
    run_on_node kubectl --request-timeout=130s wait --for=condition=Ready \
        pod/storage-probe -n "${TEST_NAMESPACE}" --timeout=120s

    runtime_id=$(kube get pod storage-probe -n "${TEST_NAMESPACE}" \
        -o jsonpath='{.status.containerStatuses[?(@.name=="test")].containerID}')
    if [[ "${runtime_id}" != cri-o://* ]]; then
        echo "ERROR: Test container is not running through CRI-O: ${runtime_id}" >&2
        return 1
    fi
    container_id=${runtime_id#cri-o://}
    inspection=$(run_on_node crictl inspect "${container_id}")
    container_pid=$(run_on_node jq -er '.info.pid | select(type == "number" and . > 0)' <<<"${inspection}")
    # awk evaluates the field reference inside the node.
    # shellcheck disable=SC2016
    root_mount=$(run_on_node awk '$5 == "/" { print }' "/proc/${container_pid}/mountinfo")
    # mountinfo separates optional fields from filesystem type and superblock options with " - ".
    read -r filesystem options < <(awk -F ' - ' '{ split($2, fields, " "); print fields[1], fields[3] }' <<<"${root_mount}")
    if [ "${filesystem}" != overlay ] || [[ ",${options}," != *,metacopy=on,* ]]; then
        echo "ERROR: Expected the container root mount to use overlay with metacopy=on" >&2
        echo "${root_mount}" >&2
        return 1
    fi
    echo "PASS: CRI-O container root uses overlay with metacopy=on"
}

verify_signed_pull() {
    local runtime_config policy_dir policy_path pull_output key
    if [[ "${SIGNED_TEST_IMAGE}" != registry.access.redhat.com/* ]]; then
        echo "ERROR: SIGNED_TEST_IMAGE must use the public registry.access.redhat.com registry" >&2
        return 1
    fi

    if run_on_node crictl inspecti "${SIGNED_TEST_IMAGE}" >/dev/null 2>&1; then
        echo "ERROR: Signed test image is already cached; choose an uncached SIGNED_TEST_IMAGE" >&2
        return 1
    fi

    # CRI-O reads <signature_policy_dir>/<namespace>.json for each namespaced pull.
    # Select it with --pod-config instead of modifying the system-wide policy.
    runtime_config=$(run_on_node crio status config)
    policy_dir=$(sed -nE 's/^[[:space:]]*signature_policy_dir[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' <<<"${runtime_config}")
    if [[ "${policy_dir}" != /* ]]; then
        echo "ERROR: CRI-O must expose an absolute signature_policy_dir" >&2
        return 1
    fi
    for key in /etc/pki/sigstore/SIGSTORE-redhat-release3 /etc/pki/sigstore/REKOR-signing-key; do
        if ! run_on_node test -r "${key}"; then
            echo "ERROR: Required image signing key is unavailable: ${key}" >&2
            return 1
        fi
    done
    run_on_node mkdir -p "${policy_dir}"
    signature_workdir=$(run_on_node mktemp -d "${policy_dir}/.crio-config-test-XXXXXX")
    run_on_node tee "${signature_workdir}/pod-config.json" >/dev/null <<EOF
{"metadata":{"name":"signature-probe","namespace":"${TEST_NAMESPACE}","uid":"${TEST_NAMESPACE}"}}
EOF
    run_on_node tee "${signature_workdir}/policy.json" >/dev/null <<'EOF'
{"default":[{"type":"reject"}]}
EOF
    policy_path="${policy_dir}/${TEST_NAMESPACE}.json"
    # Refuse to replace an existing administrator file or symlink.
    if ! run_on_node ln -sT -- "${signature_workdir}/policy.json" "${policy_path}"; then
        echo "ERROR: Could not create a separate namespace signature policy: ${policy_path}" >&2
        return 1
    fi
    signature_policy_file=${policy_path}

    if pull_output=$(run_on_node timeout 120s crictl pull \
        --pod-config "${signature_workdir}/pod-config.json" "${SIGNED_TEST_IMAGE}" 2>&1); then
        signed_image_added=1
        echo "ERROR: CRI-O ignored the test namespace's reject policy" >&2
        return 1
    fi
    if ! grep -Eqi 'rejected by policy' <<<"${pull_output}"; then
        echo "ERROR: Expected policy rejection, received: ${pull_output}" >&2
        return 1
    fi
    echo "PASS: CRI-O rejects the image under the test namespace's reject policy"

    run_on_node tee "${signature_workdir}/policy.json" >/dev/null <<'EOF'
{
  "default": [{"type": "reject"}],
  "transports": {
    "docker": {
      "registry.access.redhat.com": [{
        "type": "sigstoreSigned",
        "keyPath": "/etc/pki/sigstore/SIGSTORE-redhat-release3",
        "rekorPublicKeyPath": "/etc/pki/sigstore/REKOR-signing-key"
      }]
    }
  }
}
EOF
    run_on_node timeout 120s crictl pull --pod-config "${signature_workdir}/pod-config.json" "${SIGNED_TEST_IMAGE}"
    signed_image_added=1
    echo "PASS: CRI-O pulled the Red Hat image with sigstore signature verification required"
}

echo "=== Verifying CRI-O configuration in ${CONTAINER} (${MODE}) ==="
# The tool variable is evaluated by the shell inside the node.
# shellcheck disable=SC2016
run_on_node sh -c 'for tool in kubectl crictl crio jq awk timeout tee mktemp ln; do command -v "$tool" >/dev/null || exit 1; done'
run_on_node systemctl is-active --quiet crio
verify_storage
if [ "${MODE}" = online ]; then
    verify_signed_pull
else
    echo "SKIP: Signed registry pull requires network access"
fi
echo "=== CRI-O configuration test passed ==="
