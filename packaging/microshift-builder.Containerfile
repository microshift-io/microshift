FROM quay.io/centos-bootc/centos-bootc:stream9

ARG OKD_REPO=quay.io/okd/scos-release
ARG USHIFT_GIT_URL=https://github.com/openshift/microshift.git
ENV USER=microshift
ENV HOME=/home/microshift
ARG BUILDER_RPM_REPO_PATH=${HOME}/microshift/_output/rpmbuild/RPMS
ARG USHIFT_PREBUILD_SCRIPT=/tmp/prebuild.sh
ARG USHIFT_POSTBUILD_SCRIPT=/tmp/postbuild.sh

# Variables controlling the list of MicroShift components to build
ARG OKD_VERSION_TAG
ARG USHIFT_BRANCH=main
ENV WITH_KINDNET=${WITH_KINDNET:-1}
ENV WITH_TOPOLVM=${WITH_TOPOLVM:-1}
ENV WITH_OLM=${WITH_OLM:-0}

# Verify mandatory build arguments
RUN if [ -z "${OKD_VERSION_TAG}" ]; then \
        echo "Error: OKD_VERSION_TAG is not set"; \
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

# Building downstream Microshift RPMs and SRPMs
# TODO: Remove WITH_TOPOLVM=0 once TopoLVM is deleted from downstream
# hadolint ignore=DL3059
RUN WITH_KINDNET="${WITH_KINDNET}" WITH_OLM="${WITH_OLM}" WITH_TOPOLVM=0 \
        MICROSHIFT_VARIANT="community" \
        make -C "${HOME}/microshift" rpm srpm

# Building TopoLVM upstream RPM
COPY --chmod=644 ./src/topolvm/topolvm.spec "${HOME}/microshift/packaging/rpm/microshift.spec"
COPY ./src/topolvm/assets/  "${HOME}/microshift/assets/optional/topolvm/"
COPY ./src/topolvm/dropins/ "${HOME}/microshift/packaging/microshift/dropins/"
COPY ./src/topolvm/greenboot/ "${HOME}/microshift/packaging/greenboot/"
COPY ./src/topolvm/release/ "${HOME}/microshift/assets/optional/topolvm/"
RUN MICROSHIFT_VARIANT="community" make -C "${HOME}/microshift" rpm

# Post-build MicroShift configuration
COPY --chmod=755 ./src/image/postbuild.sh ${USHIFT_POSTBUILD_SCRIPT}
RUN "${USHIFT_POSTBUILD_SCRIPT}" "${BUILDER_RPM_REPO_PATH}"
