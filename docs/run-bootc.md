# MicroShift Bootc Deployment

MicroShift can be run on the host or inside a Bootc container.
This document describes how to run MicroShift inside a Bootc container.

See [MicroShift Host Deployment](./run.md) on how to run MicroShift on the host.

## Deployment

### Start the Cluster

Run `make run` to start MicroShift inside a Bootc container.

The following options can be specified in the make command line using the `NAME=VAL` format.

| Name              | Required | Default  | Comments
|-------------------|----------|----------|---------
| LVM_VOLSIZE       | no       | 1G       | TopoLVM CSI backend volume
| ISOLATED_NETWORK  | no       | 0        | Use `--network none` podman option

This step creates a single-node MicroShift cluster. The cluster can be extended using `make add-node` to add one node at a time.

This step includes:
* Loading the `openvswitch` module required when OVN-K CNI driver is used
  when compiled with the non-default `WITH_KINDNET=0` image build option.
* Preparing a TopoLVM CSI backend (default 1GB, configurable via `LVM_VOLSIZE`) on the host to be used by MicroShift when
  compiled with the default `WITH_TOPOLVM=1` image build option.
* Creating a podman network for easier multi-node cluster support with name resolution.

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

Log into the container by running the following command. The command is displayed as
part of the summary from `make run` and `make add-node` command output.

For example, the first node in a cluster is named `microshift-okd-1`:
```bash
sudo podman exec -it microshift-okd-1 /bin/bash -l
```

Verify that all the MicroShift services are up and running successfully.
```bash
export KUBECONFIG=/var/lib/microshift/resources/kubeadmin/kubeconfig
oc get nodes
oc get pods -A
```

### Add Node to Cluster

To create a multi-node cluster, you can add additional nodes after creating the
initial cluster with `make run`.

```bash
make add-node
```

> Note: The `add-node` target requires a non-isolated network (`ISOLATED_NETWORK=0`).
> Each additional node will be automatically joined to the cluster.

### Check Cluster Status

Run the following commands to check the status of your MicroShift cluster.

```bash
# Wait until the MicroShift service is ready (checks all nodes)
make run-ready

# Wait until the MicroShift service is healthy (checks all nodes)
make run-healthy

# Show current cluster status including nodes and pods
make run-status
```

### Stop Cluster

Run the following command to stop the MicroShift cluster.

```bash
make stop
```

If you have stopped the MicroShift cluster, you can start it again using the following command.

```bash
make start
```

## Cleanup

Run the following command to stop the MicroShift cluster and clean up the LVM
volume used by the TopoLVM CSI backend.

```bash
make clean
```

Run the following command to perform a full cleanup, including the
MicroShift Bootc images.

```bash
make clean-all
```
