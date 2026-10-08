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

## Configurable Volume Group

TopoLVM's lvmd configuration is created at build time and installed at `/etc/topolvm/lvmd.yaml`.

### Bootc Container Deployments

The default image configuration uses the Makefile's default `VG_NAME`:

```bash
make image
make run
```

To generate the image configuration for a different volume group, pass the same explicit `VG_NAME` when building and running:

```bash
make image VG_NAME=my-custom-vg
make run VG_NAME=my-custom-vg
```

To supply the complete configuration, set `LVMD_CONFIG_FILE`. Relative and absolute paths are accepted, and the file is copied unchanged:

```bash
make image VG_NAME=my-custom-vg LVMD_CONFIG_FILE=./lvmd.yaml
make run VG_NAME=my-custom-vg
```

The custom file is not validated or rewritten. Its volume group must match `VG_NAME`. `LVMD_CONFIG_FILE` is ignored when `WITH_TOPOLVM=0`.

At runtime, `cluster_manager.sh` creates the loopback volume group and verifies the build-time configuration exists. It never modifies the configuration.

### Bare Metal / VM Deployments

The `microshift-topolvm` RPM installs the inherited `VG_NAME` configuration at `/etc/topolvm/lvmd.yaml` as `%config(noreplace)`. Build a different packaged default with `make rpm VG_NAME=my-custom-vg`, or replace the file before starting MicroShift:

```bash
# Create custom lvmd configuration
sudo mkdir -p /etc/topolvm
sudo tee /etc/topolvm/lvmd.yaml <<EOF
socket-name: /run/topolvm/lvmd.sock
device-classes:
  - default: true
    name: ssd
    spare-gb: 0
    volume-group: my-custom-vg
EOF

# Ensure your LVM volume group exists
sudo vgcreate my-custom-vg /dev/sdX

# Start MicroShift
sudo systemctl start microshift.service
```

### Verification

TopoLVM has one lvmd configuration source:

```bash
kubectl exec -n topolvm-system daemonset/topolvm-lvmd-0 -c lvmd -- \
  cat /etc/topolvm/lvmd.yaml
```
