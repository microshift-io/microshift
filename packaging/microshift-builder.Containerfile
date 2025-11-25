FROM quay.io/centos-bootc/centos-bootc:stream9

# Variables controlling the source of MicroShift components to build
ARG USHIFT_REF=main
ARG OKD_RELEASE_IMAGE=quay.io/okd/scos-release
ARG OKD_VERSION_TAG

# Internal variables
ARG USHIFT_GIT_URL=https://github.com/openshift/microshift.git
ENV USER=microshift
ENV HOME=/home/microshift
ARG BUILDER_RPM_REPO_PATH=${HOME}/microshift/_output/rpmbuild/RPMS
ARG USHIFT_PREBUILD_SCRIPT=/tmp/prebuild.sh
ARG USHIFT_POSTBUILD_SCRIPT=/tmp/postbuild.sh
ARG USHIFT_MODIFY_SPEC_SCRIPT=/tmp/modify-spec.py

# Verify mandatory build arguments
RUN if [ -z "${OKD_VERSION_TAG}" ] ; then \
        echo "ERROR: OKD_VERSION_TAG is not set" ; \
        echo "See ${OKD_RELEASE_IMAGE} for a list of tags" ; \
        exit 1; \
    fi

# System setup for the build
RUN useradd -m -s /bin/bash "${USER}" && \
    echo "${USER}  ALL=(ALL)  NOPASSWD: ALL" > "/etc/sudoers.d/${USER}" && \
    chmod 0640 /etc/shadow && \
    dnf install -y \
        --setopt=install_weak_deps=False \
        git rpm-build jq python3-pip createrepo && \
    dnf clean all && \
    pip install specfile

# Set the user and work directory
USER ${USER}:${USER}
WORKDIR ${HOME}

# Preparing the OS configuration for the build
RUN git clone --branch "${USHIFT_REF}" --single-branch "${USHIFT_GIT_URL}" "${HOME}/microshift" && \
    echo '{"auths":{"fake":{"auth":"aWQ6cGFzcwo="}}}' > /tmp/.pull-secret && \
    "${HOME}/microshift/scripts/devenv-builder/configure-vm.sh" --no-build --no-set-release-version --skip-dnf-update /tmp/.pull-secret

WORKDIR ${HOME}/microshift/

# Preparing the build scripts
COPY --chmod=755 ./src/image/prebuild.sh ${USHIFT_PREBUILD_SCRIPT}
RUN "${USHIFT_PREBUILD_SCRIPT}" --replace "${OKD_RELEASE_IMAGE}" "${OKD_VERSION_TAG}"

# Modify the microshift.spec to remove packages not yet supported by the upstream.
COPY --chmod=755 ./src/image/modify-spec.py ${USHIFT_MODIFY_SPEC_SCRIPT}
# Disable the RPM and SRPM checks in the make-rpm.sh script.
RUN sed -i -e 's,CHECK_RPMS="y",,g' -e 's,CHECK_SRPMS="y",,g' ./packaging/rpm/make-rpm.sh && \
    ${USHIFT_MODIFY_SPEC_SCRIPT}

# Building all MicroShift downstream RPMs and SRPMs
# hadolint ignore=DL3059
RUN MICROSHIFT_VARIANT="community" make -C "${HOME}/microshift" rpm srpm

# Building Kindnet upstream RPM
COPY --chown=${USER}:${USER} ./src/kindnet/kindnet.spec "${HOME}/microshift/packaging/rpm/microshift.spec"
COPY --chown=${USER}:${USER} ./src/kindnet/assets/  "${HOME}/microshift/assets/optional/"
COPY --chown=${USER}:${USER} ./src/kindnet/dropins/ "${HOME}/microshift/packaging/kindnet/"
COPY --chown=${USER}:${USER} ./src/kindnet/crio.conf.d/ "${HOME}/microshift/packaging/crio.conf.d/"
# Prepare and build Kindnet upstream RPM
RUN "${USHIFT_PREBUILD_SCRIPT}" --replace-kindnet "${OKD_RELEASE_IMAGE}" "${OKD_VERSION_TAG}" && \
    MICROSHIFT_VARIANT="community" make -C "${HOME}/microshift" rpm

# Building TopoLVM upstream RPM
COPY --chown=${USER}:${USER} ./src/topolvm/topolvm.spec "${HOME}/microshift/packaging/rpm/microshift.spec"
COPY --chown=${USER}:${USER} ./src/topolvm/assets/  "${HOME}/microshift/assets/optional/topolvm/"
COPY --chown=${USER}:${USER} ./src/topolvm/dropins/ "${HOME}/microshift/packaging/microshift/dropins/"
COPY --chown=${USER}:${USER} ./src/topolvm/greenboot/ "${HOME}/microshift/packaging/greenboot/"
COPY --chown=${USER}:${USER} ./src/topolvm/release/ "${HOME}/microshift/assets/optional/topolvm/"
RUN MICROSHIFT_VARIANT="community" make -C "${HOME}/microshift" rpm

# Post-build MicroShift configuration
COPY --chmod=755 ./src/image/postbuild.sh ${USHIFT_POSTBUILD_SCRIPT}
RUN "${USHIFT_POSTBUILD_SCRIPT}" "${BUILDER_RPM_REPO_PATH}"
