## Build MicroShift Upstream

### Overview
The build process is containerized and it includes the following steps:

1. Replace the MicroShift payload/images with the OKD [released images](https://github.com/okd-project/okd-scos/releases).
1. Build the MicroShift RPMs and repository from the MicroShift sources.
1. Build the `microshift-okd` Bootc container based on CentOS Stream.

### Build Arguments and Options

The following arguments can be specified in the build command using the
`--build-arg NAME=VAL` format.

|Name           |Required|Default|Comments
|---------------|--------|-------|--------
|USHIFT_BRANCH  |no      |main   |[List of branches](https://github.com/openshift/microshift/branches)
|OKD_VERSION_TAG|yes     |none   |[List of tags](https://quay.io/repository/okd/scos-release?tab=tags)

The following options can be specified in the build command using
the `--build-env NAME=VAL` format.

|Name                  |Required|Default|Comments
|----------------------|--------|-------|--------
|WITH_KINDNET          |no      |1      |OVK-K CNI is used when Kindnet is disabled
|WITH_TOPOLVM          |no      |1      |Enable [TopoLVM](https://github.com/topolvm/topolvm) CSI
|WITH_OLM              |no      |0      |Enable OLM support
|EMBED_CONTAINER_IMAGES|no      |0      |Embed all component container dependencies in Bootc images

### Build MicroShift RPMs

Run the following command to build MicroShift RPMs based on CentOS Stream 9
operating system.

Note that the `--target builder` option only enabled the necessary RPM build steps
without proceeding with the Bootc image creation.

```bash
USHIFT_BRANCH=release-4.19
OKD_VERSION_TAG=4.19.0-okd-scos.19

sudo podman build --target builder \
    --build-arg USHIFT_BRANCH="${USHIFT_BRANCH}" \
    --build-arg OKD_VERSION_TAG="${OKD_VERSION_TAG}" \
    -t microshift-okd -f packaging/microshift-cos9.Containerfile .
```

If the build completes successfully, run the following commands to copy the RPM
packages from the container image to the host file system. The MicroShift RPM
repository is copied to the `OUTPUT_DIR` directory on the host.

```bash
OUTPUT_DIR=/tmp/microshift-rpms
mkdir -p "${OUTPUT_DIR}"

mdir=$(sudo podman image mount microshift-okd)
sudo cp -r "${mdir}/microshift/_output/rpmbuild/RPMS/." "${OUTPUT_DIR}"
sudo podman image umount microshift-okd
```

The packages from this repository can be used to install MicroShift on the
supported operating systems.

### Build MicroShift Bootc Image

Run the following command to build a MicroShift Bootc image based on CentOS
Stream 9 operating system with the default options.

```bash
USHIFT_BRANCH=release-4.19
OKD_VERSION_TAG=4.19.0-okd-scos.19

sudo podman build \
    --build-arg USHIFT_BRANCH="${USHIFT_BRANCH}" \
    --build-arg OKD_VERSION_TAG="${OKD_VERSION_TAG}" \
    -t microshift-okd -f packaging/microshift-cos9.Containerfile .
```

As an example of non-default options, run the following command to embed all
component container image dependencies during the build.

```bash
USHIFT_BRANCH=release-4.19
OKD_VERSION_TAG=4.19.0-okd-scos.19

sudo podman build \
    --build-env EMBED_CONTAINER_IMAGES=1 \
    --build-arg USHIFT_BRANCH="${USHIFT_BRANCH}" \
    --build-arg OKD_VERSION_TAG="${OKD_VERSION_TAG}" \
    -t microshift-okd -f packaging/microshift-cos9.Containerfile .
```
