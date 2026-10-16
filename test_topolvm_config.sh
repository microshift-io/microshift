#!/bin/bash
# A/B Test Suite for TopoLVM VG_NAME and SPARE_GB Configuration
# Tests all permutations of configuration parameters end-to-end

set -euo pipefail

# Configuration
REMOTE_HOST="${REMOTE_HOST:-ushift-devel-el98}"
REMOTE_DIR="${REMOTE_DIR:-/home/microshift/microshift-io/microshift}"
TEST_RESULTS_DIR="${TEST_RESULTS_DIR:-./test-results-$(date +%Y%m%d-%H%M%S)}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_TEST=""

#
# Helper Functions
#

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_test() {
    echo -e "\n${YELLOW}═══════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}$*${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════${NC}\n"
}

pass() {
    echo -e "${GREEN}✓${NC} $*"
}

fail() {
    echo -e "${RED}✗${NC} $*"
    return 1
}

remote_exec() {
    local cmd="$1"
    ssh "${REMOTE_HOST}" "cd ${REMOTE_DIR} && ${cmd}"
}

remote_exec_sudo() {
    local cmd="$1"
    ssh "${REMOTE_HOST}" "cd ${REMOTE_DIR} && sudo ${cmd}"
}

#
# Verification Functions
#

verify_clean_state() {
    log_info "Verifying clean state..."
    local errors=0

    if remote_exec_sudo "podman ps -a 2>/dev/null | grep -q microshift-okd"; then
        fail "Containers still exist"
        errors=$((errors + 1))
    else
        pass "No containers exist"
    fi

    if remote_exec_sudo "vgs 2>/dev/null | grep -qE '(myvg1|test-vg-|image-vg|runtime-vg)'"; then
        fail "Test volume groups still exist"
        remote_exec_sudo "vgs" || true
        errors=$((errors + 1))
    else
        pass "No test volume groups exist"
    fi

    if remote_exec_sudo "losetup -a 2>/dev/null | grep -q microshift"; then
        fail "Loopback devices still attached"
        errors=$((errors + 1))
    else
        pass "No loopback devices attached"
    fi

    if remote_exec_sudo "test -f /var/lib/microshift-okd/lvmdisk.image"; then
        fail "Loopback file still exists"
        errors=$((errors + 1))
    else
        pass "No loopback file exists"
    fi

    if [[ ${errors} -eq 0 ]]; then
        pass "Clean state verified"
        return 0
    else
        fail "${errors} cleanup issues found"
        return 1
    fi
}

verify_lvmd_config() {
    local expected_vg="${1}"
    local expected_spare="${2}"

    log_info "Verifying lvmd.yaml configuration..."

    local actual_vg=$(remote_exec_sudo "podman exec microshift-okd-1 grep 'volume-group:' /etc/topolvm/lvmd.yaml | awk '{print \$2}'")
    local actual_spare=$(remote_exec_sudo "podman exec microshift-okd-1 grep 'spare-gb:' /etc/topolvm/lvmd.yaml | awk '{print \$2}'")

    echo "Expected: vg=${expected_vg}, spare=${expected_spare}"
    echo "Actual:   vg=${actual_vg}, spare=${actual_spare}"

    if [[ "${actual_vg}" == "${expected_vg}" && "${actual_spare}" == "${expected_spare}" ]]; then
        pass "lvmd.yaml config matches expected values"
        return 0
    else
        fail "lvmd.yaml config mismatch"
        return 1
    fi
}

verify_host_vg() {
    local expected_vg="${1}"

    log_info "Verifying host volume group..."

    if remote_exec_sudo "vgs --noheadings -o vg_name | grep -q '^[[:space:]]*${expected_vg}[[:space:]]*\$'"; then
        pass "Host VG '${expected_vg}' exists"
    else
        fail "Host VG '${expected_vg}' not found"
        remote_exec_sudo "vgs" || true
        return 1
    fi

    # Verify config VG matches host VG
    local config_vg=$(remote_exec_sudo "podman exec microshift-okd-1 grep 'volume-group:' /etc/topolvm/lvmd.yaml | awk '{print \$2}'")
    local host_vg=$(remote_exec_sudo "vgs --noheadings -o vg_name | tr -d ' '")

    if [[ "${config_vg}" == "${host_vg}" ]]; then
        pass "Config VG matches host VG"
        return 0
    else
        fail "Config has '${config_vg}' but host has '${host_vg}'"
        return 1
    fi
}

