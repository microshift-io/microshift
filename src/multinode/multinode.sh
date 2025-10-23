#!/bin/bash
set -euo pipefail

#
# MicroShift multinode helper
#

DEFAULT_NODE_COUNT=3
USHIFT_MULTINODE_CLUSTER="${USHIFT_MULTINODE_CLUSTER:-microshift-okd-multinode}"
NODE_BASE_NAME="${NODE_BASE_NAME:-microshift-okd-}"
USHIFT_IMAGE="${USHIFT_IMAGE:-microshift-okd}"
LVM_DISK="${LVM_DISK:-/var/lib/microshift-okd/lvmdisk.image}"
LVM_VOLSIZE="${LVM_VOLSIZE:-1G}"
VG_NAME="${VG_NAME:-vg-${USHIFT_MULTINODE_CLUSTER}}"

create_topolvm_backend() {
    if [ -f "${LVM_DISK}" ]; then
        echo "INFO: '${LVM_DISK}' exists, reusing"
        return 0
    fi

    sudo mkdir -p "$(dirname "${LVM_DISK}")"
    sudo truncate --size="${LVM_VOLSIZE}" "${LVM_DISK}"
    local -r device_name="$(sudo losetup --find --show --nooverlap "${LVM_DISK}")"
    sudo vgcreate -f -y "${VG_NAME}" "${device_name}"
}

wait_for_kubeconfig() {
    local -r name="${1}"
    local -r kubeconfig="/var/lib/microshift/resources/kubeadmin/${name}/kubeconfig"

    for _ in $(seq 600); do
        if sudo podman exec -i "${name}" /bin/test -f "${kubeconfig}"; then
            return 0
        fi
        sleep 5
    done
    return 1
}

copy_kubeconfig() {
    local -r name="${1}"
    local -r src_kubeconfig="/var/lib/microshift/resources/kubeadmin/${name}/kubeconfig"
    local -r dest_kubeconfig="kubeconfig.${name}"
    sudo podman cp "${name}:${src_kubeconfig}" "${dest_kubeconfig}"
    return $?
}

add_node() {
    local -r name="${1}"
    local -r network_name="${2}"
    local -r ip_address="${3}"

    local vol_opts="--tty --volume /dev:/dev"
	for device in input snd dri; do
		[ -d "/dev/${device}" ] && vol_opts="${vol_opts} --tmpfs /dev/${device}"
	done

    sudo podman run --privileged -d \
        --ulimit nofile=524288:524288 \
        "${vol_opts}" \
        --tmpfs /var/lib/containers \
        --network "${network_name}" \
        --ip "${ip_address}" \
        --name "${name}" \
        --hostname "${name}" \
        "${USHIFT_IMAGE}"

    return $?
}

join_node() {
    local -r name="${1}"
    local -r primary_name="${NODE_BASE_NAME}1"
    local -r src_kubeconfig="/var/lib/microshift/resources/kubeadmin/${primary_name}/kubeconfig"
    local -r tmp_kubeconfig="/tmp/kubeconfig.${primary_name}"

    sudo podman cp "${primary_name}:${src_kubeconfig}" "${tmp_kubeconfig}"
    local -r dest_kubeconfig="kubeconfig"
    sudo podman cp "${tmp_kubeconfig}" "${name}:${dest_kubeconfig}"
    sudo rm -f "${tmp_kubeconfig}"

    sudo podman exec -i "${name}" bash -c "\
        systemctl stop microshift kubepods.slice crio; \
        microshift add-node --kubeconfig=${dest_kubeconfig} --learner=false > add-node.log 2>&1"

    return $?
}

wait_node_ready() {
    local -r name="${1}"

    for _ in $(seq 100); do
        state=$(sudo podman exec -i "${name}" systemctl show --property=SubState --value greenboot-healthcheck 2>/dev/null || echo "unknown")
        if [ "${state}" = "exited" ]; then
            return 0
        fi
        sleep 5
    done
    return 1
}

create_podman_network() {
    local -r name="${1}"

    if ! sudo podman network exists "${name}"; then
        echo "Creating podman network: ${name}"
        sudo podman network create "${name}"
    else
        echo "Podman network '${name}' already exists"
    fi
    return 0
}

