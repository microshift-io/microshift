# MicroShift Host Deployment

MicroShift can be run on the host or inside a Bootc container.
This document describes how to run MicroShift on the host.

See [MicroShift Bootc Deployment](./run-bootc.md) on how to run MicroShift
inside a Bootc container.

## MicroShift - optional packages

The following optional RPM packages are available in the repository. It is
mandatory to install either `microshift-kindnet` or `microshift-networking`
to enable the Kindnet or OVN-K networking support.

| Package               | Description                | Comments |
|-----------------------|----------------------------|----------|
| microshift-kindnet    | Kindnet CNI                | Overrides OVN-K |
| microshift-networking | OVN-K CNI                  | Uninstall Kindnet to enable OVN-K |
| microshift-topolvm    | TopoLVM CSI                | Install to enable storage support |
| microshift-olm        | Operator Lifecycle Manager | See [Operator Hub Catalogs](https://okd.io/docs/operators/) |

## Package-based systems (non-bootc)

### Installing MicroShift

#### Local RPMs

Run the following commands to install MicroShift RPM packages from a local repository.
This repository should be [built locally](./build.md#create-rpm-packages).

```bash
RPM_REPO_DIR=/tmp/microshift-rpms

sudo ./src/rpm/create_repos.sh -create "${RPM_REPO_DIR}"
sudo dnf install -y microshift microshift-kindnet
sudo ./src/rpm/create_repos.sh -delete
```

#### RPMs from COPR

Run following command to enable COPR repository:
```sh
sudo dnf copr enable @microshift-io/microshift
```

Optionally specify chroot like `epel-9-{x86_64,aarch64}`, `fedora-42-{x86_64,aarch64}`, for example:
```sh
sudo dnf copr enable @microshift-io/microshift epel-9-x86_64
sudo dnf copr enable @microshift-io/microshift epel-9-aarch64
sudo dnf copr enable @microshift-io/microshift fedora-42-x86_64
sudo dnf copr enable @microshift-io/microshift fedora-42-aarch64
```

Next, install MicroShift:
```sh
sudo dnf install -y microshift microshift-kindnet
```

#### Local DEB (Ubuntu)

Run the following command to install MicroShift DEB packages from the local
repository copied from the build container image.
See [Create DEB Packages](./build.md#create-deb-packages) for more information.

```bash
DEB_REPO_DIR=/tmp/microshift-rpms/deb
sudo ./src/deb/install.sh "${DEB_REPO_DIR}"
```

### Start MicroShift Service

On RPM-based systems, run the following commands to configure the minimum
required firewall rules, disable LVMS, and enable the MicroShift service.
Skip this command on Ubuntu.

```bash
sudo ./src/rpm/postinstall.sh
```

Run the following command to start the MicroShift service.

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