verify_topolvm_running() {
    local vg_name="${1}"

    log_info "Verifying TopoLVM components..."

    # Check pods
    if ! remote_exec "VG_NAME=${vg_name} make env CMD='kubectl get pods -n topolvm-system'"; then
        fail "Cannot get TopoLVM pods"
        return 1
    fi

    # Wait for pods to be ready
    if remote_exec "VG_NAME=${vg_name} make env CMD='kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=topolvm -n topolvm-system --timeout=120s'"; then
        pass "All TopoLVM pods are ready"
    else
        fail "TopoLVM pods not ready within timeout"
        return 1
    fi

    # Run healthcheck
    if remote_exec_sudo "podman exec microshift-okd-1 microshift healthcheck -v=2 --timeout=60s --custom '{\"topolvm-system\":{\"deployments\": [\"topolvm-controller\"], \"daemonsets\": [\"topolvm-node\"]}}'"; then
        pass "TopoLVM healthcheck passed"
    else
        fail "TopoLVM healthcheck failed"
        return 1
    fi

    # Verify StorageClass is default
    local is_default=$(remote_exec "VG_NAME=${vg_name} make env CMD='kubectl get storageclass topolvm-provisioner -o jsonpath=\"{.metadata.annotations.storageclass\\.kubernetes\\.io/is-default-class}\"'")
    if [[ "${is_default}" == "true" ]]; then
        pass "TopoLVM StorageClass is default"
        return 0
    else
        fail "TopoLVM StorageClass is not default: ${is_default}"
        return 1
    fi
}

test_volume_provisioning() {
    local vg_name="${1}"

    log_info "Testing volume provisioning..."

    local pvc_name="test-pvc-$(date +%s)"

    # Create PVC
    remote_exec "VG_NAME=${vg_name} make env CMD='kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${pvc_name}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
  storageClassName: topolvm-provisioner
EOF'"

    # Wait for PVC to bind
    if remote_exec "VG_NAME=${vg_name} make env CMD='kubectl wait --for=jsonpath=\"{.status.phase}\"=Bound pvc/${pvc_name} --timeout=60s'"; then
        pass "PVC ${pvc_name} bound successfully"
    else
        fail "PVC ${pvc_name} failed to bind"
        remote_exec "VG_NAME=${vg_name} make env CMD='kubectl describe pvc/${pvc_name}'" || true
        remote_exec "VG_NAME=${vg_name} make env CMD='kubectl delete pvc/${pvc_name}'" || true
        return 1
    fi

    # Verify LV created
    if remote_exec_sudo "lvs | grep -q '${vg_name}'"; then
        pass "Logical volume created in VG '${vg_name}'"
    else
        fail "No logical volume found in VG '${vg_name}'"
        remote_exec_sudo "lvs" || true
        remote_exec "VG_NAME=${vg_name} make env CMD='kubectl delete pvc/${pvc_name}'" || true
        return 1
    fi

    # Cleanup PVC
    remote_exec "VG_NAME=${vg_name} make env CMD='kubectl delete pvc/${pvc_name}'"
    pass "PVC ${pvc_name} deleted"

    return 0
}

cleanup_environment() {
    local vg_name="${1:-myvg1}"

    log_info "Cleaning up environment (VG_NAME=${vg_name})..."

    if ! remote_exec "VG_NAME=${vg_name} make clean-all 2>&1"; then
        log_warn "Cleanup had issues, attempting manual cleanup..."
        remote_exec_sudo "podman stop microshift-okd-1 || true" || true
        remote_exec_sudo "podman rm -f microshift-okd-1 || true" || true
        remote_exec_sudo "lvremove -y ${vg_name} || true" || true
        remote_exec_sudo "vgremove -y ${vg_name} || true" || true
        remote_exec_sudo "losetup -D || true" || true
        remote_exec_sudo "rm -rf /var/lib/microshift-okd || true" || true
    fi

    pass "Cleanup complete"
}