is_cluster_created() {
    if sudo podman container exists "${NODE_BASE_NAME}1"; then
        return 0
    fi
    return 1
}

get_subnet() {
    # shellcheck disable=SC2016
    local -r subnet_with_mask=$(sudo podman network inspect "${USHIFT_MULTINODE_CLUSTER}" --format '{{range .}}{{range .Subnets}}{{.Subnet}}{{end}}{{end}}')
    if [ -z "$subnet_with_mask" ]; then
        echo "ERROR: Could not determine subnet for network '${USHIFT_MULTINODE_CLUSTER}'." >&2
        exit 1
    fi
    local -r subnet="${subnet_with_mask%%/*}"
    echo "$subnet"
}

get_ip_address() {
    local -r subnet="${1}"
    local -r node_id="${2}"
    echo "$subnet" | awk -F. -v new="$node_id" 'NF==4{$4=new+10; printf "%s.%s.%s.%s", $1,$2,$3,$4} NF!=4{print $0}'
}

cmd_create() {
    local count="${1}"
    if ! [[ "${count}" =~ ^[0-9]+$ ]] || [ "${count}" -lt 3 ]; then
        echo "ERROR: number of nodes must be >= 3" >&2
        exit 1
    fi

    if is_cluster_created; then
        echo "ERROR: cluster already created" >&2
        exit 1
    fi

    sudo modprobe openvswitch || true
    create_podman_network "${USHIFT_MULTINODE_CLUSTER}"
    create_topolvm_backend
    local -r subnet=$(get_subnet)
    echo "Subnet for '${USHIFT_MULTINODE_CLUSTER}': $subnet"

    for i in $(seq 1 "$count"); do
        node_name="${NODE_BASE_NAME}${i}"
        ip_address=$(get_ip_address "$subnet" "$i")
        echo "Creating node: $node_name"
        if ! add_node "${node_name}" "${USHIFT_MULTINODE_CLUSTER}" "${ip_address}"; then
            echo "ERROR: failed to create node: $node_name" >&2
            exit 1
        fi

        if [ "${i}" -eq 1 ]; then
            echo "Waiting for node to be ready: $node_name"
            if ! wait_node_ready "${node_name}"; then
                echo "ERROR: Time out waiting for node to be ready: $node_name" >&2
                exit 1
            fi
        else
            echo "Adding node to the cluster: $node_name"
            if ! join_node "${node_name}"; then
                echo "ERROR: failed to join node to the cluster: $node_name. Check logs with 'sudo podman exec ${node_name} cat add-node.log'" >&2
                exit 1
            fi
        fi
    done
}

cmd_add_node() {
    local -r count="${1:-1}"
    if ! [[ "${count}" =~ ^[0-9]+$ ]] || [ "${count}" -lt 1 ]; then
        echo "ERROR: COUNT must be a positive integer greater than 0" >&2
        exit 1
    fi

    local last_id=0
    local node
    for node in $(sudo podman ps -a --format '{{.Names}}' | grep -E "^${NODE_BASE_NAME}[0-9]+$" | sed "s/${NODE_BASE_NAME}//"); do
        if [[ "$node" =~ ^[0-9]+$ ]] && [ "$node" -gt "$last_id" ]; then
            last_id="$node"
        fi
    done

    local -r subnet=$(get_subnet)

    for i in $(seq 1 "$count"); do
        node_id=$((last_id + i))
        node_name="${NODE_BASE_NAME}${node_id}"
        ip_address=$(get_ip_address "$subnet" "$node_id")
        echo "Creating node: $node_name"
        if ! add_node "${node_name}" "${USHIFT_MULTINODE_CLUSTER}" "${ip_address}"; then
            echo "ERROR: failed to create node: $node_name" >&2
            exit 1
        fi
        echo "Joining node to the cluster: $node_name"
        if ! join_node "${node_name}"; then
            echo "ERROR: failed to join node to the cluster: $node_name. Check logs with 'sudo podman exec ${node_name} cat add-node.log'" >&2
            exit 1
        fi
    done
}

cmd_start() {
    local -r containers=$(sudo podman ps -a --format '{{.Names}}' | grep -E "^${NODE_BASE_NAME}[0-9]+$" || true)
    for container in ${containers}; do
        echo "Starting container: ${container}"
        sudo podman start "${container}" || true
    done
}

