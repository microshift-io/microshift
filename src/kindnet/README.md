# Kindnet and Kube-Proxy Upstream Integration with MicroShift

## Overview

Kindnet is a simple CNI (Container Network Interface) plugin that provides basic
networking capabilities for Kubernetes clusters. It is lightweight and designed
for single-node or small cluster deployments.

Kube-proxy is the Kubernetes network proxy that runs on each node, maintaining
network rules and enabling Service abstraction by forwarding connections to pods.

[Kindnet](https://github.com/kubernetes-sigs/kind/tree/main/images/kindnetd) and
[Kube-proxy](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-proxy/)
are integrated with [MicroShift](https://github.com/openshift/microshift) downstream
by generating manifests from upstream configurations.

## Deployment

Run the `src/kindnet/generate_manifests.sh` script to generate both Kindnet and
Kube-proxy manifests.

This script will:
- Fetch the latest Kindnet image from Docker Hub (`docker.io/kindest/kindnetd`)
- Fetch the latest Kube-proxy image from Quay.io (`quay.io/okd/scos-content`) matching the configured version
- Generate namespace, RBAC, and DaemonSet manifests for Kindnet
- Generate namespace, RBAC, ConfigMap, and DaemonSet manifests for Kube-proxy
- Generate kustomization files with architecture-specific image references
- Generate release JSON files with the resolved image digests

```
$ ./src/kindnet/generate_manifests.sh
=========================================
Generating kindnet and kube-proxy manifests
=========================================

Fetching latest kindnet image info...
Latest kindnet tag: v20250512-df8de77b
 - aarch64 digest: sha256:2bdc3188f2ddc8e54841f69ef900a8dde1280057c97500f966a7ef31364021f1
 - x86_64 digest: sha256:7a9c9fa59dd517cdc2c82eef1e51392524dd285e9cf7cb5a851c49f294d6cd11

Fetching latest kube-proxy image info...
Latest kube-proxy tag: 4.20.0-okd-scos.11-kube-proxy
 - aarch64 digest: sha256:...
 - x86_64 digest: sha256:182c4934a99762929597de8a3dce9c5980dc957eaa599199eb63f65669bd2643

Generating kindnet manifests...
kindnet manifests generated in /home/microshift/microshift-io/src/kindnet/assets/kindnet

Generating kube-proxy manifests...
kube-proxy manifests generated in /home/microshift/microshift-io/src/kindnet/assets/kube-proxy

=========================================
All manifests generated successfully!
=========================================
```

## Updating Image References

The script automatically fetches the latest images from upstream:
- **Kindnet**: Fetches the latest tag from Docker Hub
- **Kube-proxy**: Fetches the latest tag matching `KUBE_PROXY_VERSION` (configured in the script) from Quay.io

To update to a new version, simply re-run the generation script. To change the
Kube-proxy version, edit the `KUBE_PROXY_VERSION` variable in `generate_manifests.sh`.

Image digests are stored in release JSON files after generation:
- `src/kindnet/assets/kindnet/release-kindnet-{aarch64,x86_64}.json`
- `src/kindnet/assets/kube-proxy/release-kube-proxy-{aarch64,x86_64}.json`

## Integrating with MicroShift RPMs

The `make rpm` command of the upstream repository first builds the original
MicroShift RPM files. In the second pass, the command copies the Kindnet and
Kube-proxy assets into the downstream directory structure. The command then uses
the downstream RPM build facilities to generate the RPM files.

The RPM files are built using the following command:

```bash
cd ~/microshift
MICROSHIFT_VARIANT=community make rpm
```