collect_diagnostics() {
    local vg_name="${1}"
    local test_name="${2}"
    local output_dir="${TEST_RESULTS_DIR}/${test_name}"

    log_warn "Collecting diagnostics for ${test_name}..."

    mkdir -p "${output_dir}"

    # System state
    remote_exec_sudo "vgs" > "${output_dir}/vgs.txt" 2>&1 || true
    remote_exec_sudo "lvs" > "${output_dir}/lvs.txt" 2>&1 || true
    remote_exec_sudo "pvs" > "${output_dir}/pvs.txt" 2>&1 || true
    remote_exec_sudo "lsblk -a" > "${output_dir}/lsblk.txt" 2>&1 || true
    remote_exec_sudo "losetup -a" > "${output_dir}/losetup.txt" 2>&1 || true

    # Container state
    remote_exec_sudo "podman ps -a" > "${output_dir}/podman-ps.txt" 2>&1 || true
    remote_exec_sudo "podman images" > "${output_dir}/podman-images.txt" 2>&1 || true

    # MicroShift logs
    remote_exec_sudo "podman logs microshift-okd-1 2>&1 | tail -200" > "${output_dir}/microshift.log" 2>&1 || true

    # lvmd config
    remote_exec_sudo "podman exec microshift-okd-1 cat /etc/topolvm/lvmd.yaml" > "${output_dir}/lvmd.yaml" 2>&1 || true

    # TopoLVM logs
    remote_exec "VG_NAME=${vg_name} make env CMD='kubectl logs -n topolvm-system daemonset/topolvm-lvmd-0 -c lvmd --tail=100'" > "${output_dir}/lvmd.log" 2>&1 || true
    remote_exec "VG_NAME=${vg_name} make env CMD='kubectl logs -n topolvm-system deployment/topolvm-controller --tail=100'" > "${output_dir}/controller.log" 2>&1 || true

    # Pod status
    remote_exec "VG_NAME=${vg_name} make env CMD='kubectl get pods -A -o wide'" > "${output_dir}/pods.txt" 2>&1 || true
    remote_exec "VG_NAME=${vg_name} make env CMD='kubectl get events -A --sort-by=.lastTimestamp'" > "${output_dir}/events.txt" 2>&1 || true

    log_info "Diagnostics saved to ${output_dir}"
}

#
# Build and Deploy Functions
#

build_and_deploy() {
    local vg_name="${1}"
    local spare_gb="${2}"
    local srpm_spare="${3:-${spare_gb}}"  # Allow different SRPM spare for mismatch tests
    local run_vg="${4:-${vg_name}}"       # Allow different runtime VG for mismatch tests

    log_info "Building with VG_NAME=${vg_name}, SPARE_GB=${spare_gb}..."

    # SRPM build
    if ! remote_exec "make srpm VG_NAME=${vg_name} SPARE_GB=${srpm_spare}"; then
        fail "SRPM build failed"
        return 1
    fi
    pass "SRPM build completed"

    # RPM build
    if ! remote_exec "make rpm"; then
        fail "RPM build failed"
        return 1
    fi
    pass "RPM build completed"

    # Bootc image build
    if ! remote_exec "make image VG_NAME=${vg_name} SPARE_GB=${spare_gb}"; then
        fail "Bootc image build failed"
        return 1
    fi
    pass "Bootc image build completed"

    # Deploy cluster
    log_info "Deploying cluster with VG_NAME=${run_vg}..."
    if ! remote_exec "VG_NAME=${run_vg} make run"; then
        fail "Cluster creation failed"
        return 1
    fi
    pass "Cluster created"

    # Wait for ready
    log_info "Waiting for MicroShift service to be ready (5min timeout)..."
    if ! remote_exec "VG_NAME=${run_vg} make run-ready"; then
        fail "Service not ready within timeout"
        return 1
    fi
    pass "Service is ready"

    # Wait for healthy
    log_info "Waiting for MicroShift service to be healthy (15min timeout)..."
    if ! remote_exec "VG_NAME=${run_vg} make run-healthy"; then
        fail "Service not healthy within timeout"
        return 1
    fi
    pass "Service is healthy"

    return 0
}

