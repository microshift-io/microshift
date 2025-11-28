#!/bin/bash
set -euo pipefail

OWNER=${OWNER:-microshift-io}
REPO=${REPO:-microshift}
BRANCH=${BRANCH:-main}
TAG=${TAG:-latest}

LVM_DISK="/var/lib/microshift-okd/lvmdisk.image"
VG_NAME="myvg1"

WORKDIR=$(mktemp -d /tmp/microshift-quickrpm-XXXXXX)
trap 'rm -rf "${WORKDIR}"' EXIT

function check_prerequisites() {
    # Supported platforms
    case "$(uname -m)" in
    x86_64|aarch64)
        ;;
    *)
        echo "ERROR: Unsupported platform: $(uname -m)"
        exit 1
    esac

    # Supported operating systems
    # shellcheck disable=SC1091
    source /etc/os-release
    case "${ID}" in
    centos|fedora|rhel)
        ;;
    *)
        echo "ERROR: Unsupported operating system: ${ID}"
        exit 1
    esac
}

# The CentOS 10 Stream does not include the containernetworking-plugins package
# in the AppStream repository. Download the package from CentOS 9 Stream because
# it is required by MicroShift 4.20 and older due to cri-o dependencies.
function centos10_cni_plugins() {
    # Check if the operating system is CentOS 10 Stream
    # shellcheck disable=SC1091
    source /etc/os-release
    if [ "${ID}" != "centos" ] || [ "${VERSION_ID}" != "10" ] ; then
        return 0
    fi

    # If containernetworking-plugins is already installed, exit
    if rpm -q containernetworking-plugins &>/dev/null; then
        return 0
    fi

    dnf install -y \
        --repofrompath=c9appstream,"https://mirror.stream.centos.org/9-stream/AppStream/$(uname -m)/os/" \
        --repo=c9appstream \
        --nogpgcheck \
        containernetworking-plugins
}

function install_rpms() {
    # Download the RPMs from the release
    mkdir -p "${WORKDIR}/rpms"
    curl -L -s --retry 5 \
        "https://github.com/${OWNER}/${REPO}/releases/download/${TAG}/microshift-rpms-$(uname -m).tgz" | \
        tar zxf - -C "${WORKDIR}/rpms"

    # Download the installation scripts
    for script in create_repos.sh postinstall.sh ; do
        curl -fSsL --retry 5 --max-time 60 \
            "https://github.com/${OWNER}/${REPO}/raw/${BRANCH}/src/rpm/${script}" \
            -o "${WORKDIR}/${script}"
        chmod +x "${WORKDIR}/${script}"
    done

    # Create the RPM repository and install the RPMs
    "${WORKDIR}/create_repos.sh" -create "${WORKDIR}/rpms"
    # Disable weak dependencies to avoid the deployment of the microshift-networking
    # RPM, which is not necessary when microshift-kindnet RPM is installed.
    dnf install -y --setopt=install_weak_deps=False \
        microshift microshift-kindnet microshift-topolvm
    "${WORKDIR}/create_repos.sh" -delete
}

function prepare_lvm_disk() {
    local -r lvm_disk="$1"
    local -r vg_name="$2"

    if [ -f "${lvm_disk}" ]; then
        echo "INFO: '${lvm_disk}' already exists. Clearing and reusing it."
        dd if=/dev/zero of="${lvm_disk}" bs=1M count=100 >/dev/null
        return 0
    fi

    mkdir -p "$(dirname "${lvm_disk}")"
    truncate --size=1G "${lvm_disk}"

    local -r device_name="$(losetup --find --show --nooverlap "${lvm_disk}")"
    vgcreate -f -y "${vg_name}" "${device_name}"
}

function start_microshift() {
    "${WORKDIR}/postinstall.sh"
    systemctl start microshift.service
}

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Update the 'latest' tag to the latest released version
if [ "${TAG}" == "latest" ] ; then
    dnf install -y jq
    TAG="$(curl -s --max-time 60 "https://api.github.com/repos/${OWNER}/${REPO}/releases/latest" | jq -r .tag_name)"
    if [ -z "${TAG}" ] || [ "${TAG}" == "null" ] ; then
        echo "ERROR: Could not determine the latest release tag from GitHub"
        exit 1
    fi
fi

# Run the procedures
check_prerequisites
centos10_cni_plugins
install_rpms
prepare_lvm_disk "${LVM_DISK}" "${VG_NAME}"
start_microshift

# Follow-up instructions
echo
echo "MicroShift is running on the host"
echo "LVM disk:  ${LVM_DISK}"
echo "VG name:   ${VG_NAME}"
echo
echo "To verify that MicroShift pods are up and running, run the following command:"
echo " - sudo oc get pods -A --kubeconfig /var/lib/microshift/resources/kubeadmin/kubeconfig"
echo
echo "To uninstall MicroShift, run the following command:"
echo " - curl -s https://${OWNER}.github.io/${REPO}/quickclean.sh | sudo bash"
