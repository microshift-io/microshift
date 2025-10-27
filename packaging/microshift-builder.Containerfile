FROM quay.io/centos-bootc/centos-bootc:stream9

# Variables controlling the source of MicroShift components to build
ARG USHIFT_BRANCH=main
ARG OKD_VERSION_TAG

# Internal variables
ARG OKD_REPO=quay.io/okd/scos-release
ARG USHIFT_GIT_URL=https://github.com/openshift/microshift.git
ENV USER=microshift
ENV HOME=/home/microshift
ARG BUILDER_RPM_REPO_PATH=${HOME}/microshift/_output/rpmbuild/RPMS
ARG USHIFT_PREBUILD_SCRIPT=/tmp/prebuild.sh
ARG USHIFT_POSTBUILD_SCRIPT=/tmp/postbuild.sh

# Verify mandatory build arguments
RUN if [ -z "${OKD_VERSION_TAG}" ]; then \
        echo "ERROR: OKD_VERSION_TAG is not set"; \
        echo "See quay.io/okd/scos-release for a list of tags"; \
        exit 1; \
    fi

# System setup for the build
RUN useradd -m -s /bin/bash "${USER}" && \
    echo "${USER}  ALL=(ALL)  NOPASSWD: ALL" > "/etc/sudoers.d/${USER}" && \
    chmod 0640 /etc/shadow && \
    dnf install -y git && \
    dnf clean all

# Set the user and work directory
USER ${USER}:${USER}
WORKDIR ${HOME}

# Preparing the OS configuration for the build
RUN git clone --branch "${USHIFT_BRANCH}" --single-branch "${USHIFT_GIT_URL}" "${HOME}/microshift" && \
    echo '{"auths":{"fake":{"auth":"aWQ6cGFzcwo="}}}' > /tmp/.pull-secret && \
    "${HOME}/microshift/scripts/devenv-builder/configure-vm.sh" --no-build --no-set-release-version --skip-dnf-update /tmp/.pull-secret

# Preparing the build scripts
COPY --chmod=755 ./src/image/prebuild.sh ${USHIFT_PREBUILD_SCRIPT}
RUN "${USHIFT_PREBUILD_SCRIPT}" --replace "${OKD_REPO}" "${OKD_VERSION_TAG}"

# Building all MicroShift downstream RPMs and SRPMs
RUN cd "${HOME}/microshift" && \
    MICROSHIFT_VERSION="${USHIFT_BRANCH}-${OKD_VERSION_TAG}" \
    RPM_RELEASE="1" \
    SOURCE_GIT_TAG="$(git describe --long --tags --abbrev=7 --match 'v[0-9]*' || echo 'v0.0.0-unknown-$(SOURCE_GIT_COMMIT)')" \
    SOURCE_GIT_COMMIT="$(git rev-parse --short 'HEAD^{commit}')" \
    SOURCE_GIT_TREE_STATE=clean \
    MICROSHIFT_VARIANT=community \
    ./packaging/rpm/make-rpm.sh rpm local \
    && \
    MICROSHIFT_VERSION="${USHIFT_BRANCH}-${OKD_VERSION_TAG}" \
    RPM_RELEASE="1" \
    SOURCE_GIT_TAG="$(git describe --long --tags --abbrev=7 --match 'v[0-9]*' || echo 'v0.0.0-unknown-$(SOURCE_GIT_COMMIT)')" \
    SOURCE_GIT_COMMIT="$(git rev-parse --short 'HEAD^{commit}')" \
    SOURCE_GIT_TREE_STATE=clean \
    MICROSHIFT_VARIANT=community \
    ./packaging/rpm/make-rpm.sh srpm local

