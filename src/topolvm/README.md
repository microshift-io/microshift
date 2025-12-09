# TopoLVM Upstream Integration with MicroShift

## Overview

TopoLVM is a CSI (Container Storage Interface) driver that provides logical
volume management using LVM, enabling dynamic provisioning, volume resizing,
and topology-aware scheduling.

[TopoLVM](https://github.com/topolvm/topolvm) is integrated with [MicroShift](https://github.com/openshift/microshift)
downstream by generating manifests from helm charts.

## Deployment

Run the `src/topolvm/generate_manifests.sh` script to generate the TopoLVM manifests
in `src/topolvm/assets` and container image references in `src/topolvm/release`.

This script will:
- Download cert-manager manifests from the upstream repository
- Download and template the upstream TopoLVM Helm chart
- Patch it for compatibility with MicroShift by changing deployment replicas to 1
- Display a path to the generated manifests and release info

```
$ ./src/topolvm/generate_manifests.sh
...
...
Manifests generated in /home/microshift/microshift-io/src/topolvm/assets

$ ls -1 /home/microshift/microshift-io/src/topolvm/assets
01-namespace.yaml
02-topolvm.yaml
kustomization.yaml
```

## Integrating with MicroShift RPMs

The `make rpm` command of the upstream repository first builds the original
MicroShift RPM files. In the second pass, the command copies the TopoLVM
assets into the downstream directory structure. The command then uses the
downstream RPM build facilities to generate the TopoLVM RPM files.

The TopoLVM RPM files are built using the following command:

```bash
cd ~/microshift
MICROSHIFT_VARIANT=community make rpm
```

## Service CA Cert Injection Instead of Cert-Manager

Instead of deploying and managing a full cert-manager stack, MicroShift uses [OpenShift Service CA Operator](https://docs.openshift.com/container-platform/latest/security/certificate_types_descriptions/service-ca-certificates.html) to automate TopoLVM certificate creation. We annotate the TopoLVM Service and MutatingWebhookConfiguration resources, which triggers the Service CA Operator in MicroShift/OKD to inject valid serving certificates.

This approach is lighter-weight than running cert-manager, minimizing dependencies and reducing resource consumption. 

