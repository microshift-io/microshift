#!/bin/bash
set -euo pipefail

readonly CONTAINER="${CONTAINER:-microshift-okd-1}"
readonly WITH_MULTUS="${WITH_MULTUS:-0}"
readonly TEST_NAMESPACE="network-smoke-test"
readonly TEST_IMAGE="quay.io/microshift/busybox:1.36"
readonly PRIMARY_PAYLOAD="microshift-primary-network-ok"
readonly SECONDARY_PAYLOAD="microshift-secondary-network-ok"
readonly KUBE_REQUEST_TIMEOUT="30s"
readonly KUBE_EXEC_TIMEOUT="15s"
# Six client attempts can each use the outer exec bound, with five retry sleeps.
readonly KUBE_LISTENER_TIMEOUT="120s"

namespace_created=0
listener_pid=""

# Run the supplied command inside the configured MicroShift node container.
run_on_node() {
    sudo podman exec -i "${CONTAINER}" "$@"
}

# Run kubectl inside the node container with the standard request timeout.
kube() {
    run_on_node kubectl --request-timeout="${KUBE_REQUEST_TIMEOUT}" "$@"
}

# Run kubectl with the request timeout supplied as the first argument.
kube_with_request_timeout() {
    local -r request_timeout=$1
    shift

    run_on_node kubectl --request-timeout="${request_timeout}" "$@"
}

# Run kubectl exec inside the node container, bounded by the supplied outer timeout.
kube_exec() {
    local -r exec_timeout=$1
    shift

    timeout --foreground "${exec_timeout}" sudo podman exec -i "${CONTAINER}" \
        kubectl --request-timeout="${KUBE_REQUEST_TIMEOUT}" exec "$@"
}

# Print best-effort node, cluster, and test-namespace diagnostics.
diagnose() {
    echo "=== Network smoke test diagnostics ==="
    run_on_node ip -4 route show table all || true
    kube get nodes -o wide || true
    kube get pods -A -o wide || true
    if [ "${namespace_created}" -eq 1 ]; then
        kube describe pods -n "${TEST_NAMESPACE}" || true
        kube get events -n "${TEST_NAMESPACE}" --sort-by=.lastTimestamp || true
    fi
}

# Handle script exit by stopping the listener, diagnosing failures, and deleting
# the test namespace, reporting a deletion failure when the script had succeeded.
cleanup() {
    local status=$?
    trap - EXIT

    if [ -n "${listener_pid}" ] && kill -0 "${listener_pid}" 2>/dev/null; then
        kill "${listener_pid}" 2>/dev/null || true
        wait "${listener_pid}" 2>/dev/null || true
    fi
    if [ "${status}" -ne 0 ]; then
        diagnose
    fi
    if [ "${namespace_created}" -eq 1 ]; then
        if ! kube_with_request_timeout 70s delete namespace "${TEST_NAMESPACE}" \
            --wait=true --timeout=60s; then
            echo "ERROR: Failed to delete test namespace '${TEST_NAMESPACE}'" >&2
            if [ "${status}" -eq 0 ]; then
                status=1
            fi
        fi
    fi
    exit "${status}"
}
trap cleanup EXIT

# Verify that a node command fails with an allowed status and matching error text.
# The first two arguments are a status list and error regex; the rest are the command.
verify_isolated_probe() {
    local expected_statuses=$1
    local expected_output=$2
    shift 2
    local output
    local probe_status

    # The quoted variables are expanded by the shell inside the node container.
    # shellcheck disable=SC2016
    if ! output="$(run_on_node sh -c '
        "$@"
        status=$?
        printf "\n__PROBE_EXIT__=%s\n" "${status}"
        exit 0
    ' -- "$@" 2>&1)"; then
        echo "ERROR: Failed to execute isolated-network probe in '${CONTAINER}'" >&2
        return 1
    fi

    probe_status="${output##*__PROBE_EXIT__=}"
    probe_status="${probe_status%%$'\n'*}"
    if [ "${probe_status}" = "0" ]; then
        echo "ERROR: Isolated-network probe unexpectedly succeeded: $*" >&2
        return 1
    fi
    case ",${expected_statuses}," in
        *",${probe_status},"*) ;;
        *)
            echo "ERROR: Probe failed with unexpected status ${probe_status}: $*" >&2
            echo "${output}" >&2
            return 1
            ;;
    esac
    if ! grep -Eqi "${expected_output}" <<<"${output}"; then
        echo "ERROR: Probe failure did not report an expected network error: $*" >&2
        echo "${output}" >&2
        return 1
    fi
}

