# Isolated Network OVN-K Test Validation

**Issue**: [#221](https://github.com/microshift-io/microshift/issues/221)

---

## Problem

The `isolated-network` CI job in `.github/workflows/builders.yaml` defines
three matrix entries:

| Name | ovnk-networking | with-multus |
|------|-----------------|-------------|
| kindnet | 0 | 0 |
| ovnk | 1 | 0 |
| ovnk-multus | 1 | 1 |

When `ovnk-networking: 1`, the image is built with `WITH_KINDNET=0`, which
installs the `microshift-networking` package (OVN-K) instead of
`microshift-kindnet`. However, the test verification step in
`.github/actions/build/action.yaml` only checks:

1. Internet is blocked (ping/curl fail inside the container)
2. `microshift.service` is running (`make run-ready`)
3. `greenboot-healthcheck` has exited (`make run-healthy`)

These checks are identical for all three matrix variants. The OVN-K and
OVN-K+Multus jobs pass as long as MicroShift starts — they do not validate
that OVN-K networking is actually functioning. A broken OVN-K configuration
would go undetected.

### Container name bug

The existing internet isolation check on line 108 of the build action
references a container named `microshift-okd`. The actual container created
by `cluster_manager.sh` is named `microshift-okd-1` (`NODE_BASE_NAME` is
`microshift-okd-` and the first node appends `1`). This check has been
silently passing because `podman exec` against a non-existent container
fails, and the test asserts that the commands fail.

---

## What changed

All changes are in `.github/actions/build/action.yaml`.

### Fix: container name

Changed `microshift-okd` to `microshift-okd-1` in the internet isolation
check so it runs against the actual container.

### Addition: OVN-K validation

When `ovnk-networking == 1`, after `make run-healthy` passes:

1. **Pod check**: Verifies that pods are running in the
   `openshift-ovn-kubernetes` namespace. If no running pods are found, the
   job fails and dumps pod state for debugging.

2. **IP assignment check**: Verifies that every running OVN-K pod has an IP
   address assigned. Pods running without IPs would indicate a broken network
   plane. If any pod lacks an IP, the job fails with the pod names listed.

### Addition: Multus validation

When `with-multus == 1`, after the OVN-K check:

1. **Pod check**: Verifies that pods are running in the `openshift-multus`
   namespace.

2. **CRD check**: Verifies that the `network-attachment-definitions.k8s.cni.cncf.io`
   Custom Resource Definition exists, confirming Multus installed its API
   extension.

---

## Why this approach

**No test pod creation.** In isolated network mode, the container runs with
`--network none` and no internet access. Container images cannot be pulled,
so creating a test pod with an external image is not possible. The embedded
images are MicroShift components, not general-purpose test containers.

Instead, the validation checks the OVN-K pods themselves. After greenboot
passes (which validates core MicroShift workloads), OVN-K pods running with
assigned IPs is strong evidence that the network plane is functional. The
OVN-K pods depend on OpenVSwitch, the OVN databases, and the CNI plugin
chain — if any of those are broken, the pods will not reach Running state
with IPs.

**Inline bash, not a separate script.** The existing test step already
contains inline validation logic (the internet isolation check). Adding the
networking checks in the same style keeps the change minimal and
reviewable. A separate script would require additional plumbing (file copy
into the container or a new Makefile target) for a small amount of logic.

**No retry loops.** The checks run after `make run-healthy`, which polls
greenboot for up to 5 minutes. By that point, all expected workload pods
should be stable. Adding retry logic would mask real failures.

---

## Impact

- **kindnet variant**: Unaffected. The new blocks only execute when
  `ovnk-networking` or `with-multus` inputs are `1`.
- **ovnk variant**: Now validates OVN-K pods are running with IPs.
- **ovnk-multus variant**: Now validates both OVN-K pods and Multus
  deployment.
- **Other jobs**: Unaffected. The `ovnk-networking` and `with-multus` inputs
  default to `0`.

On failure, the job dumps `kubectl get pods -o wide` for the relevant
namespace before exiting, providing immediate diagnostic context in the CI
logs.
