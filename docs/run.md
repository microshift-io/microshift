# MicroShift Host Deployment

MicroShift can be run on the host or inside a Bootc container.
This document describes how to run MicroShift on the host.

See [MicroShift Bootc Deployment](./run-bootc.md) on how to run MicroShift
inside a Bootc container.

## MicroShift RPM Packages

### Install RPM

Run the following commands to install MicroShift RPM packages from a local repository.
This repository should be either [built locally](../docs/build.md#create-rpm-packages)
or downloaded from [Releases](https://github.com/microshift-io/microshift/releases).

```bash
RPM_REPO_DIR=/tmp/microshift-rpms

sudo ./src/rpm/create_repos.sh -create "${RPM_REPO_DIR}"
sudo dnf install -y microshift microshift-kindnet
sudo ./src/rpm/create_repos.sh -delete
```

The following optional RPM packages are available in the repository. It is
mandatory to install either `microshift-kindnet` or `microshift-networking`
to enable the Kindnet or OVN-K networking support.

| Package               | Description                | Comments |
|-----------------------|----------------------------|----------|
| microshift-kindnet    | Kindnet CNI                | Overrides OVN-K |
| microshift-networking | OVN-K CNI                  | Uninstall Kindnet to enable OVN-K |
| microshift-topolvm    | TopoLVM CSI                | Install to enable storage support |
| microshift-olm        | Operator Lifecycle Manager | See [Operator Hub Catalogs](https://okd.io/docs/operators/) |

### Start MicroShift Service

Run the following commands to configure the minimum required firewall rules,
disable LVMS, and start the MicroShift service.

```bash
sudo ./src/rpm/postinstall.sh
sudo systemctl start microshift.service
```

Verify that all the MicroShift pods are up and running successfully.

```bash
mkdir -p ~/.kube
sudo cat /var/lib/microshift/resources/kubeadmin/kubeconfig > ~/.kube/config

oc get pods -A
```

## MicroShift DEB Packages

### Install DEB

Run the following commands to install MicroShift DEB packages from the RPM repository.
This repository should be either [built locally](../docs/build.md#create-deb-packages)
or downloaded from [Releases](https://github.com/microshift-io/microshift/releases).

```bash
DEB_REPO_DIR=/tmp/microshift-rpms/deb
sudo ./src/deb/install.sh "${DEB_REPO_DIR}"
```

The following optional DEB packages are available in the repository.

| Package            | Description                | Comments |
|--------------------|----------------------------|----------|
| microshift-topolvm | TopoLVM CSI                | Install to enable storage support |
| microshift-olm     | Operator Lifecycle Manager | See [Operator Hub Catalogs](https://okd.io/docs/operators/) |

> Note: All of the optional packages are installed by default.

### Start MicroShift Service

Run the following command to start the MicroShift service. All the necessary system
configuration was performed during the installation step.

```bash
sudo systemctl start microshift.service
```

Verify that all the MicroShift pods are up and running successfully.

```bash
mkdir -p ~/.kube
sudo cat /var/lib/microshift/resources/kubeadmin/kubeconfig > ~/.kube/config

oc get pods -A
```

## Cleanup

### RPM

Run the following commands to delete all the MicroShift data and uninstall the
MicroShift RPM packages.

```bash
echo y | sudo microshift-cleanup-data --all
sudo dnf remove -y 'microshift*'
```

### DEB

Run the following commands to delete all the MicroShift data and uninstall the
MicroShift DEB packages.

```bash
echo y | sudo microshift-cleanup-data --all
sudo apt purge -y 'microshift*'
```
