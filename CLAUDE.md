# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MicroShift Upstream builds MicroShift (optimized OpenShift for edge computing) using OKD components instead of Red Hat payloads. This enables upstream development and testing without subscriptions.

## Build System Architecture

The build process is containerized and consists of three sequential stages:

1. **SRPM Build** (`make srpm`): Creates source RPM in `microshift-okd-srpm` container image
   - Clones MicroShift from upstream repository at specified `USHIFT_GITREF` (default: main)
   - Replaces component images with OKD references via `src/image/prebuild.sh`
   - Outputs to `SRPM_WORKDIR` (temp dir if not specified)

2. **RPM Build** (`make rpm`): Builds binary RPMs from SRPM in `microshift-okd-rpm` container image
   - Requires SRPM image from previous step
   - Outputs to `RPM_OUTDIR` (temp dir if not specified)
   - Can be converted to DEB packages using `make rpm-to-deb RPM_OUTDIR=/path/to/rpms`

3. **Bootc Image** (`make image`): Creates bootable container image `microshift-okd`
   - Requires RPM image from previous step
   - Configurable via `WITH_KINDNET`, `WITH_TOPOLVM`, `WITH_OLM`, `EMBED_CONTAINER_IMAGES`
   - Based on `BOOTC_IMAGE_URL:BOOTC_IMAGE_TAG` (default: quay.io/centos-bootc/centos-bootc:stream9)

### Key Build Variables

- `USHIFT_GITREF`: MicroShift branch/tag (default: main)
- `OKD_VERSION_TAG`: OKD release version (auto-detects latest if unset)
- `ARCH`: Automatically detected (x86_64 or aarch64)
- OKD release images differ by arch:
  - x86_64: `quay.io/okd/scos-release`
  - aarch64: `ghcr.io/microshift-io/okd/okd-release-arm64`

## Common Commands

### Building

```bash
# Complete build sequence
make srpm              # Build SRPM first
make rpm               # Build RPMs (requires SRPM)
make image             # Build bootc image (requires RPM)

# Build with custom versions
make srpm USHIFT_GITREF=release-4.20 OKD_VERSION_TAG=4.20.0-okd-scos.6

# Build DEB packages
RPM_OUTDIR=/tmp/my-rpms make rpm
make rpm-to-deb RPM_OUTDIR=/tmp/my-rpms
```

### Running (Bootc Container)

```bash
# Start single-node cluster
make run                          # Default config
make run LVM_VOLSIZE=5G          # With larger TopoLVM backend
make run ISOLATED_NETWORK=1      # Without internet (requires EMBED_CONTAINER_IMAGES=1)

# Multi-node cluster
make run                          # Create first node
make add-node                     # Add additional nodes

# Cluster management
make start                        # Start stopped cluster
make stop                         # Stop cluster
make run-status                   # Show cluster status
make run-ready                    # Wait for service ready (5min timeout)
make run-healthy                  # Wait for service healthy (15min timeout)

# Access cluster
make env                          # Shell with KUBECONFIG
make env CMD="kubectl get nodes"  # Run single command

# Container access
sudo podman exec -it microshift-okd-1 /bin/bash -l
```

### Running (Host Installation)

```bash
# RPM installation
sudo ./src/rpm/create_repos.sh -create /path/to/rpms
sudo dnf install -y microshift microshift-kindnet
sudo ./src/rpm/create_repos.sh -delete
sudo ./src/rpm/postinstall.sh
sudo systemctl start microshift.service

# DEB installation
sudo ./src/deb/install.sh /path/to/rpms/deb
sudo systemctl start microshift.service
```

### Cleanup

```bash
make clean              # Stop cluster and remove LVM backend
make clean-all          # Also remove container images

# Host cleanup
echo y | sudo microshift-cleanup-data --all
sudo dnf remove -y 'microshift*'    # or sudo apt purge -y 'microshift*'
```

### Testing

```bash
make check              # Run linters (hadolint + shellcheck)
```

## Directory Structure

- `packaging/`: Containerfiles for SRPM, RPM, and bootc builds
- `src/`: Build scripts and component customizations
  - `src/image/`: Image build scripts (prebuild.sh replaces OKD images)
  - `src/okd/`: OKD version detection and ARM builds
  - `src/kindnet/`: Kindnet CNI assets and spec
  - `src/topolvm/`: TopoLVM CSI assets and spec
  - `src/etcd/`: etcd backend configuration (postgres/sqlite)
  - `src/deb/`: DEB package conversion
  - `src/rpm/`: RPM repository and installation
  - `src/cluster_manager.sh`: Multi-node cluster orchestration
- `ansible/`: Ansible roles for automated builds/deployments
- `.github/workflows/`: CI/CD workflows
  - `builders.yaml`: Pre-submit tests for builds
  - `installers.yaml`: Tests quickstart scripts
  - `release.yaml`: Manual release workflow
  - `release-okd.yaml`: Daily OKD ARM builds

## Multi-Architecture Support

- x86_64 and aarch64 supported
- ARM builds use custom OKD images at `ghcr.io/microshift-io/okd/okd-release-arm64`
- Architecture detected automatically via `uname -m`
- OKD ARM builds run daily at 03:00 UTC via GitHub Actions

## Versioning Scheme

Format: `MICROSHIFT-VERSION_gMICROSHIFT-GIT-COMMIT_OKD-VERSION`

Examples:
- `4.21.0_ga9cd00b34_4.21.0_okd_scos.ec.5`: Built from branch (no timestamp)
- `4.20.0-202510201126.p0-g1c4675ace_4.20.0-okd-scos.6`: Built from tag (has timestamp)

## Networking Options

Two CNI options available (mutually exclusive):
- **Kindnet** (default): Set `WITH_KINDNET=1` during image build, install `microshift-kindnet` package
- **OVN-K**: Set `WITH_KINDNET=0` during image build, install `microshift-networking` package, requires `openvswitch` kernel module

## Storage

TopoLVM CSI provides persistent storage:
- Enabled by default (`WITH_TOPOLVM=1`)
- Requires LVM backend (cluster_manager.sh creates automatically)
- Configure size via `LVM_VOLSIZE` (default: 1G)
- Install `microshift-topolvm` package for host deployments

### TopoLVM Configuration

The following environment variables can be used to customize TopoLVM:

- `VG_NAME`: LVM volume group name (default: `myvg1`)
- `SPARE_GB`: Spare GB to reserve in the volume group (default: `10`)

Example usage:
```bash
# Use custom volume group name and smaller spare for testing
make run VG_NAME=testvg SPARE_GB=2 LVM_VOLSIZE=5G

# Using quickstart scripts
VG_NAME=customvg SPARE_GB=5 sudo -E ./src/quickstart.sh
```

## Cluster Manager

`src/cluster_manager.sh` manages multi-node bootc clusters:
- Creates podman network for node communication
- Manages TopoLVM LVM backend
- Supports operations: create, add-node, start, stop, delete, ready, healthy, status, env
- Node naming: `microshift-okd-1`, `microshift-okd-2`, etc.
- Environment variables: `USHIFT_IMAGE`, `LVM_DISK`, `VG_NAME`, `SPARE_GB`, `ISOLATED_NETWORK`, `EXPOSE_KUBEAPI_PORT`

## Important Notes

- Always build SRPM before RPM, and RPM before bootc image
- Isolated network requires `EMBED_CONTAINER_IMAGES=1` during image build
- Multi-node clusters require `ISOLATED_NETWORK=0`
- OKD version auto-detection queries latest-amd64 or latest-arm64 tags
- Build artifacts are temporary by default; specify output dirs to preserve
