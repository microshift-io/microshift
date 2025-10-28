#!/bin/bash
# MicroShift Cluster Manager
# Primitive functions for managing MicroShift clusters

set -euo pipefail

# Configuration - These variables can be overridden by the environment
# They are used throughout the script for single-node and multi-node cluster management
USHIFT_MULTINODE_CLUSTER="${USHIFT_MULTINODE_CLUSTER:-microshift-okd-multinode}"
NODE_BASE_NAME="${NODE_BASE_NAME:-microshift-okd-}"
USHIFT_IMAGE="${USHIFT_IMAGE:-microshift-okd}"
LVM_DISK="${LVM_DISK:-/var/lib/microshift-okd/lvmdisk.image}"
LVM_VOLSIZE="${LVM_VOLSIZE:-1G}"
VG_NAME="${VG_NAME:-vg-${USHIFT_MULTINODE_CLUSTER}}"
ISOLATED_NETWORK="${ISOLATED_NETWORK:-0}"

_is_cluster_created() {
    if sudo podman container exists "${NODE_BASE_NAME}1"; then
        return 0
    fi
    return 1
}

_is_container_created() {
    local -r name="${1}"
    if sudo podman container exists "${name}"; then
        return 0
    fi
    return 1
}

_create_topolvm_backend() {
    if [ -f "${LVM_DISK}" ]; then
        echo "INFO: '${LVM_DISK}' exists, reusing"
        return 0
    fi

    sudo mkdir -p "$(dirname "${LVM_DISK}")"
    sudo truncate --size="${LVM_VOLSIZE}" "${LVM_DISK}"
    local -r device_name="$(sudo losetup --find --show --nooverlap "${LVM_DISK}")"
    sudo vgcreate -f -y "${VG_NAME}" "${device_name}"
}

# Delete TopoLVM backend
_delete_topolvm_backend() {
    if [ -f "${LVM_DISK}" ]; then
        echo "Deleting TopoLVM backend: ${LVM_DISK}"
        sudo lvremove -y "${VG_NAME}" || true
        sudo vgremove -y "${VG_NAME}" || true
        local -r device_name="$(sudo losetup -j "${LVM_DISK}" | cut -d: -f1)"
        [ -n "${device_name}" ] && sudo losetup -d "${device_name}" || true
        sudo rm -rf "$(dirname "${LVM_DISK}")"
    fi
}

_create_podman_network() {
    local -r name="${1}"
    if ! sudo podman network exists "${name}"; then
        echo "Creating podman network: ${name}"
        sudo podman network create "${name}"
    else
        echo "Podman network '${name}' already exists"
    fi
}

_get_subnet() {
    local -r network_name="${1}"
    local -r subnet_with_mask=$(sudo podman network inspect "${network_name}" --format '{{range .}}{{range .Subnets}}{{.Subnet}}{{end}}{{end}}')
    if [ -z "$subnet_with_mask" ]; then
        echo "ERROR: Could not determine subnet for network '${network_name}'." >&2
        exit 1
    fi
    local -r subnet="${subnet_with_mask%%/*}"
    echo "$subnet"
}

_get_ip_address() {
    local -r subnet="${1}"
    local -r node_id="${2}"
    echo "$subnet" | awk -F. -v new="$node_id" 'NF==4{$4=new+10; printf "%s.%s.%s.%s", $1,$2,$3,$4} NF!=4{print $0}'
}

_add_node() {
    local -r name="${1}"
    local -r network_name="${2}"
    local -r ip_address="${3}"

    local vol_opts="--tty --volume /dev:/dev"
    for device in input snd dri; do
        [ -d "/dev/${device}" ] && vol_opts="${vol_opts} --tmpfs /dev/${device}"
    done

    local network_opts="--network ${network_name}"
    if [ "${ISOLATED_NETWORK}" = "0" ]; then
        network_opts="${network_opts} --ip ${ip_address}"
    fi

    # shellcheck disable=SC2086
    sudo podman run --privileged -d \
        --ulimit nofile=524288:524288 \
        ${vol_opts} \
        ${network_opts} \
        --tmpfs /var/lib/containers \
        --name "${name}" \
        --hostname "${name}" \
        "${USHIFT_IMAGE}"

    return $?
}


