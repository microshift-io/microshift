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

### Build Options

Building MicroShift artifacts is performed by running `make rpm` or `make image`
commands.

The following options can be specified in the make command line using the
`NAME=VAL` format.

| Name                   | Required | Default  | Comments
|------------------------|----------|----------|---------
| USHIFT_BRANCH          | no       | main     | MicroShift repository branch used in `make rpm` command<br>[List of branches](https://github.com/openshift/microshift/branches)
| OKD_VERSION_TAG        | no       | latest   | OKD version tag used in `make rpm` command<br>[List of tags](https://quay.io/repository/okd/scos-release?tab=tags)
| RPM_OUTDIR             | no       | /tmp/... | RPM repository output directory for `make rpm` command
| WITH_KINDNET           | no       | 1        | OVK-K CNI is used when Kindnet is disabled
| WITH_TOPOLVM           | no       | 1        | Enable [TopoLVM](https://github.com/topolvm/topolvm) CSI
| WITH_OLM               | no       | 0        | Enable OLM support
| EMBED_CONTAINER_IMAGES | no       | 0        | Embed all component container dependencies in Bootc images
| BOOTC_IMAGE_URL        | no       | quay.io/centos-bootc/centos-bootc | Base Bootc image URL used in `make image` command
| BOOTC_IMAGE_TAG        | no       | stream9  | Base Bootc image tag used in `make image` command

### Build MicroShift RPMs

Run the following command to build MicroShift RPMs based on CentOS Stream 9
operating system. The `main` MicroShift repository branch and the latest OKD
version tag are used by default if unspecified.

```
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

### Build MicroShift Bootc Image

Run the following command to build a MicroShift Bootc image based on CentOS
Stream 9 operating system with the default options. The command uses artifacts
from the `microshift-okd-builder` container image created by `make rpm`.

```bash
make image
```

If the build completes successfully, the `microshift-okd` image is created.

Note: The base operating system image used to run MicroShift can be overriden by
specifying `BOOTC_IMAGE_URL=value` and `BOOTC_IMAGE_TAG=value` make command line
arguments.
