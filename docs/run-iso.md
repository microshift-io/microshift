# MicroShift ISO Deployment

MicroShift ISO can be installed on a physical host or a virtual machine.
This document describes how to install MicroShift ISO inside a virtual machine.

> Hardware-level configuration is host-dependent and excluded from this document
> to maintain a vendor-neutral deployment guide.

## Prerequisites

### Virtualization

The procedures described in this document must be run on a physical hypervisor host
of the supported `x86_64` or `aarch64` architecture. The [libvirt](https://libvirt.org/)
toolkit for managing virtualization platforms is used for starting virtual machines.

### Kickstart

MicroShift ISO uses [Anaconda Installer](https://anaconda-installer.readthedocs.io/),
which can be customized using [Kickstart](https://anaconda-installer.readthedocs.io/en/latest/kickstart.html).

It is recommended to customize the system with user-specific settings like
hostname, user names and passwords, SSH keys, disk partitioning, etc.

An opinionated example of such a customization can be found at [kickstart.ks.template](../src/iso/kickstart.ks.template).
The file is used during the installation procedures described below.

### Installer Types

Two installation techniques are presented below:
- Using a custom ISO installer with an embedded Bootc container image
- Using a stock ISO installer image with a Bootc container image from registry

> Stock ISO deployment is recommended for most use cases to minimize maintenance.
> Custom builds are reserved for specific environmental needs that fall outside
> the scope of Kickstart automation.

When using a custom ISO installer, follow the instructions in [Create ISO](./build.md#create-iso)
to build the ISO installer.

When using a stock ISO installer, download it from one of the following sites.

| OS        | Link            |
|-----------|-----------------|
| Fedora    | [Booting via ISO](https://docs.fedoraproject.org/en-US/fedora-coreos/live-booting/#_booting_via_iso) |
| CentOS 10 | [x86_64](https://mirror.stream.centos.org/10-stream/BaseOS/x86_64/iso/) [aarch64](https://mirror.stream.centos.org/10-stream/BaseOS/aarch64/iso/) |
| CentOS 9  | [x86_64](https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/iso/) [aarch64](https://mirror.stream.centos.org/9-stream/BaseOS/aarch64/iso/) |

## Installation

Follow instructions in one of [Custom ISO](#custom-iso) or [Stock ISO](#stock-iso)
sections below, depending on the installation type of choice.

### Custom ISO

Copy the `install.iso` file to the `/var/lib/libvirt/images` directory and set
the following variables to be used during the virtual machine creation.

```bash
VMNAME="microshift-okd"
NETNAME="default"
ISOFILE="install.iso"
```

Convert the kickstart template to a configuration suitable for the custom ISO
installation by resetting transport and URL variables.

```bash
KSTEMP="./src/iso/kickstart.ks.template"
KSFILE=/tmp/kickstart-custom-iso.ks

# Loading the bootc image bundled in the ISO
export BOOTC_IMAGE_TRANSPORT=oci
export BOOTC_IMAGE_URL=/run/install/repo/container

envsubst '${BOOTC_IMAGE_TRANSPORT} ${BOOTC_IMAGE_URL}' \
    < "${KSTEMP}" > "${KSFILE}"
```

Run the following commands to create a virtual machine. You can watch the
installation progress at the console of the created virtual machine.

```bash
# Always use a full path for kickstart files
KSFILE="$(readlink -f "${KSFILE}")"

sudo bash -c " \
cd /var/lib/libvirt/images/ && \
virt-install \
    --name "${VMNAME}" \
    --vcpus 2 \
    --memory 3072 \
    --disk "path=./${VMNAME}.qcow2,size=20" \
    --network "network=${NETNAME},model=virtio" \
    --events on_reboot=restart \
    --location "${ISOFILE}" \
    --initrd-inject "${KSFILE}" \
    --extra-args "inst.ks=file:/$(basename "${KSFILE}") console=tty0" \
    --wait \
"
```

The virtual machine should reboot in the event of a successful installation and
present a user login prompt.

### Stock ISO

Download an ISO from one of the locations mentioned in the [Installer Types](#installer-types)
and copy the file to the `/var/lib/libvirt/images` directory.
Set the following variables to be used during the virtual machine creation.

```bash
VMNAME="microshift-okd"
NETNAME="default"
ISOFILE="CentOS-Stream-10-latest-$(uname -m)-boot.iso"
```

Convert the kickstart template to a configuration suitable for the stock ISO
installation by resetting transport and URL variables.

```bash
KSTEMP="./src/iso/kickstart.ks.template"
KSFILE=/tmp/kickstart-stock-iso.ks

# Loading the bootc image from a container registry
export BOOTC_IMAGE_TRANSPORT=registry
export BOOTC_IMAGE_URL="ghcr.io/microshift-io/microshift:<IMAGE_TAG>"

envsubst '${BOOTC_IMAGE_TRANSPORT} ${BOOTC_IMAGE_URL}' \
    < "${KSTEMP}" > "${KSFILE}"
```

Run the following commands to create a virtual machine. You can watch the
installation progress at the console of the created virtual machine.

```bash
# Always use a full path for kickstart files
KSFILE="$(readlink -f "${KSFILE}")"

sudo bash -c " \
cd /var/lib/libvirt/images/ && \
virt-install \
    --name "${VMNAME}" \
    --vcpus 2 \
    --memory 3072 \
    --disk "path=./${VMNAME}.qcow2,size=20" \
    --network "network=${NETNAME},model=virtio" \
    --events on_reboot=restart \
    --location "${ISOFILE}" \
    --initrd-inject "${KSFILE}" \
    --extra-args "inst.ks=file:/$(basename "${KSFILE}") console=tty0" \
    --wait \
"
```

The virtual machine should reboot in the event of a successful installation and
present a user login prompt.

## Login

Log into the virtual machine console by running the following command. Enter the
`microshift:microshift` credentials when prompted.

```bash
sudo virsh console --force "${VMNAME}"
```

Verify that all the MicroShift services are up and running successfully.
```bash
sudo oc get nodes
sudo oc get pods -A
```

## Cleanup

Run the following commands to shut down and delete the virtual machine.

```bash
sudo virsh destroy "${VMNAME}"
sudo virsh undefine "${VMNAME}"
sudo rm -f "/var/lib/libvirt/images/${VMNAME}.qcow2"
```