_join_node() {
    local -r name="${1}"
    local -r primary_name="${NODE_BASE_NAME}1"
    local -r src_kubeconfig="/var/lib/microshift/resources/kubeadmin/${primary_name}/kubeconfig"
    local -r tmp_kubeconfig="/tmp/kubeconfig.${primary_name}"

    sudo podman cp "${primary_name}:${src_kubeconfig}" "${tmp_kubeconfig}"
    local -r dest_kubeconfig="kubeconfig"
    sudo podman cp "${tmp_kubeconfig}" "${name}:${dest_kubeconfig}"
    sudo rm -f "${tmp_kubeconfig}"

    sudo podman exec -i "${name}" bash -c "\
        systemctl stop microshift kubepods.slice crio && \
        microshift add-node --kubeconfig=${dest_kubeconfig} --learner=false > add-node.log 2>&1"

    return $?
}


_get_cluster_containers() {
    sudo podman ps -a --format '{{.Names}}' | grep -E "^${NODE_BASE_NAME}[0-9]+$" || true
}


_get_running_containers() {
    sudo podman ps --format '{{.Names}}' | grep -E "^${NODE_BASE_NAME}[0-9]+$" || true
}


cluster_create() {
    local -r container_name="${NODE_BASE_NAME}1"
    echo "Creating cluster: ${container_name}"

    if _is_container_created "${container_name}"; then
        echo "ERROR: Container '${container_name}' already exists" >&2
        exit 1
    fi

    sudo modprobe openvswitch || true
    _create_topolvm_backend
    _create_podman_network "${USHIFT_MULTINODE_CLUSTER}"

    local -r subnet=$(_get_subnet "${USHIFT_MULTINODE_CLUSTER}")
    local network_name="${USHIFT_MULTINODE_CLUSTER}"
    if [ "${ISOLATED_NETWORK}" = "1" ]; then
        network_name="none"
    fi

    local -r node_name="${NODE_BASE_NAME}1"
    local -r ip_address=$(_get_ip_address "$subnet" "1")
    if ! _add_node "${node_name}" "${network_name}" "${ip_address}"; then
        echo "ERROR: failed to create node: $node_name" >&2
        exit 1
    fi

    if [ "${ISOLATED_NETWORK}" = "1" ] ; then
        echo "Configuring isolated network for node: ${node_name}"
        sudo podman cp ./src/config_isolated_net.sh "${node_name}:/tmp/config_isolated_net.sh"
        sudo podman exec -i "${node_name}" /tmp/config_isolated_net.sh
        sudo podman exec -i "${node_name}" rm -vf /tmp/config_isolated_net.sh
    fi

    echo "Cluster created successfully"
}


cluster_add_node() {
    if ! _is_cluster_created; then
        echo "ERROR: Cluster is not created" >&2
        exit 1
    fi
    if [ "${ISOLATED_NETWORK}" = "1" ]; then
        echo "ERROR: Network type is isolated" >&2
        exit 1
    fi

    local last_id=0

    for node in $(_get_cluster_containers); do
        node_num="${node##*"${NODE_BASE_NAME}"}"
        if [[ "${node_num}" =~ ^[0-9]+$ ]] && [ "${node_num}" -gt "${last_id}" ]; then
            last_id="${node_num}"
        fi
    done

    local -r subnet=$(_get_subnet "${USHIFT_MULTINODE_CLUSTER}")
    local -r node_id=$((last_id + 1))
    local -r node_name="${NODE_BASE_NAME}${node_id}"
    local -r ip_address=$(_get_ip_address "$subnet" "$node_id")

    cluster_healthy

    echo "Creating node: ${node_name}"
    if ! _add_node "${node_name}" "${USHIFT_MULTINODE_CLUSTER}" "${ip_address}"; then
        echo "ERROR: failed to create node: ${node_name}" >&2
        exit 1
    fi
    echo "Joining node to the cluster: ${node_name}"
    if ! _join_node "${node_name}"; then
        echo "ERROR: failed to join node to the cluster: ${node_name}. Check logs with 'sudo podman exec ${node_name} cat add-node.log'" >&2
        exit 1
    fi

    echo "Node added successfully"
    return 0
}


