## Build MicroShift Upstream

### Overview
The build process is containerized and it includes the following steps:

1. Replace the MicroShift payload/images with the OKD [released images](https://github.com/okd-project/okd-scos/releases).
1. Build the MicroShift RPMs and repository from the MicroShift sources.
1. Build the `microshift-okd` Bootc container based on CentOS Stream.

### Build Options

Building MicroShift artifacts is performed by running `make rpm` or `make image`
commands.

The following options can be specified in the make command line using the
`NAME=VAL` format.

|Name                  |Required|Default|Comments
|----------------------|--------|-------|--------
|USHIFT_BRANCH         |no      |main   |[List of branches](https://github.com/openshift/microshift/branches)
|OKD_VERSION_TAG       |yes     |       |[List of tags](https://quay.io/repository/okd/scos-release?tab=tags)
|WITH_KINDNET          |no      |1      |OVK-K CNI is used when Kindnet is disabled
|WITH_TOPOLVM          |no      |1      |Enable [TopoLVM](https://github.com/topolvm/topolvm) CSI
|WITH_OLM              |no      |0      |Enable OLM support
|EMBED_CONTAINER_IMAGES|no      |0      |Embed all component container dependencies in Bootc images

### Build MicroShift RPMs

Run the `make rpm` command to build MicroShift RPMs based on CentOS Stream 9
operating system.

```
USHIFT_BRANCH=release-4.19
OKD_VERSION_TAG=4.19.0-okd-scos.19

make rpm \
  USHIFT_BRANCH="${USHIFT_BRANCH}" \
  OKD_VERSION_TAG="${OKD_VERSION_TAG}"
```

If the build completes successfully, the MicroShift RPM repository is copied to
a temporary directory on the host. The packages from this repository can be used
to install MicroShift on the supported operating systems.

Note: The path to the temporary directory is displayed in the end of the build procedure.

### Build MicroShift Bootc Image

Run the `make image` command to build a MicroShift Bootc image based on CentOS
Stream 9 operating system with the default options.

```bash
USHIFT_BRANCH=release-4.19
OKD_VERSION_TAG=4.19.0-okd-scos.19

make image \
  USHIFT_BRANCH="${USHIFT_BRANCH}" \
  OKD_VERSION_TAG="${OKD_VERSION_TAG}"
```

If the build completes successfully, the `microshift-okd` image is created.