# Print the first candidate subnet that does not overlap a node IPv4 route.
select_secondary_subnet() {
    local node_routes
    local candidate

    node_routes="$(run_on_node ip -4 route show table all)"
    for candidate in 198.18.0.0/24 198.18.1.0/24 198.19.0.0/24; do
        if CANDIDATE="${candidate}" NODE_ROUTES="${node_routes}" python3 -c '
import ipaddress
import os
import sys

candidate = ipaddress.ip_network(os.environ["CANDIDATE"])
for line in os.environ["NODE_ROUTES"].splitlines():
    for token in line.split():
        try:
            route = ipaddress.ip_network(token, strict=False)
        except ValueError:
            continue
        if route.version == 4 and candidate.overlaps(route):
            sys.exit(1)
'; then
            echo "${candidate}"
            return 0
        fi
    done

    echo "ERROR: No non-overlapping secondary test subnet is available" >&2
    return 1
}

# Create the restricted client and server pods, attaching Multus when enabled.
create_test_pods() {
    {
        cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: network-server
  namespace: ${TEST_NAMESPACE}
EOF
        if [ "${WITH_MULTUS}" = "1" ]; then
            cat <<'EOF'
  annotations:
    k8s.v1.cni.cncf.io/networks: network-smoke-secondary
EOF
        fi
        cat <<EOF
spec:
  hostNetwork: false
  terminationGracePeriodSeconds: 0
  containers:
  - name: test
    image: ${TEST_IMAGE}
    imagePullPolicy: Never
    command: ["/bin/sh", "-c", "sleep 3600"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      runAsNonRoot: true
      runAsUser: 1001
      runAsGroup: 1001
      seccompProfile:
        type: RuntimeDefault
---
apiVersion: v1
kind: Pod
metadata:
  name: network-client
  namespace: ${TEST_NAMESPACE}
EOF
        if [ "${WITH_MULTUS}" = "1" ]; then
            cat <<'EOF'
  annotations:
    k8s.v1.cni.cncf.io/networks: network-smoke-secondary
EOF
        fi
        cat <<EOF
spec:
  hostNetwork: false
  terminationGracePeriodSeconds: 0
  containers:
  - name: test
    image: ${TEST_IMAGE}
    imagePullPolicy: Never
    command: ["/bin/sh", "-c", "sleep 3600"]
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
    } | kube apply -f -
}

# Create a bridge NetworkAttachmentDefinition for the supplied test subnet.
create_secondary_network() {
    local test_subnet=$1
    local range_prefix="${test_subnet%0/24}"

    cat <<EOF | kube apply -f -
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: network-smoke-secondary
  namespace: ${TEST_NAMESPACE}
spec:
  config: |-
    {
      "cniVersion": "0.4.0",
      "type": "bridge",
      "bridge": "br-smoke221",
      "ipam": {
        "type": "host-local",
        "ranges": [[{
          "subnet": "${test_subnet}",
          "rangeStart": "${range_prefix}20",
          "rangeEnd": "${range_prefix}50",
          "gateway": "${range_prefix}254"
        }]],
        "dataDir": "/var/lib/cni/br-smoke221"
      }
    }
EOF
}

# Run a client command up to six times and print its expected payload on success.
receive_payload() {
    local expected=$1
    shift
    local result=""
    local attempt

    for attempt in $(seq 1 6); do
        if result="$(kube_exec "${KUBE_EXEC_TIMEOUT}" \
            -n "${TEST_NAMESPACE}" network-client -- "$@")"; then
            if [ "${result}" = "${expected}" ]; then
                echo "${result}"
                return 0
            fi
            echo "ERROR: Expected payload '${expected}', got '${result}'" >&2
            return 1
        fi
        if [ "${attempt}" -lt 6 ]; then
            sleep 2
        fi
    done

    echo "ERROR: Did not receive '${expected}' after ${attempt} attempts" >&2
    return 1
}

# Verify that both test pods use pod networking, have an IP, and run as UID 1001.
verify_test_pods() {
    local actual_uid
    local host_network
    local pod
    local pod_ip

    for pod in network-server network-client; do
        if ! host_network="$(kube get pod -n "${TEST_NAMESPACE}" "${pod}" \
            -o jsonpath='{.spec.hostNetwork}')"; then
            echo "ERROR: Failed to inspect host networking for test pod '${pod}'" >&2
            return 1
        fi
        if [ "${host_network}" = "true" ]; then
            echo "ERROR: Test pod '${pod}' is not an ordinary non-hostNetwork pod" >&2
            return 1
        fi
        pod_ip="$(kube get pod -n "${TEST_NAMESPACE}" "${pod}" -o jsonpath='{.status.podIP}')"
        if [ -z "${pod_ip}" ]; then
            echo "ERROR: Test pod '${pod}' has no primary pod IP" >&2
            return 1
        fi
        actual_uid="$(kube_exec "${KUBE_EXEC_TIMEOUT}" \
            -n "${TEST_NAMESPACE}" "${pod}" -- id -u)"
        if [ "${actual_uid}" != "1001" ]; then
            echo "ERROR: Test pod '${pod}' is running as UID ${actual_uid}, expected 1001" >&2
            return 1
        fi
    done
}

# Verify direct pod-IP payload delivery and Kubernetes Service DNS resolution.
verify_primary_network() {
    local server_ip
    local service_ip
    local dns_output
    local payload

    server_ip="$(kube get pod -n "${TEST_NAMESPACE}" network-server -o jsonpath='{.status.podIP}')"
    if [ -z "${server_ip}" ]; then
        echo "ERROR: The network server has no primary pod IP" >&2
        return 1
    fi

    # The positional parameter is expanded by the shell inside the test pod.
    # shellcheck disable=SC2016
    kube_exec "${KUBE_LISTENER_TIMEOUT}" -n "${TEST_NAMESPACE}" network-server -- \
        timeout 110 sh -c 'printf "%s\n" "$1" | nc -l -p 8080' -- \
        "${PRIMARY_PAYLOAD}" &
    listener_pid=$!
    payload="$(receive_payload "${PRIMARY_PAYLOAD}" nc -w 5 "${server_ip}" 8080)"
    if ! wait "${listener_pid}"; then
        echo "ERROR: Primary-network listener failed" >&2
        listener_pid=""
        return 1
    fi
    listener_pid=""
    echo "Primary pod-IP payload verified: ${payload}"

    service_ip="$(kube get service kubernetes -n default -o jsonpath='{.spec.clusterIP}')"
    if [ -z "${service_ip}" ] || [ "${service_ip}" = "None" ]; then
        echo "ERROR: The Kubernetes Service has no ClusterIP" >&2
        return 1
    fi
    if ! dns_output="$(kube_exec "${KUBE_EXEC_TIMEOUT}" \
        -n "${TEST_NAMESPACE}" network-client -- \
        timeout 10 nslookup kubernetes.default.svc.cluster.local 2>&1)"; then
        echo "ERROR: Kubernetes Service DNS lookup failed" >&2
        echo "${dns_output}" >&2
        return 1
    fi
    if ! printf '%s\n' "${dns_output}" | awk -v expected="${service_ip}" '
        $1 == "Address:" {
            sub(/:53$/, "", $2)
            if ($2 == expected) found = 1
        }
        END { exit !found }
    '; then
        echo "ERROR: DNS did not resolve the Kubernetes Service to ClusterIP ${service_ip}" >&2
        echo "${dns_output}" >&2
        return 1
    fi
    echo "Kubernetes Service DNS resolved to ${service_ip}"
}

# Wait for the Multus CRD and daemonset, then verify the required CNI plugins.
wait_for_multus() {
    kube_with_request_timeout 70s wait --for=condition=Established \
        crd/network-attachment-definitions.k8s.cni.cncf.io --timeout=60s
    kube_with_request_timeout 130s rollout status daemonset/multus \
        -n openshift-multus --timeout=120s
    run_on_node test -x /run/cni/bin/bridge
    run_on_node test -x /run/cni/bin/host-local
}

# Verify net1 addressing and routes plus payload delivery on the supplied subnet.
verify_secondary_network() {
    local test_subnet=$1
    local subnet_prefix="${test_subnet%0/24}"
    local client_ip
    local server_ip
    local pod
    local pod_node
    local server_node
    local routes
    local payload

    for pod in network-server network-client; do
        if ! kube_exec "${KUBE_EXEC_TIMEOUT}" \
            -n "${TEST_NAMESPACE}" "${pod}" -- ip link show dev net1 >/dev/null; then
            echo "ERROR: Test pod '${pod}' has no Multus net1 interface" >&2
            return 1
        fi
        routes="$(kube_exec "${KUBE_EXEC_TIMEOUT}" \
            -n "${TEST_NAMESPACE}" "${pod}" -- ip -4 route show)"
        if ! grep -Fq "${test_subnet} dev net1" <<<"${routes}"; then
            echo "ERROR: Test pod '${pod}' has no ${test_subnet} route on net1" >&2
            echo "${routes}" >&2
            return 1
        fi
        if ! grep -Eq '^default .* dev eth0([[:space:]]|$)' <<<"${routes}"; then
            echo "ERROR: Test pod '${pod}' primary default route is not on eth0" >&2
            echo "${routes}" >&2
            return 1
        fi
        if grep -Eq '^default .* dev net1([[:space:]]|$)' <<<"${routes}"; then
            echo "ERROR: Test pod '${pod}' secondary network replaced the default route" >&2
            echo "${routes}" >&2
            return 1
        fi
    done

    server_node="$(kube get pod -n "${TEST_NAMESPACE}" network-server -o jsonpath='{.spec.nodeName}')"
    pod_node="$(kube get pod -n "${TEST_NAMESPACE}" network-client -o jsonpath='{.spec.nodeName}')"
    if [ -z "${server_node}" ] || [ "${server_node}" != "${pod_node}" ]; then
        echo "ERROR: Multus test pods are not scheduled on the same node" >&2
        return 1
    fi

    server_ip="$(kube_exec "${KUBE_EXEC_TIMEOUT}" \
        -n "${TEST_NAMESPACE}" network-server -- \
        ip -4 -o addr show dev net1 | awk '{print $4}' | cut -d/ -f1)"
    client_ip="$(kube_exec "${KUBE_EXEC_TIMEOUT}" \
        -n "${TEST_NAMESPACE}" network-client -- \
        ip -4 -o addr show dev net1 | awk '{print $4}' | cut -d/ -f1)"
    case "${server_ip}" in
        "${subnet_prefix}"*) ;;
        *) echo "ERROR: Server secondary IP '${server_ip}' is outside ${test_subnet}" >&2; return 1 ;;
    esac
    case "${client_ip}" in
        "${subnet_prefix}"*) ;;
        *) echo "ERROR: Client secondary IP '${client_ip}' is outside ${test_subnet}" >&2; return 1 ;;
    esac
    if [ "${server_ip}" = "${client_ip}" ]; then
        echo "ERROR: Multus test pods received the same secondary IP" >&2
        return 1
    fi

    # The positional parameters are expanded by the shell inside the test pod.
    # shellcheck disable=SC2016
    kube_exec "${KUBE_LISTENER_TIMEOUT}" -n "${TEST_NAMESPACE}" network-server -- \
        timeout 110 sh -c 'printf "%s\n" "$1" | nc -l -p 8081 -s "$2"' -- \
        "${SECONDARY_PAYLOAD}" "${server_ip}" &
    listener_pid=$!
    payload="$(receive_payload "${SECONDARY_PAYLOAD}" \
        nc -s "${client_ip}" -w 5 "${server_ip}" 8081)"
    if ! wait "${listener_pid}"; then
        echo "ERROR: Secondary-network listener failed" >&2
        listener_pid=""
        return 1
    fi
    listener_pid=""
    echo "Secondary Multus payload verified on ${client_ip} -> ${server_ip}: ${payload}"
}

