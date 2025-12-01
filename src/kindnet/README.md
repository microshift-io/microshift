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

### Kindnet

Run the `src/kindnet/generate_kindnet_manifests.sh` script to generate the Kindnet
manifests in `src/kindnet/assets/kindnet`.

This script will:
- Generate namespace, RBAC, and DaemonSet manifests for Kindnet
- Generate kustomization files with architecture-specific image references
- Display a path to the generated manifests

```
$ ./src/kindnet/generate_kindnet_manifests.sh
Generating kindnet manifests for kindnetd...
kindnet manifests generated in /home/microshift/microshift-io/src/kindnet/assets/kindnet

$ ls -1 /home/microshift/microshift-io/src/kindnet/assets/kindnet
00-namespace.yaml
01-service-account.yaml
02-cluster-role.yaml
03-cluster-role-binding.yaml
04-daemonset.yaml
kustomization.yaml
kustomization.aarch64.yaml
kustomization.x86_64.yaml
```

### Kube-Proxy

Run the `src/kindnet/generate_kube_proxy_manifests.sh` script to generate the
Kube-proxy manifests in `src/kindnet/assets/kube-proxy`.

This script will:
- Generate namespace, RBAC, ConfigMap, and DaemonSet manifests for Kube-proxy
- Generate kustomization files with architecture-specific image references
- Display a path to the generated manifests

```
$ ./src/kindnet/generate_kube_proxy_manifests.sh
Generating kube-proxy manifests...
kube-proxy manifests generated in /home/microshift/microshift-io/src/kindnet/assets/kube-proxy

$ ls -1 /home/microshift/microshift-io/src/kindnet/assets/kube-proxy
00-namespace.yaml
01-service-account.yaml
02-cluster-role.yaml
03-cluster-role-binding.yaml
04-configmap.yaml
05-daemonset.yaml
kustomization.yaml
kustomization.aarch64.yaml
kustomization.x86_64.yaml
```

## Updating Image References

Image digests are stored in release JSON files:
- `src/kindnet/assets/kindnet/release-kindnet-{aarch64,x86_64}.json`
- `src/kindnet/assets/kube-proxy/release-kube-proxy-{aarch64,x86_64}.json`

To update to a new version, update the image references in these JSON files and
re-run the corresponding generation script.

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
