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

## Build and Run

* [Build MicroShift Upstream](./docs/build.md)
* [Run MicroShift Upstream](./docs/run.md)
