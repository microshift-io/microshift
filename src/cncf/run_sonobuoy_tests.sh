#!/bin/bash
#
# Run CNCF conformance tests with Sonobuoy
# Based on https://github.com/openshift/microshift/blob/main/test/scenarios-bootc/periodics/el96-src%40cncf-conformance.sh
#

set -euo pipefail

# Configuration
SONOBUOY_VERSION="${SONOBUOY_VERSION:-v0.57.3}"
SYSTEMD_LOGS_VERSION="${SYSTEMD_LOGS_VERSION:-v0.4}"
TEST_MODE="${TEST_MODE:-certified-conformance}"
TIMEOUT_TEST="${TIMEOUT_TEST:-8400}"  # ~2.5 hours
TIMEOUT_RESULTS="${TIMEOUT_RESULTS:-600}"  # 10 minutes to wait for results
RESULTS_DIR="${RESULTS_DIR:-/tmp/sonobuoy-output}"
EXTRA_E2E_SKIP="${EXTRA_E2E_SKIP:-}"

# Create results directory
mkdir -p "${RESULTS_DIR}"

# Function to collect debug info on failure
collect_sonobuoy_debug_info() {
    ~/go/bin/sonobuoy logs > "${RESULTS_DIR}/sonobuoy-logs.txt" 2>&1 || true
    kubectl get all -n sonobuoy -o wide > "${RESULTS_DIR}/sonobuoy-resources.txt" 2>&1 || true
    kubectl describe all -n sonobuoy > "${RESULTS_DIR}/sonobuoy-resources-describe.txt" 2>&1 || true
    kubectl get events -n sonobuoy --sort-by=.metadata.creationTimestamp > "${RESULTS_DIR}/sonobuoy-events.txt" 2>&1 || true
}

# Configure cluster prerequisites
oc adm policy add-scc-to-group privileged system:authenticated system:serviceaccounts || rc=$?
oc adm policy add-scc-to-group anyuid system:authenticated system:serviceaccounts || rc=$?
if [ "${rc:-0}" -ne 0 ]; then
    echo "ERROR: Failed to configure Security Context Constraints"
    exit 1
fi

# Install Sonobuoy
go install "github.com/vmware-tanzu/sonobuoy@${SONOBUOY_VERSION}"

# Build the E2E_SKIP pattern combining base skips with any extra skips
E2E_SKIP_PATTERN=".*Services should be able to switch session affinity for NodePort service.*"
if [ -n "${EXTRA_E2E_SKIP}" ]; then
    E2E_SKIP_PATTERN="${E2E_SKIP_PATTERN}|${EXTRA_E2E_SKIP}"
    echo "Additional tests will be skipped: ${EXTRA_E2E_SKIP}"
fi

# Force the images to include the registry to avoid ambiguity
~/go/bin/sonobuoy run \
    --sonobuoy-image "docker.io/sonobuoy/sonobuoy:${SONOBUOY_VERSION}" \
    --systemd-logs-image "docker.io/sonobuoy/systemd-logs:${SYSTEMD_LOGS_VERSION}" \
    --mode="${TEST_MODE}" \
    --plugin-env=e2e.E2E_SKIP="${E2E_SKIP_PATTERN}" \
    --dns-namespace=openshift-dns \
    --dns-pod-labels=dns.operator.openshift.io/daemonset-dns=default || rc=$?
if [ "${rc:-0}" -ne 0 ]; then
    echo "ERROR: Failed to start Sonobuoy"
    exit 1
fi

# Wait for up to 5m until tests start
rc=1
for _ in $(seq 1 150); do
    if [ "$(~/go/bin/sonobuoy status --json | jq -r '.status')" = "running" ]; then
        rc=0
        break
    fi
    sleep 2
done

if [ ${rc} -ne 0 ]; then
    echo "ERROR: Failed to start tests after 5m"
    collect_sonobuoy_debug_info
    ~/go/bin/sonobuoy status --json || true
    exit 1
fi

# Monitor test progress
stat_file="${RESULTS_DIR}/cncf_status.json"
start=$(date +%s)
rc=0

while true; do
    ~/go/bin/sonobuoy status --json > "${stat_file}"
    cat "${stat_file}"

    if [ "$(jq -r '.status' "${stat_file}")" != "running" ]; then
        break
    fi

    now=$(date +%s)
    if [ $((now - start)) -ge "${TIMEOUT_TEST}" ]; then
        rc=1
        echo "ERROR: Tests running for ${TIMEOUT_TEST}s. Timing out"
        collect_sonobuoy_debug_info
        break
    fi

    # Print progress information
    jq '.plugins[] | select(.plugin=="e2e") | .["result-counts"], .progress' "${stat_file}" 2>/dev/null || true
    sleep 60
done

# Wait for results to be available
results=true
start=$(date +%s)
while [ -z "$(~/go/bin/sonobuoy status --json | jq -r '."tar-info".name // empty')" ]; do
    now=$(date +%s)
    if [ $((now - start)) -ge "${TIMEOUT_RESULTS}" ]; then
        rc=1
        results=false
        echo "Waited for results for ${TIMEOUT_RESULTS}s. Timing out"
        break
    fi
    echo "Waiting for results availability"
    sleep 10
done

if ${results}; then
    # Collect the results
    results_dir=$(mktemp -d -p /tmp)
    ~/go/bin/sonobuoy retrieve "${results_dir}" -f results.tar.gz
    tar xf "${results_dir}/results.tar.gz" -C "${results_dir}"
    cp "${results_dir}/results.tar.gz" "${RESULTS_DIR}/results.tar.gz"
    cp "${results_dir}/plugins/e2e/results/global/"{e2e.log,junit_01.xml} "${RESULTS_DIR}/" 2>/dev/null || true
    rm -r "${results_dir}"

    # If we got the results we need to check if there are any failures
    failures=$(~/go/bin/sonobuoy status --json | jq '[.plugins[] | select(."result-status" == "failed")] | length')
    if [ "${failures}" != "0" ]; then
        rc=1
    fi
fi

if [ ${rc} -eq 0 ]; then
    echo "Tests finished successfully"
else
    echo "Tests finished with errors. Check results in: ${RESULTS_DIR}"
fi
exit ${rc}
