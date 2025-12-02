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

## Operating System Support

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

## Quick Start

Prebuilt MicroShift artifacts are published at the
[Releases](https://github.com/microshift-io/microshift/releases) page.
MicroShift can be run on the host or inside a Bootc container.

* Install the [latest](https://github.com/microshift-io/microshift/releases/latest)
  MicroShift RPM packages on your host and start the MicroShift service.

  ```bash
  curl -s https://microshift-io.github.io/microshift/quickrpm.sh | sudo bash
  ```

* Bootstrap the [latest](https://github.com/microshift-io/microshift/releases/latest)
  MicroShift build inside a Bootc container on your host.

  ```bash
  curl -s https://microshift-io.github.io/microshift/quickstart.sh | sudo bash
  ```

When completed successfully, the commands displays information about the system
setup, next steps for accessing MicroShift and uninstall instructions.

## Documentation

* [Build MicroShift](./docs/build.md)
* [Versioning Scheme](./docs/versioning.md)
* [MicroShift Host Deployment](./docs/run.md)
* [MicroShift Bootc Deployment](./docs/run-bootc.md)
* [GitHub Workflows](./docs/workflows.md)
