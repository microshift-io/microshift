## GitHub Workflows

The GitHub Workflows are defined at the `.github/workflows` folder, including
pre-submit tests and software release procedures.

* Pre-submit tests are run automatically before a pull request can be merged
* Software release procedures can be run under the [Actions](https://github.com/microshift-io/microshift/actions)
  tab by the repository maintainers, or scheduled for regular automatic execution

> Note: Contributors can create a fork from the [MicroShift Upstream](https://github.com/microshift-io/microshift)
> repository and run software release workflows in their private repository branches.

The remainder of this document describes the existing workflows and their functionality.

### Pre-submit Workflows

The workflows described in this section are run as a prerequisite for merging a
pull request into the main branch. If any of these procedures exit with errors,
the pull request cannot be merged before all the errors are fixed.

#### Builders

Build a MicroShift Bootc image from the `main` MicroShift source branch and the
latest published OKD version tag. Run this image to verify that all the MicroShift
services are functional.

The following operating systems are tested:
* Fedora, CentOS 9 and CentOS 10 for RPM packages and Bootc images
* Ubuntu for DEB packages

The following configurations are tested:
* The `x86_64` and `aarch64` architectures
* Isolated network for OVN-K and Kindnet CNI

#### Installers

Run the [Quick Start](../README.md#quick-start) procedures to verify:
* The latest published RPM packages on the supported operating systems and
  architectures
* The latest published Bootc images on the supported architectures

The [quick clean](./quickclean.sh) script is called in the end to verify the
uninstall procedure.

#### Linters

Run [ShellCheck](https://github.com/koalaman/shellcheck) on all shell scripts and
[hadolint](https://github.com/hadolint/hadolint) on all container files in the repository.

### Software Release Procedures

#### MicroShift

The workflow implements a build process producing MicroShift RPM packages, DEB
packages and Bootc container image artifacts. It is executed manually by the
repository maintainers - no scheduled runs are configured at this time.

The following parameters determine the MicroShift source code branch and the OKD
container image dependencies used during the build process.
* [MicroShift (OpenShift) branch](https://github.com/openshift/microshift/branches)
* [OKD version tag](https://quay.io/repository/okd/scos-release?tab=tags)

The following actions are supported:
* `packages`: Build MicroShift RPM and DEB packages
* `bootc-image`: Build a MicroShift Bootc container image
* `all`: Build all of the above

> Note: After the Bootc container image is built, a workflow step checks it by
> attempting to run the container image and verifying that all the MicroShift
> services are functional.

If the build job finishes successfully, the artifact download and installation
instructions are available at [Releases](https://github.com/microshift-io/microshift/releases).

> Note: The available container images can be listed at [Packages](https://github.com/microshift-io/microshift/packages)
> and pulled from the `ghcr.io/microshift-io` registry.

#### OKD on ARM

The workflow implements a build process producing a subset of OKD container image
artifacts that are required by MicroShift on the `aarch64` architecture. It runs
every day at 03:00 UTC to make sure ARM artifacts are available for the latest
OKD releases.

> Note: OKD `aarch64` builds are performed using MicroShift-specific build procedure
> until [OKD Build of OpenShift on Arm](https://issues.redhat.com/browse/OKD-215)
> is implemented by the OKD team.

The following parameters determine the MicroShift source code branch and the OKD
container image dependencies used during the build process.
* [MicroShift (OpenShift) branch](https://github.com/openshift/microshift/branches)
* [OKD version tag](https://quay.io/repository/okd/scos-release?tab=tags)

The default target registry for publishing OKD container image artifacts is
`ghcr.io/microshift-io/okd`.

> Note: After the OKD container images are built, a workflow step checks them by
> creating a MicroShift Bootc image with the new artifacts, attempting to run it,
> and verifying that all the MicroShift services work.

If the build job finishes successfully, the available container images can be listed
at [Packages](https://github.com/microshift-io/microshift/packages) and pulled from
the `ghcr.io/microshift-io` registry.
