# Run MicroShift Upstream

MicroShift can be run on the host or inside a Bootc container.

## MicroShift RPMs

### Prerequisites

MicroShift requires the `openvswitch` package. The installation instructions may
vary depending on the current operating system.

For example, on CentOS Stream, the following command should be run to enable the
appropriate repository.

```bash
sudo dnf install -y centos-release-nfv-openvswitch
```

### Install RPM Packages

Run the following command to install MicroShift RPM package from the local
repository copied from the build container image.
See [Build MicroShift RPMs](../docs/build.md#build-microshift-rpms) for more information.

```bash
RPM_REPO_DIR=/tmp/microshift-rpms

sudo ./src/create_repos.sh -create "${RPM_REPO_DIR}"

sudo dnf install -y microshift
```

### Start MicroShift Service

Run the following commands to configure the minimum required firewall rules,
disable LVMS, and start the MicroShift service.

```bash
sudo firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
sudo firewall-cmd --permanent --zone=trusted --add-source=169.254.169.1
sudo firewall-cmd --reload

cat << EOF | sudo tee -a /etc/microshift/config.yaml >/dev/null
storage:
    driver: "none"
EOF

sudo systemctl enable --now microshift.service
```

Verify that all the MicroShift pods are up and running successfully.

```bash
mkdir -p ~/.kube
sudo cat /var/lib/microshift/resources/kubeadmin/kubeconfig > ~/.kube/config

oc get pods -A
```

## MicroShift Bootc Image

### Prerequisites

#### TopoLVM Backend

Prepare the TopoLVM CSI backend on the host to be used by MicroShift when compiled
with the default `WITH_TOPOLVM=1` built option.

```bash
LVM_DISK=/var/db/lvmdisk.image
VG_NAME=myvg1

sudo truncate --size=20G "${LVM_DISK}"
sudo losetup -f "${LVM_DISK}"

DEVICE_NAME="$(sudo losetup -j "${LVM_DISK}" | cut -d: -f1)"
sudo vgcreate -f -y "${VG_NAME}" "${DEVICE_NAME}"
```

#### OVN-K Configuration

If OVN-K CNI driver is used (`WITH_KINDNET=0` non-default build option), the
`openvswitch` module must be loaded on the host by running the following command.

```bash
sudo modprobe openvswitch
```

### Start the Container

Run the following command to start MicroShift inside a Bootc container.

```bash
make run
```

### Container Login

Log into the container by running the following command.

```bash
make login
```

Verify that all the MicroShift services are up and running successfully.

```bash
export KUBECONFIG=/var/lib/microshift/resources/kubeadmin/kubeconfig
oc get nodes
oc get pods -A
```

### Stop the Container

Run the following command to stop the MicroShift Bootc container.

```bash
make stop
```

## Cleanup

### RPM

Run the following command to delete all the MicroShift data and uninstall the
MicroShift RPM packages.

```bash
echo y | sudo microshift-cleanup-data --all
sudo dnf remove -y microshift*
```

### Bootc Containers

Run the following commands to delete MicroShift Bootc container images.

```bash
make clean
```

Clean up the LVM volume used by the TopoLVM CSI backend.

```bash
LVM_DISK=/var/db/lvmdisk.image
VG_NAME=myvg1

sudo vgremove -y "${VG_NAME}"
DEVICE_NAME="$(sudo losetup -j "${LVM_DISK}" | cut -d: -f1)"
[ -n "${DEVICE_NAME}" ] && sudo losetup -d "${DEVICE_NAME}"
sudo rm -f "${LVM_DISK}"
```
