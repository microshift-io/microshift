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

### Start the Container

Run `make run` to start MicroShift inside a Bootc container.

The following options can be specified in the make command line using the `NAME=VAL` format.

| Name              | Required | Default  | Comments
|-------------------|----------|----------|---------
| LVM_VOLUME_SIZE   | no       | 1G       | TopoLVM CSI backend volume
| ISOLATED_NETWORK  | no       | 0        | Use `--network none` podman option

This step includes:
* Loading the `openvswitch` module required when OVN-K CNI driver is used
  when compiled with the non-default `WITH_KINDNET=0` build option.
* Preparing a 1GB TopoLVM CSI backend on the host to be used by MicroShift when
  compiled with the default `WITH_TOPOLVM=1` build option.

```bash
make run
```

> Specify the `ISOLATED_NETWORK=1` make option to run MicroShift inside a Bootc
> container without Internet access.
>
> Such a setup requires a MicroShift Bootc image built with `make image EMBED_CONTAINER_IMAGES=1`.
> This ensures all the required container image runtime dependencies are embedded
> and the operating system network settings are adjusted to allow a successful
> MicroShift operation.
>
> See the [config_isolated_net.sh](../src/config_isolated_net.sh) script for more
> information.

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

Run the following command to stop the MicroShift Bootc container and
clean up the LVM volume used by the TopoLVM CSI backend.

```bash
make clean
```

Run the following command to perform a full cleanup, including the
MicroShift Bootc images.

```bash
make clean-all
```
