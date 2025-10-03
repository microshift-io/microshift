## GitHub Workflows

The following GitHub workflows are defined at the `.github/workflows` folder:
* `MicroShift RPM and Container Image Builder` in `build-rpms.yaml`

These workflows can be run under the [Actions](https://github.com/microshift-io/microshift/actions)
tab by the repository maintainers. Other contributors can
[create a fork](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/fork-a-repo#forking-a-repository)
from the [MicroShift Upstream](https://github.com/microshift-io/microshift) repository
and run existing or create new workflows in their private repository branches.

The remainder of this document describes the existing workflows and their functionality.

### Release MicroShift RPMs and Container Images

The workflow implements a build process producing MicroShift RPM and Bootc
container image artifacts.

The following parameters determine the MicroShift source code branch and OKD
container dependencies used during the build process.
* MicroShift branch from https://github.com/openshift/microshift/branches
* OKD version tag from https://quay.io/repository/okd/scos-release?tab=tags

The following actions are suppported.
* `build-all`: Builds both MicroShift RPMs and Bootc container images
* `build-rpms`: Builds only the MicroShift RPM packages
* `build-bootc-images`: Builds only the Bootc container images

Note: When the Bootc container images are built, one of the workflow steps tests
the validity of the produced artifacts by attempting to run the container image
and making sure all the MicroShift services are functional.

The build artifacts are available for download under [Releases](https://github.com/microshift-io/microshift/releases)
after the job finishes successfully.

### Presubmit Pull Request Verification

The workflow is run as a prerequisite for merging a pull request into the main
branch.

It implements the following verification procedures:
* Run `shellcheck` on all scripts in the repository
* Run `hadolint` on all container files in the repository
* Run MicroShift bootc image build and test the services are up and running

Note: The bootc image build is performed on the `main` MicroShift branch and the
latest published OKD version tag.

If any of these procedures exit with errors, the pull request cannot be merged
before all the errors are fixed.
