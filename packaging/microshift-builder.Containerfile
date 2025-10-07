FROM quay.io/centos-bootc/centos-bootc:stream9

ARG OKD_REPO=quay.io/okd/scos-release
ARG USHIFT_GIT_URL=https://github.com/openshift/microshift.git
ENV USER=microshift
ENV HOME=/home/microshift
ARG BUILDER_RPM_REPO_PATH=${HOME}/microshift/_output/rpmbuild/RPMS
ARG USHIFT_PREBUILD_SCRIPT=/tmp/prebuild.sh

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
COPY --chmod=755 ./src/image/prebuild.sh ${USHIFT_PREBUILD_SCRIPT}

# Set the user and work directory
USER ${USER}:${USER}
WORKDIR ${HOME}

# Preparing for the build
RUN git clone --branch "${USHIFT_BRANCH}" --single-branch "${USHIFT_GIT_URL}" "${HOME}/microshift" && \
    echo '{"auths":{"fake":{"auth":"aWQ6cGFzcwo="}}}' > /tmp/.pull-secret && \
    "${HOME}/microshift/scripts/devenv-builder/configure-vm.sh" --no-build --no-set-release-version --skip-dnf-update /tmp/.pull-secret && \
    "${USHIFT_PREBUILD_SCRIPT}" --replace "${OKD_REPO}" "${OKD_VERSION_TAG}"

# Building Microshift RPMs and SRPMs
RUN WITH_KINDNET="${WITH_KINDNET}" WITH_TOPOLVM="${WITH_TOPOLVM}" WITH_OLM="${WITH_OLM}" \
        MICROSHIFT_VARIANT="community" \
        make -C "${HOME}/microshift" rpm srpm

# Delete unsupported RPMs, create a local RPM repository and add SRPMs on top of it
# hadolint ignore=DL3059
RUN /bin/bash -c <<'EOF'
    set -euo pipefail
    set -x

    # These RPMs are built unconditionally.
    # To add support for an RPM, undo the file removal and add a presubmit test for it.
    rm -f "${BUILDER_RPM_REPO_PATH}"/*/microshift-ai-model-serving*.rpm
    rm -f "${BUILDER_RPM_REPO_PATH}"/*/microshift-cert-manager*.rpm
    rm -f "${BUILDER_RPM_REPO_PATH}"/*/microshift-gateway-api*.rpm
    rm -f "${BUILDER_RPM_REPO_PATH}"/*/microshift-low-latency*.rpm
    rm -f "${BUILDER_RPM_REPO_PATH}"/*/microshift-multus*.rpm
    rm -f "${BUILDER_RPM_REPO_PATH}"/*/microshift-observability*.rpm

    mkdir -p "${BUILDER_RPM_REPO_PATH}/srpms"
    createrepo -v "${BUILDER_RPM_REPO_PATH}"
    cp -r "${BUILDER_RPM_REPO_PATH}/../SRPMS/." "${BUILDER_RPM_REPO_PATH}/srpms/"
EOF