cmd_stop() {
    local -r containers=$(sudo podman ps --format '{{.Names}}' | grep -E "^${NODE_BASE_NAME}[0-9]+$" || true)
    for container in ${containers}; do
        echo "Stopping container: ${container}"
        sudo podman stop --time 0 "${container}" || true
    done
}

cmd_status() {
    if ! sudo podman container exists "${NODE_BASE_NAME}1"; then
        echo "Cluster is not initialized."
        exit 1
    fi

    local -r running_containers=$(sudo podman ps --format '{{.Names}}' | grep -E "^${NODE_BASE_NAME}[0-9]+$" || true)

    if [ -z "${running_containers}" ]; then
        echo "Cluster is down. No cluster containers are currently running."
        return 0
    fi

    local -r first_container=$(echo "${running_containers}" | head -n1)
    echo "Cluster is running."
    sudo podman exec -i "${first_container}" oc --kubeconfig=/var/lib/microshift/resources/kubeadmin/kubeconfig get nodes -o wide
    exit $?
}

cmd_delete() {
    containers=$(sudo podman ps -a --format '{{.Names}}' | grep "^${NODE_BASE_NAME}[0-9]\+") || true
    for container in ${containers}; do
        echo "Stopping container: ${container}"
        sudo podman stop --time 0 "${container}" || true
        echo "Removing container: ${container}"
        sudo podman rm -f "${container}" || true
    done

    # Remove podman network for the multinode cluster
    if sudo podman network exists "${USHIFT_MULTINODE_CLUSTER}" ; then
        echo "Removing podman network: ${USHIFT_MULTINODE_CLUSTER}"
        sudo podman network rm "${USHIFT_MULTINODE_CLUSTER}" || true
    fi
    if [ -f "${LVM_DISK}" ]; then
        echo "Deleting LVM disk: ${LVM_DISK}"
        sudo lvremove -y "${VG_NAME}" || true
		sudo vgremove -y "${VG_NAME}" || true
		local -r device_name="$(sudo losetup -j "${LVM_DISK}" | cut -d: -f1)"
		[ -n "${device_name}" ] && sudo losetup -d "${device_name}" || true
        sudo rm -rf "$(dirname "${LVM_DISK}")"
    fi
    echo "Cluster deleted successfully"
}

usage() {
    cat <<EOF
Usage: $0 <command> [args]

Commands:
  create [COUNT]       Create cluster with COUNT nodes (default 3, min 3).
  add-node [COUNT]     Add COUNT new nodes (default 1) to the cluster.
  start                Start all nodes.
  stop                 Stop all nodes.
  status               Show the status of the cluster.
  delete               Delete the cluster.

Environment:
    USHIFT_IMAGE                MicroShift image (default: microshift-okd)
    USHIFT_MULTINODE_CLUSTER    Cluster name (default: microshift-okd-multinode)
    NODE_BASE_NAME              Node base name (default: microshift-okd-)
    LVM_DISK                    TopoLVM disk image (default: /var/lib/microshift-okd/lvmdisk.image)
    LVM_VOLSIZE                 TopoLVM volume size (default: 1G)
    VG_NAME                     TopoLVM volume group name (default: vg-microshift-okd)
EOF
}

main() {
    local cmd="${1:-}"; shift || true

    echo "Multinode Cluster Environment Summary:"
    echo "  LVM_DISK                 = ${LVM_DISK}"
    echo "  LVM_VOLSIZE              = ${LVM_VOLSIZE}"
    echo "  VG_NAME                  = ${VG_NAME}"
    echo "  USHIFT_MULTINODE_CLUSTER = ${USHIFT_MULTINODE_CLUSTER}"
    echo "  NODE_BASE_NAME           = ${NODE_BASE_NAME}"
    echo "  USHIFT_IMAGE             = ${USHIFT_IMAGE}"

    case "${cmd}" in
        create) cmd_create "${1:-${DEFAULT_NODE_COUNT}}" ;;
        add-node) cmd_add_node "${1:-1}" ;;
        start) cmd_start ;;
        stop) cmd_stop ;;
        status) cmd_status ;;
        delete) cmd_delete ;;
        *) usage ;;
    esac
}

main "$@"
