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

TopoLVM's lvmd can be configured to use a custom LVM volume group at runtime without rebuilding container images.

### Bootc Container Deployments

When using `cluster_manager.sh`, the volume group is automatically configured via the `VG_NAME` environment variable:

```bash
# Use custom volume group name
VG_NAME=my-custom-vg make run

# Or set it directly when calling cluster_manager.sh
VG_NAME=storage-vg ./src/cluster_manager.sh create
```

The `cluster_manager.sh` script:
1. Creates the LVM volume group with the specified name
2. Generates a matching lvmd.yaml configuration
3. Injects it into the container at `/var/lib/microshift-topolvm/lvmd.yaml`

### Bare Metal / VM Deployments

For host installations, create the override configuration file before starting MicroShift:

```bash
# Create custom lvmd configuration
sudo mkdir -p /var/lib/microshift-topolvm
sudo tee /var/lib/microshift-topolvm/lvmd.yaml <<EOF
socket-name: /run/topolvm/lvmd.sock
device-classes:
  - default: true
    name: ssd
    spare-gb: 10
    volume-group: my-custom-vg
EOF

# Ensure your LVM volume group exists
sudo vgcreate my-custom-vg /dev/sdX

# Start MicroShift
sudo systemctl start microshift.service
```

### Fallback Behavior

If no override configuration exists at `/var/lib/microshift-topolvm/lvmd.yaml`, lvmd automatically falls back to the default configuration from the ConfigMap (volume group: `myvg1`). This ensures backwards compatibility with existing deployments.

### Verification

To verify which configuration lvmd is using:

```bash
# For bootc containers
sudo podman exec -it microshift-okd-1 bash -c \
  "cat /var/lib/microshift-topolvm/lvmd.yaml 2>/dev/null || echo 'Using default ConfigMap'"

# For bare metal
sudo cat /var/lib/microshift-topolvm/lvmd.yaml 2>/dev/null || echo "Using default ConfigMap"
```

To check the active volume group in lvmd:

```bash
# Get into the lvmd pod
kubectl exec -n topolvm-system daemonset/topolvm-lvmd-0 -c lvmd -- \
  sh -c 'cat /etc/topolvm/lvmd.yaml 2>/dev/null || cat /var/lib/microshift-topolvm/lvmd.yaml'
``` 