#
# Test Cases
#

test_1_default_default() {
    CURRENT_TEST="Test 1: Default/Default"
    log_test "${CURRENT_TEST}"
    TESTS_RUN=$((TESTS_RUN + 1))

    local vg_name="myvg1"
    local spare_gb="0"

    # Cleanup first
    cleanup_environment "${vg_name}"
    verify_clean_state || { TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }

    # Build and deploy
    build_and_deploy "${vg_name}" "${spare_gb}" || { collect_diagnostics "${vg_name}" "test1"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }

    # Verify
    verify_lvmd_config "${vg_name}" "${spare_gb}" || { collect_diagnostics "${vg_name}" "test1"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }
    verify_host_vg "${vg_name}" || { collect_diagnostics "${vg_name}" "test1"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }
    verify_topolvm_running "${vg_name}" || { collect_diagnostics "${vg_name}" "test1"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }
    test_volume_provisioning "${vg_name}" || { collect_diagnostics "${vg_name}" "test1"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }

    # Cleanup
    cleanup_environment "${vg_name}"

    TESTS_PASSED=$((TESTS_PASSED + 1))
    pass "Test 1 PASSED"
}

test_2_custom_vg_default_spare() {
    CURRENT_TEST="Test 2: Custom VG, Default Spare"
    log_test "${CURRENT_TEST}"
    TESTS_RUN=$((TESTS_RUN + 1))

    local vg_name="test-vg-custom"
    local spare_gb="0"

    cleanup_environment "${vg_name}"
    verify_clean_state || { TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }

    build_and_deploy "${vg_name}" "${spare_gb}" || { collect_diagnostics "${vg_name}" "test2"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }

    verify_lvmd_config "${vg_name}" "${spare_gb}" || { collect_diagnostics "${vg_name}" "test2"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }
    verify_host_vg "${vg_name}" || { collect_diagnostics "${vg_name}" "test2"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }
    verify_topolvm_running "${vg_name}" || { collect_diagnostics "${vg_name}" "test2"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }
    test_volume_provisioning "${vg_name}" || { collect_diagnostics "${vg_name}" "test2"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }

    cleanup_environment "${vg_name}"

    TESTS_PASSED=$((TESTS_PASSED + 1))
    pass "Test 2 PASSED"
}

test_3_default_vg_custom_spare() {
    CURRENT_TEST="Test 3: Default VG, Custom Spare"
    log_test "${CURRENT_TEST}"
    TESTS_RUN=$((TESTS_RUN + 1))

    local vg_name="myvg1"
    local spare_gb="5"

    cleanup_environment "${vg_name}"
    verify_clean_state || { TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }

    build_and_deploy "${vg_name}" "${spare_gb}" || { collect_diagnostics "${vg_name}" "test3"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }

    verify_lvmd_config "${vg_name}" "${spare_gb}" || { collect_diagnostics "${vg_name}" "test3"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }
    verify_host_vg "${vg_name}" || { collect_diagnostics "${vg_name}" "test3"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }
    verify_topolvm_running "${vg_name}" || { collect_diagnostics "${vg_name}" "test3"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }
    test_volume_provisioning "${vg_name}" || { collect_diagnostics "${vg_name}" "test3"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }

    cleanup_environment "${vg_name}"

    TESTS_PASSED=$((TESTS_PASSED + 1))
    pass "Test 3 PASSED"
}

