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
- Fetch the latest Kube-proxy image from the official Kubernetes registry (`registry.k8s.io/kube-proxy`)
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
Latest kube-proxy tag: v1.34.2
 - aarch64 digest: sha256:20a31b16a001e3e4db71a17ba8effc4b145a3afa2086e844ab40dc5baa5b8d12
 - x86_64 digest: sha256:1512fa1bace72d9bcaa7471e364e972c60805474184840a707b6afa05bde3a74

Generating kindnet manifests...
kindnet manifests generated in /home/microshift/microshift-io/src/kindnet/assets/kindnet

Generating kube-proxy manifests...
kube-proxy manifests generated in /home/microshift/microshift-io/src/kindnet/assets/kube-proxy

=========================================
All manifests generated successfully!
=========================================
```

## Pod Network

Kindnet and Kube-proxy have to agree with MicroShift's `network.clusterNetwork`
setting, which defaults to `10.42.0.0/16`.

- **Kindnet** reads its pod subnet from the `podSubnet` key of the
  `kindnet-config` ConfigMap in the `kube-kindnet` namespace. Kindnet masquerades
  traffic to every destination outside this range. If the value does not match
  the cluster network, connections into pods are masqueraded as well, and pods
  such as the router see the node's address on the pod network instead of the
  client address.
- **Kube-proxy** needs no CIDR. It recognises pod traffic by the node's
  `spec.podCIDRs` (`detectLocalMode: NodeCIDR`), which MicroShift allocates from
  `clusterNetwork`.

### Using a Different Cluster Network

The packaged `kindnet-config` ConfigMap carries the default. For a cluster with
a different `network.clusterNetwork`, set `podSubnet` to the same value; for a
dual-stack cluster, separate both CIDRs with a comma.

Do not add a second `kindnet-config` ConfigMap somewhere in
`manifests.kustomizePaths`. MicroShift applies the kustomization paths one after
another on every start, so the packaged manifest resets `podSubnet` to the
default before the override is applied again. A kindnet pod that starts in
between, typically after a reboot, keeps the default and masquerades traffic
into the pods. The value has to be written in one place only:

- **Image mode (bootc) or container:** replace
  `/usr/lib/microshift/manifests.d/000-microshift-kindnet/00-kindnet-config.yaml`
  in a derived image, or bind-mount a replacement file.
- **Package installation:** take the packaged kindnet kustomization out of
  `manifests.kustomizePaths` and apply it through an overlay that patches only
  the pod subnet, as shown below.

`/etc/microshift/config.d/10-kindnet-pod-subnet.yaml`:

```yaml
network:
  clusterNetwork:
    - 10.100.0.0/16
