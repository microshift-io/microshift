# MicroShift Upstream

This repository provides scripts to build and run [MicroShift](https://github.com/openshift/microshift/)
upstream (i.e. without Red Hat subscriptions or a pull secrets).

## Overview

MicroShift is a project that optimizes OpenShift Kubernetes for small form factor
and edge computing. MicroShift Upstream is intended for upstream development and
testing by allowing to build MicroShift directly from the original OpenShift MicroShift
sources, while replacing the default payload images with OKD (the community distribution
of Kubernetes that powers OpenShift).

The goal is to enable contributors and testers to work with an upstream build of MicroShift
set up using OKD components, making it easier to develop, verify, and iterate on features
outside the downstream Red Hat payloads.

# Operating System Support

MicroShift and its main components are available for the `x86_64` and `aarch64`
architectures. RPM and DEB packages built in a container can be installed and
run on the following operating systems.

| OS        |Package|Bootc|OVN-K|Kindnet|TopoLVM|Greenboot|Comments|
|-----------|-------|-----|-----|-------|-------|---------|--------|
| CentOS 9  |  RPM  |  Y  |  Y  |   Y   |   Y   |    Y    | Latest version in Stream 9 |
| CentOS 10 |  RPM  |  Y  |  Y  |   Y   |   Y   |    Y    | Latest version in Stream 10 |
| Fedora    |  RPM  |  Y  |  N  |   Y   |   Y   |    Y    | Latest released version (e.g. 42) |
| Ubuntu    |  DEB  |  N  |  N  |   Y   |   Y   |    N    | Latest LTS version (e.g. 24.04) |

Notes:
- MicroShift Bootc container images can be run on `x86_64` and `aarch64` systems
  using any OS supported by [Podman](https://podman.io/).
- OKD builds for the `aarch64` architecture are performed using MicroShift-specific
  build procedure until [OKD Build of OpenShift on Arm](https://issues.redhat.com/browse/OKD-215)
  is implemented by the OKD team.

# Version scheme

Upstream packages are based on MicroShift's code and OKD's images.
To allow for easy identification and tracking back of what's included in the package,
following version scheme is used: `MICROSHIFT_VERSION`-g`MICROSHIFT_GIT_COMMIT`-`OKD_VERSION`:

- `MICROSHIFT_VERSION` can have two forms:
  - `X.Y.Z-YYYYMMDDHHSS.pN` or `X.Y.Z-{e,r}c.M-YYYYMMDDHHSS.pN` if it's based on [openshift/microshift's tag](https://github.com/openshift/microshift/tags).
  - `X.Y.Z` if it was build against a branch (e.g. `main` or `release-X.Y`), value of `X.Y.Z` is  based on version stored in `Makefile.version.*.var` file.
- `MICROSHIFT_GIT_COMMIT` is the [openshift/microshift](https://github.com/openshift/microshift) commit.
- `OKD_VERSION` is tag of the OKD release image from which the component image references are sourced.

Examples:
- `4.21.0_ga9cd00b34_4.21.0_okd_scos.ec.5`
  - Missing `YYYYMMDDHHSS.pN` means it was built against a branch, not a tag (release)
  - `4.21.0` means that commit [a9cd00b34](https://github.com/openshift/microshift/commit/a9cd00b341191e2091937a1f982168964c105297) was part of 4.21 release (but it could be built from main)
  - Component image references are sourced from [4.21.0-okd-scos.ec.5 release](https://github.com/okd-project/okd/releases/tag/4.21.0-okd-scos.ec.5)
- `4.20.0-202510201126.p0-g1c4675ace_4.20.0-okd-scos.6`
  - `202510201126.p0` is present which means it was built from [MicroShift's release tag 4.20.0-202510201126.p0](https://github.com/openshift/microshift/releases/tag/4.20.0-202510201126.p0)
  - MicroShift's tag points to [1c4675ace](https://github.com/openshift/microshift/commit/1c4675ace39e1ef9c4919218c15d21e8793f6254) commit.
  - Component image references are sourced from [4.20.0-okd-scos.6 release](https://github.com/okd-project/okd/releases/tag/4.20.0-okd-scos.6)

## Quick Start

Prebuilt MicroShift artifacts are published at the
[Releases](https://github.com/microshift-io/microshift/releases) page.

Run the following command to quickly run the latest build of MicroShift inside a
Bootc container on your host.

```bash
curl -s https://microshift-io.github.io/microshift/quickstart.sh | sudo bash
```

When completed successfully, the command displays information about the system
setup, next steps for accessing MicroShift and uninstall instructions.

```text
MicroShift is running in a bootc container
Hostname:  127.0.0.1.nip.io
Container: microshift-okd
LVM disk:  /var/lib/microshift-okd/lvmdisk.image
VG name:   myvg1

To access the container, run the following command:
 - sudo podman exec -it microshift-okd /bin/bash

To verify that MicroShift pods are up and running, run the following command:
 - sudo podman exec -it microshift-okd oc get pods -A

To uninstall MicroShift, run the following command:
 - curl -s https://microshift-io.github.io/microshift/quickclean.sh | sudo bash
```

## Documentation

* [Build MicroShift](./docs/build.md)
* [MicroShift Host Deployment](./docs/run.md)
* [MicroShift Bootc Deployment](./docs/run-bootc.md)
* [GitHub Workflows](./docs/workflows.md)