test_4_custom_custom() {
    CURRENT_TEST="Test 4: Custom/Custom"
    log_test "${CURRENT_TEST}"
    TESTS_RUN=$((TESTS_RUN + 1))

    local vg_name="test-vg-full"
    local spare_gb="10"

    cleanup_environment "${vg_name}"
    verify_clean_state || { TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }

    build_and_deploy "${vg_name}" "${spare_gb}" || { collect_diagnostics "${vg_name}" "test4"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }

    verify_lvmd_config "${vg_name}" "${spare_gb}" || { collect_diagnostics "${vg_name}" "test4"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }
    verify_host_vg "${vg_name}" || { collect_diagnostics "${vg_name}" "test4"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }
    verify_topolvm_running "${vg_name}" || { collect_diagnostics "${vg_name}" "test4"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }
    test_volume_provisioning "${vg_name}" || { collect_diagnostics "${vg_name}" "test4"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }

    cleanup_environment "${vg_name}"

    TESTS_PASSED=$((TESTS_PASSED + 1))
    pass "Test 4 PASSED"
}

test_5_vg_mismatch() {
    CURRENT_TEST="Test 5: Image/Runtime VG Mismatch (NEGATIVE)"
    log_test "${CURRENT_TEST}"
    TESTS_RUN=$((TESTS_RUN + 1))

    local image_vg="image-vg"
    local runtime_vg="runtime-vg"
    local spare_gb="0"

    cleanup_environment "${image_vg}"
    cleanup_environment "${runtime_vg}"
    verify_clean_state || { TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }

    # Build with one VG, run with different VG
    build_and_deploy "${image_vg}" "${spare_gb}" "${spare_gb}" "${runtime_vg}" || {
        log_warn "Build/deploy may have succeeded (checking if mismatch is caught later)..."
    }

    # Verify config has image VG but host has runtime VG
    local config_vg=$(remote_exec_sudo "podman exec microshift-okd-1 grep 'volume-group:' /etc/topolvm/lvmd.yaml | awk '{print \$2}'")
    local host_vg=$(remote_exec_sudo "vgs --noheadings -o vg_name | tr -d ' '")

    if [[ "${config_vg}" == "${image_vg}" && "${host_vg}" == "${runtime_vg}" ]]; then
        pass "Mismatch confirmed: config has '${config_vg}', host has '${host_vg}'"
    else
        fail "Unexpected state: config has '${config_vg}', host has '${host_vg}'"
        collect_diagnostics "${runtime_vg}" "test5"
        cleanup_environment "${runtime_vg}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi

    # Volume provisioning should FAIL
    log_info "Testing volume provisioning (should FAIL)..."
    if test_volume_provisioning "${runtime_vg}"; then
        fail "Volume provisioning succeeded when it should have failed!"
        collect_diagnostics "${runtime_vg}" "test5"
        cleanup_environment "${runtime_vg}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    else
        pass "Volume provisioning failed as expected"
    fi

    # Check lvmd logs for VG error
    log_info "Checking lvmd logs for VG error..."
    if remote_exec "VG_NAME=${runtime_vg} make env CMD='kubectl logs -n topolvm-system daemonset/topolvm-lvmd-0 -c lvmd'" | grep -i "${image_vg}"; then
        pass "lvmd logs show expected VG '${image_vg}' reference"
    else
        log_warn "Could not find VG reference in lvmd logs"
    fi

    cleanup_environment "${runtime_vg}"

    TESTS_PASSED=$((TESTS_PASSED + 1))
    pass "Test 5 PASSED (negative test)"
}

test_6_missing_runtime_vg() {
    CURRENT_TEST="Test 6: Missing Runtime VG_NAME (NEGATIVE)"
    log_test "${CURRENT_TEST}"
    TESTS_RUN=$((TESTS_RUN + 1))

    local vg_name="myvg1"
    local spare_gb="0"

    cleanup_environment "${vg_name}"
    verify_clean_state || { TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }

    # Build normally
    log_info "Building with VG_NAME=${vg_name}..."
    if ! remote_exec "make srpm VG_NAME=${vg_name} SPARE_GB=${spare_gb}"; then
        fail "SRPM build failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    if ! remote_exec "make rpm"; then
        fail "RPM build failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    if ! remote_exec "make image VG_NAME=${vg_name} SPARE_GB=${spare_gb}"; then
        fail "Bootc image build failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    pass "Build completed"

    # Try to run without VG_NAME (should FAIL)
    log_info "Attempting to run without VG_NAME (should FAIL)..."
    if remote_exec "make run 2>&1 | tee /tmp/test6-run.log"; then
        fail "make run succeeded when it should have failed!"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    else
        pass "make run failed as expected"
    fi

    # Verify error message
    if remote_exec "grep -q 'ERROR: VG_NAME is required' /tmp/test6-run.log"; then
        pass "Error message 'VG_NAME is required' found"
    else
        log_warn "Expected error message not found, checking output..."
        remote_exec "cat /tmp/test6-run.log" || true
    fi

    # Verify no cluster was created
    if ! remote_exec_sudo "podman container exists microshift-okd-1"; then
        pass "No cluster was created (as expected)"
    else
        fail "Cluster was created when it shouldn't have been!"
        cleanup_environment "${vg_name}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi

    TESTS_PASSED=$((TESTS_PASSED + 1))
    pass "Test 6 PASSED (negative test)"
}