echo "=== Verifying isolated node networking ==="
run_on_node sh -c 'command -v ping >/dev/null && command -v curl >/dev/null'
verify_isolated_probe "1,2" \
    "100% packet loss|Network is unreachable|Destination Host Unreachable|No route to host" \
    ping -c 1 -W 10 8.8.8.8
verify_isolated_probe "5,6,7,28" \
    "Could not resolve|Failed to connect|Connection timed out|Resolving timed out|Operation timed out|Network is unreachable" \
    curl --head --max-time 10 https://quay.io
verify_isolated_probe "5,6,7,28" \
    "Could not resolve|Failed to connect|Connection timed out|Resolving timed out|Operation timed out|Network is unreachable" \
    curl --head --max-time 10 https://ghcr.io

if ! kube create namespace "${TEST_NAMESPACE}"; then
    echo "ERROR: Refusing to reuse pre-existing namespace '${TEST_NAMESPACE}'" >&2
    exit 1
fi
namespace_created=1

secondary_subnet=""
if [ "${WITH_MULTUS}" = "1" ]; then
    wait_for_multus
    secondary_subnet="$(select_secondary_subnet)"
    create_secondary_network "${secondary_subnet}"
fi

create_test_pods
kube_with_request_timeout 130s wait --for=condition=Ready \
    pod/network-server pod/network-client -n "${TEST_NAMESPACE}" --timeout=120s

verify_test_pods
verify_primary_network
if [ "${WITH_MULTUS}" = "1" ]; then
    verify_secondary_network "${secondary_subnet}"
    # Confirm the primary network and cluster DNS still work after secondary traffic.
    verify_primary_network
fi

echo "=== Network smoke test passed ==="
