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

MicroShift and its main components are built in a CentOS Stream 9 Bootc container.
The produced RPMs can be installed and run on the following operating systems.

| OS        | Bootc| OVN-K | Kindnet | TopoLVM | Comments |
|-----------|------|-------|---------|---------|----------|
| CentOS 9  |  Y   |   Y   |    Y    |    Y    | Latest version in Stream 9
| CentOS 10 |  Y   |   Y   |    Y    |    Y    | Latest version in Stream 10
| Fedora    |  Y   |   N   |    Y    |    Y    | Latest released version (e.g. 42)

Notes:
- MicroShift is available on the `x86_64` architecture. The support for the
  `aarch64` architecture depends on [OKD Build of OpenShift on Arm](https://issues.redhat.com/browse/OKD-215).
- MicroShift Bootc container images can be run on any operating system supported
  by [Podman](https://podman.io/).

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

* [Build MicroShift Upstream](./docs/build.md)
* [Run MicroShift Upstream](./docs/run.md)
* [GitHub Workflows](./docs/workflows.md)