cluster_start() {
    local -r containers=$(_get_cluster_containers)

    if [ -z "${containers}" ]; then
        echo "ERROR: No cluster containers found" >&2
        exit 1
    fi

    echo "Starting cluster"
    for container in ${containers}; do
        echo "Starting container: ${container}"
        sudo podman start "${container}" || true
    done
}


cluster_stop() {
    local -r containers=$(_get_running_containers)

    if [ -z "${containers}" ]; then
        echo "No running cluster containers"
        return 0
    fi

    echo "Stopping cluster"
    for container in ${containers}; do
        echo "Stopping container: ${container}"
        sudo podman stop --time 0 "${container}" || true
    done
}


cluster_destroy() {
    local containers
    containers=$(_get_cluster_containers)
    for container in ${containers}; do
        echo "Stopping container: ${container}"
        sudo podman stop --time 0 "${container}" || true
        echo "Removing container: ${container}"
        sudo podman rm -f "${container}" || true
    done

    if sudo podman network exists "${USHIFT_MULTINODE_CLUSTER}"; then
        echo "Removing podman network: ${USHIFT_MULTINODE_CLUSTER}"
        sudo podman network rm "${USHIFT_MULTINODE_CLUSTER}" || true
    fi

    sudo rmmod openvswitch || true
    _delete_topolvm_backend

    echo "Cluster destroyed successfully"
}


cluster_ready() {
    local -r containers=$(_get_running_containers)
    if [ -z "${containers}" ]; then
        echo "No running nodes found"
        exit 1
    fi
    for container in ${containers}; do
        echo "Checking readiness of container: ${container}"
        state=$(sudo podman exec -i "${container}" systemctl show --property=SubState --value microshift.service 2>/dev/null || echo "unknown")
        if [ "${state}" != "running" ]; then
            echo "Node ${container} is not ready."
            exit 1
        fi
    done
    echo "All nodes running."
}

cluster_healthy() {
    if ! _is_cluster_created ; then
        echo "Cluster is not initialized"
        exit 1
    fi

    local -r containers=$(_get_running_containers)

    if [ -z "${containers}" ]; then
        echo "Cluster is down. No cluster nodes are running."
        return 0
    fi

    for container in ${containers}; do
        echo "Checking health of container: ${container}"
        state=$(sudo podman exec -i "${container}" systemctl show --property=SubState --value greenboot-healthcheck 2>/dev/null || echo "unknown")
        if [ "${state}" != "exited" ]; then
            echo "Node ${container} is not healthy."
            exit 1
        fi
    done
    echo "All nodes healthy."
}


cluster_status() {
    if ! _is_cluster_created ; then
        echo "Cluster is not initialized"
        exit 1
    fi

    local -r running_containers=$(_get_running_containers)

    if [ -z "${running_containers}" ]; then
        echo "Cluster is down. No cluster nodes are running."
        return 0
    fi

    local -r created_containers=$(_get_cluster_containers)
    for container in ${created_containers}; do
        if ! echo "${running_containers}" | grep -q "${container}"; then
            echo "Node ${container} is not running."
        fi
    done

    local -r first_container=$(echo "${running_containers}" | head -n1)
    echo "Cluster is running."
    sudo podman exec -i "${first_container}" oc --kubeconfig=/var/lib/microshift/resources/kubeadmin/kubeconfig get nodes,pods -A -o wide 2>/dev/null || echo "Unable to retrieve cluster status"
    return 0
}

main() {
    case "${1:-}" in
        create)
            shift
            cluster_create
            ;;
        add-node)
            shift
            cluster_add_node
            ;;
        start)
            shift
            cluster_start
            ;;
        stop)
            shift
            cluster_stop
            ;;
        delete)
            shift
            cluster_destroy
            ;;
        ready)
            shift
            cluster_ready
            ;;
        healthy)
            shift
            cluster_healthy
            ;;
        status)
            shift
            cluster_status
            ;;
        *)
            echo "Usage: $0 {create|add-node|start|stop|delete|ready|healthy|status}"
            exit 1
            ;;
    esac
}

# Ensure script is running from project root directory (where Makefile exists)
if [ ! -f "./Makefile" ]; then
    echo "ERROR: Please run this script from the project root directory (where Makefile is located)" >&2
    exit 1
fi

main "$@"