manifests:
  kustomizePaths:
    - /usr/lib/microshift/manifests
    # Every packaged directory except 000-microshift-kindnet, one by one.
    # See the first caveat below.
    - /usr/lib/microshift/manifests.d/000-microshift-kube-proxy
    - /etc/microshift/manifests
    - /etc/microshift/manifests.d/*
```

`/etc/microshift/manifests.d/010-kindnet-pod-subnet/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  # kustomize does not accept an absolute path here
  - ../../../../usr/lib/microshift/manifests.d/000-microshift-kindnet
patches:
  - patch: |-
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: kindnet-config
        namespace: kube-kindnet
      data:
        podSubnet: 10.100.0.0/16
```

The overlay builds on the installed package, so updates of the kindnetd image
or the DaemonSet are picked up without touching it. If a future package renames
the ConfigMap, the patch fails and MicroShift logs the failed kustomization. A
renamed key is not detected; see the caveats below.

> [!IMPORTANT]
> **Caveats of the package installation variant**
>
> - **Packages installed later are not applied.** The glob
>   `/usr/lib/microshift/manifests.d/*` cannot exclude a single directory, so
>   the list names every packaged directory explicitly. A package installed
>   later, for example `microshift-topolvm`, `microshift-olm` or
>   `microshift-gateway-api`, places its manifests in
>   `/usr/lib/microshift/manifests.d`, but MicroShift does not apply them
>   until the directory is added to the list. Nothing reports this. After
>   installing or removing packages, compare
>   `ls /usr/lib/microshift/manifests.d` with the list in
>   `microshift show-config`.
> - **A renamed key goes unnoticed.** If a future package reads the pod subnet
>   from a different key of `kindnet-config`, the patch does not fail: it adds
>   `podSubnet` next to the new key, and kindnet silently runs with the
>   packaged default again. After package updates, check the value kindnet
>   actually uses, as shown at the end of this section.
> - **A changed value needs more than a restart of kindnet.** Switching an
>   existing cluster to the overlay, or changing the value later, leaves the
>   running nodes with outdated masquerade rules. See
>   [Changing the Pod Subnet on an Existing Node](#changing-the-pod-subnet-on-an-existing-node).
> - **The relative path depends on where the overlay lives.** From
>   `/etc/microshift/manifests.d/<name>/` it takes four `../`.
> - **Delete manifests follow the list.** MicroShift looks for delete
>   manifests next to each kustomization path: in
>   `/usr/lib/microshift/manifests.d/delete/*` for the glob, but in
>   `<directory>/delete` for a directory that is listed explicitly.
> - **Multi-node clusters:** keep the drop-in and the overlay identical on all
>   nodes, so that no node applies a different value.

### Changing the Pod Subnet on an Existing Node

kindnetd reads `POD_SUBNET` only when it starts, and it only appends rules to
its `KIND-MASQ-AGENT` chain; it never removes or reorders existing ones. When
the value changes on a node that already ran kindnet, restarting kindnet keeps
the old exemptions and adds the new ones behind the `MASQUERADE` rule, where
they never match. This applies to every change of the value: upgrading from a
package that still shipped kind's `10.244.0.0/16`, switching to an override,
and changing an override later.

> [!IMPORTANT]
> After such a change, either reboot every node, or rebuild the chain in this
> order:
>
> 1. Restart kindnet and wait until every pod runs with the new value:
>
>    ```bash
>    oc rollout restart daemonset/kube-kindnet-ds -n kube-kindnet
>    oc rollout status daemonset/kube-kindnet-ds -n kube-kindnet
>    ```
>
> 2. On each node, flush the chain and delete that node's kindnet pod, so that
>    its replacement rebuilds the chain right away:
>
>    ```bash
>    sudo iptables -t nat -F KIND-MASQ-AGENT
>    oc delete pod -n kube-kindnet -l app=kindnet --field-selector spec.nodeName=<node>
>    ```
>
> Do not flush before every pod runs with the new value: kindnetd re-applies
> its rules every 60 seconds, so a pod that still has the old value can restore
> the old order before it is replaced. Between the flush and the rebuild, new
> connections from pods to the outside are not masqueraded. On a dual-stack
> cluster, flush the IPv6 chain as well: `sudo ip6tables -t nat -F KIND-MASQ-AGENT`.

To check the value kindnet actually uses:

```bash
oc get configmap kindnet-config -n kube-kindnet -o jsonpath='{.data.podSubnet}'
# expects one RETURN rule per pod subnet CIDR, all of them before the MASQUERADE rule
sudo iptables -t nat -S KIND-MASQ-AGENT
sudo ip6tables -t nat -S KIND-MASQ-AGENT   # dual-stack clusters only
```

## Updating Image References

The script automatically fetches the latest images from upstream:
- **Kindnet**: Fetches the latest tag from Docker Hub (`docker.io/kindest/kindnetd`)
- **Kube-proxy**: Fetches the latest stable tag from the official Kubernetes registry (`registry.k8s.io/kube-proxy`), excluding alpha, beta, and rc versions

To update to a new version, simply re-run the generation script.

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
