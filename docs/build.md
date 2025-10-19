## Build MicroShift Upstream

### Overview

The build process is containerized and it includes the following steps:

1. Replace the MicroShift payload/images with the OKD [released images](https://github.com/okd-project/okd/releases)
1. Build the MicroShift RPMs from the MicroShift [sources](https://github.com/openshift/microshift)
1. Build the `microshift-okd` Bootc container image

### Prerequisites

Install the software necessary for running the build process:

```bash
sudo dnf install -y make podman
```

### Create RPM Packages

Create the MicroShift RPM packages by running the `make rpm` command.

The following options can be specified in the make command line using the `NAME=VAL` format.

| Name            | Required | Default  | Comments |
|-----------------|----------|----------|----------|
| USHIFT_BRANCH   | no       | main     | [MicroShift repository branches](https://github.com/openshift/microshift/branches) |
| OKD_VERSION_TAG | no       | latest   | [OKD version tags](https://quay.io/repository/okd/scos-release?tab=tags) |
| RPM_OUTDIR      | no       | /tmp/... | RPM repository output directory |

The `make rpm` command builds MicroShift RPMs based on CentOS Stream 9 operating
system. The `main` MicroShift repository branch and the latest OKD version tag
are used by default if unspecified.

```bash
make rpm
```

If the build completes successfully, the `microshift-okd-builder` container image
is created and the MicroShift RPM repository is copied to the `RPM_OUTDIR` directory
on the host. The packages from this repository can be used to install MicroShift
on the supported operating systems.

```
...
...
Build completed successfully
RPMs are available in '/tmp/microshift-rpms-EI3IXg'
```

Notes:
- The MicroShift repository branch and the OKD version tag used to build the
  packages can be overriden by specifying `USHIFT_BRANCH` and `OKD_VERSION_TAG`
  make command line arguments.
- The path to the `RPM_OUTDIR` directory (either temporary or specified in
  the `make rpm` command line) is displayed in the end of the build procedure.

### Create DEB Packages

Create the MicroShift DEB packages by running the `make rpm-deb` command.

The following options can be specified in the make command line using the `NAME=VAL` format.

| Name       | Required | Default  | Comments |
|------------|----------|----------|----------|
| RPM_OUTDIR | yes      | none     | RPM repository directory to convert |

The `make rpm-deb` command converts MicroShift RPMs to Debian packages. The path
to an existing RPM repository must be specified using the mandatory `RPM_OUTDIR`
make command line.

```bash
RPM_OUTDIR=/tmp/microshift-rpms
make rpm-deb RPM_OUTDIR="${RPM_OUTDIR}"
```

If the conversion completes successfully, the Debian packages are copied to the
`${RPM_OUTDIR}/deb` directory on the host. The packages from this directory can
be used to install MicroShift on the supported operating systems.

```
...
...
Conversion completed successfully"
Debian packages are available in '/tmp/microshift-rpms/deb'"
```

### Create Bootc Image

Create the MicroShift Bootc image by running the `make image` command.

The following options can be specified in the make command line using the `NAME=VAL` format.

| Name                   | Required | Default  | Comments
|------------------------|----------|----------|---------
| BOOTC_IMAGE_URL        | no       | quay.io/centos-bootc/centos-bootc | Base Bootc image URL
| BOOTC_IMAGE_TAG        | no       | stream9  | Base Bootc image tag
| WITH_KINDNET           | no       | 1        | OVK-K CNI is used when Kindnet is disabled
| WITH_TOPOLVM           | no       | 1        | Enable [TopoLVM](https://github.com/topolvm/topolvm) CSI
| WITH_OLM               | no       | 0        | Enable OLM support
| EMBED_CONTAINER_IMAGES | no       | 0        | Embed all component container dependencies in Bootc images

The `make image` command builds a MicroShift Bootc image based on CentOS Stream 9
operating system with the default options. The command uses artifacts from the
`microshift-okd-builder` container image created by `make rpm`.

```bash
make image
```

If the build completes successfully, the `microshift-okd` image is created.

> The base operating system image used to run MicroShift can be overriden by
> specifying `BOOTC_IMAGE_URL=value` and `BOOTC_IMAGE_TAG=value` make command line
> arguments.
