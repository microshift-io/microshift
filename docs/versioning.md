# Versioning Scheme

Upstream packages are based on MicroShift code and OKD images.
To allow for easy identification and tracking of what is included in the package,
following versioning scheme is used: `MICROSHIFT-VERSION`_g`MICROSHIFT-GIT-COMMIT`_`OKD-VERSION`:

- `MICROSHIFT-VERSION` can have two forms:
  - `X.Y.Z-YYYYMMDDHHMM.pN` or `X.Y.Z-{e,r}c.M-YYYYMMDDHHMM.pN` if it is based on [openshift/microshift tags](https://github.com/openshift/microshift/tags).
  - `X.Y.Z` if it was build against a branch (e.g. `main` or `release-X.Y`), value of `X.Y.Z` is  based on version stored in `Makefile.version.*.var` file.
- `MICROSHIFT-GIT-COMMIT` is the [openshift/microshift](https://github.com/openshift/microshift) commit.
- `OKD-VERSION` is a tag of the OKD release image from which the component image references are sourced.

Examples:
- `4.21.0_ga9cd00b34_4.21.0_okd_scos.ec.5`
  - Missing `YYYYMMDDHHMM.pN` means it was built against a branch, not a tag (release)
  - `4.21.0` means that commit [a9cd00b34](https://github.com/openshift/microshift/commit/a9cd00b341191e2091937a1f982168964c105297) was part of 4.21 release (but it could be built from main)
  - Component image references are sourced from [4.21.0-okd-scos.ec.5 release](https://github.com/okd-project/okd/releases/tag/4.21.0-okd-scos.ec.5)
- `4.20.0-202510201126.p0-g1c4675ace_4.20.0-okd-scos.6`
  - `202510201126.p0` is present which means it was built from [MicroShift release tag 4.20.0-202510201126.p0](https://github.com/openshift/microshift/releases/tag/4.20.0-202510201126.p0)
  - MicroShift tag points to [1c4675ace](https://github.com/openshift/microshift/commit/1c4675ace39e1ef9c4919218c15d21e8793f6254) commit.
  - Component image references are sourced from [4.20.0-okd-scos.6 release](https://github.com/okd-project/okd/releases/tag/4.20.0-okd-scos.6)