# Building Kindnet upstream RPM
COPY --chown=${USER}:${USER} ./src/kindnet/kindnet.spec "${HOME}/microshift/packaging/rpm/microshift.spec"
COPY --chown=${USER}:${USER} ./src/kindnet/assets/  "${HOME}/microshift/assets/optional/"
COPY --chown=${USER}:${USER} ./src/kindnet/dropins/ "${HOME}/microshift/packaging/kindnet/"
COPY --chown=${USER}:${USER} ./src/kindnet/crio.conf.d/ "${HOME}/microshift/packaging/crio.conf.d/"
# Prepare and build Kindnet upstream RPM
RUN "${USHIFT_PREBUILD_SCRIPT}" --replace-kindnet "${OKD_REPO}" "${OKD_VERSION_TAG}"
RUN cd "${HOME}/microshift" && \
    MICROSHIFT_VERSION="${USHIFT_BRANCH}-${OKD_VERSION_TAG}" \
    RPM_RELEASE="1" \
    SOURCE_GIT_TAG="$(git describe --long --tags --abbrev=7 --match 'v[0-9]*' || echo 'v0.0.0-unknown-$(SOURCE_GIT_COMMIT)')" \
    SOURCE_GIT_COMMIT="$(git rev-parse --short 'HEAD^{commit}')" \
    SOURCE_GIT_TREE_STATE=clean \
    MICROSHIFT_VARIANT=community \
    ./packaging/rpm/make-rpm.sh rpm local \
    && \
    MICROSHIFT_VERSION="${USHIFT_BRANCH}-${OKD_VERSION_TAG}" \
    RPM_RELEASE="1" \
    SOURCE_GIT_TAG="$(git describe --long --tags --abbrev=7 --match 'v[0-9]*' || echo 'v0.0.0-unknown-$(SOURCE_GIT_COMMIT)')" \
    SOURCE_GIT_COMMIT="$(git rev-parse --short 'HEAD^{commit}')" \
    SOURCE_GIT_TREE_STATE=clean \
    MICROSHIFT_VARIANT=community \
    ./packaging/rpm/make-rpm.sh srpm local

# Building TopoLVM upstream RPM
COPY --chown=${USER}:${USER} ./src/topolvm/topolvm.spec "${HOME}/microshift/packaging/rpm/microshift.spec"
COPY --chown=${USER}:${USER} ./src/topolvm/assets/  "${HOME}/microshift/assets/optional/topolvm/"
COPY --chown=${USER}:${USER} ./src/topolvm/dropins/ "${HOME}/microshift/packaging/microshift/dropins/"
COPY --chown=${USER}:${USER} ./src/topolvm/greenboot/ "${HOME}/microshift/packaging/greenboot/"
COPY --chown=${USER}:${USER} ./src/topolvm/release/ "${HOME}/microshift/assets/optional/topolvm/"
RUN cd "${HOME}/microshift" && \
    MICROSHIFT_VERSION="${USHIFT_BRANCH}-${OKD_VERSION_TAG}" \
    RPM_RELEASE="1" \
    SOURCE_GIT_TAG="$(git describe --long --tags --abbrev=7 --match 'v[0-9]*' || echo 'v0.0.0-unknown-$(SOURCE_GIT_COMMIT)')" \
    SOURCE_GIT_COMMIT="$(git rev-parse --short 'HEAD^{commit}')" \
    SOURCE_GIT_TREE_STATE=clean \
    MICROSHIFT_VARIANT=community \
    ./packaging/rpm/make-rpm.sh rpm local \
    && \
    MICROSHIFT_VERSION="${USHIFT_BRANCH}-${OKD_VERSION_TAG}" \
    RPM_RELEASE="1" \
    SOURCE_GIT_TAG="$(git describe --long --tags --abbrev=7 --match 'v[0-9]*' || echo 'v0.0.0-unknown-$(SOURCE_GIT_COMMIT)')" \
    SOURCE_GIT_COMMIT="$(git rev-parse --short 'HEAD^{commit}')" \
    SOURCE_GIT_TREE_STATE=clean \
    MICROSHIFT_VARIANT=community \
    ./packaging/rpm/make-rpm.sh srpm local

# Post-build MicroShift configuration
COPY --chmod=755 ./src/image/postbuild.sh ${USHIFT_POSTBUILD_SCRIPT}
RUN "${USHIFT_POSTBUILD_SCRIPT}" "${BUILDER_RPM_REPO_PATH}"
