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
ARG USHIFT_BUILDRPMS_SCRIPT=/tmp/build-rpms.sh

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

COPY --chmod=755 ./src/image/build-rpms.sh ${USHIFT_BUILDRPMS_SCRIPT}
COPY --chmod=755 ./src/image/modify-spec.py ${USHIFT_MODIFY_SPEC_SCRIPT}

WORKDIR ${HOME}/microshift/
# Building MicroShift downstream RPMs and SRPMs
RUN sed -i -e 's,CHECK_RPMS="y",,g' -e 's,CHECK_SRPMS="y",,g' ./packaging/rpm/make-rpm.sh && \
    python3 ${USHIFT_MODIFY_SPEC_SCRIPT} && \
    "${USHIFT_BUILDRPMS_SCRIPT}"

# Building Kindnet upstream RPM
COPY --chown=${USER}:${USER} ./src/kindnet/kindnet.spec "./packaging/rpm/microshift.spec"
COPY --chown=${USER}:${USER} ./src/kindnet/assets/  "./assets/optional/"
COPY --chown=${USER}:${USER} ./src/kindnet/dropins/ "./packaging/kindnet/"
COPY --chown=${USER}:${USER} ./src/kindnet/crio.conf.d/ "./packaging/crio.conf.d/"
# Prepare and build Kindnet upstream RPM
RUN "${USHIFT_PREBUILD_SCRIPT}" --replace-kindnet "${OKD_REPO}" "${OKD_VERSION_TAG}" && \
    "${USHIFT_BUILDRPMS_SCRIPT}"

# Building TopoLVM upstream RPM
COPY --chown=${USER}:${USER} ./src/topolvm/topolvm.spec "./packaging/rpm/microshift.spec"
COPY --chown=${USER}:${USER} ./src/topolvm/assets/  "./assets/optional/topolvm/"
COPY --chown=${USER}:${USER} ./src/topolvm/dropins/ "./packaging/microshift/dropins/"
COPY --chown=${USER}:${USER} ./src/topolvm/greenboot/ "./packaging/greenboot/"
COPY --chown=${USER}:${USER} ./src/topolvm/release/ "./assets/optional/topolvm/"
RUN "${USHIFT_BUILDRPMS_SCRIPT}"

# Post-build MicroShift configuration
COPY --chmod=755 ./src/image/postbuild.sh ${USHIFT_POSTBUILD_SCRIPT}
RUN "${USHIFT_POSTBUILD_SCRIPT}" "${BUILDER_RPM_REPO_PATH}"