test_7_spare_mismatch() {
    CURRENT_TEST="Test 7: SRPM/Image SPARE_GB Mismatch"
    log_test "${CURRENT_TEST}"
    TESTS_RUN=$((TESTS_RUN + 1))

    local vg_name="myvg1"
    local srpm_spare="10"
    local image_spare="5"

    cleanup_environment "${vg_name}"
    verify_clean_state || { TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }

    # Build with different SPARE_GB values
    build_and_deploy "${vg_name}" "${image_spare}" "${srpm_spare}" || { collect_diagnostics "${vg_name}" "test7"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }

    # Verify lvmd.yaml has IMAGE spare value (not SRPM)
    local actual_spare=$(remote_exec_sudo "podman exec microshift-okd-1 grep 'spare-gb:' /etc/topolvm/lvmd.yaml | awk '{print \$2}'")

    if [[ "${actual_spare}" == "${image_spare}" ]]; then
        pass "lvmd.yaml has image SPARE_GB value (${image_spare}), not SRPM value (${srpm_spare})"
    else
        fail "Expected spare=${image_spare}, got spare=${actual_spare}"
        collect_diagnostics "${vg_name}" "test7"
        cleanup_environment "${vg_name}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi

    # Verify cluster functions normally
    verify_topolvm_running "${vg_name}" || { collect_diagnostics "${vg_name}" "test7"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }
    test_volume_provisioning "${vg_name}" || { collect_diagnostics "${vg_name}" "test7"; cleanup_environment "${vg_name}"; TESTS_FAILED=$((TESTS_FAILED + 1)); return 1; }

    cleanup_environment "${vg_name}"

    TESTS_PASSED=$((TESTS_PASSED + 1))
    pass "Test 7 PASSED"
}

#
# Main Test Runner
#

main() {
    log_info "Starting TopoLVM VG_NAME and SPARE_GB A/B Test Suite"
    log_info "Remote host: ${REMOTE_HOST}"
    log_info "Remote directory: ${REMOTE_DIR}"
    log_info "Results directory: ${TEST_RESULTS_DIR}"

    mkdir -p "${TEST_RESULTS_DIR}"

    # Verify SSH connectivity
    log_info "Verifying SSH connectivity..."
    if ! ssh -q "${REMOTE_HOST}" exit; then
        log_error "Cannot connect to ${REMOTE_HOST}"
        exit 1
    fi
    pass "SSH connection successful"

    # Run tests
    test_1_default_default || true
    test_2_custom_vg_default_spare || true
    test_3_default_vg_custom_spare || true
    test_4_custom_custom || true
    test_5_vg_mismatch || true
    test_6_missing_runtime_vg || true
    test_7_spare_mismatch || true

    # Summary
    echo ""
    log_test "TEST SUMMARY"
    echo "Tests run:    ${TESTS_RUN}"
    echo "Tests passed: ${TESTS_PASSED}"
    echo "Tests failed: ${TESTS_FAILED}"

    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        echo -e "${GREEN}All tests PASSED!${NC}"
        exit 0
    else
        echo -e "${RED}${TESTS_FAILED} test(s) FAILED${NC}"
        echo "Diagnostics saved to ${TEST_RESULTS_DIR}"
        exit 1
    fi
}

# Run main if not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
