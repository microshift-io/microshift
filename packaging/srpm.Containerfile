# Using Fedora for easy access to the dependencies (no need to install EPEL or use pip)
FROM quay.io/fedora/fedora:42

RUN dnf install -y \
        --setopt=install_weak_deps=False \
        git rpm-build jq python3-pip python3-specfile && \
    dnf clean all

# Variables controlling the source of MicroShift components to build
ARG USHIFT_GITREF=main
ARG OKD_VERSION_TAG

# Internal variables
ARG OKD_RELEASE_IMAGE_X86_64=quay.io/okd/scos-release
ARG OKD_RELEASE_IMAGE_AARCH64=ghcr.io/microshift-io/okd/okd-release-arm64
ARG USHIFT_GIT_URL=https://github.com/openshift/microshift.git
ENV HOME=/home/microshift
ARG USHIFT_PREBUILD_SCRIPT=/tmp/prebuild.sh
ARG USHIFT_BUILDRPMS_SCRIPT=/tmp/build-rpms.sh
ARG USHIFT_MODIFY_SPEC_SCRIPT=/tmp/modify-spec.py
ARG SPEC_KINDNET=/tmp/kindnet.spec
ARG SPEC_TOPOLVM=/tmp/topolvm.spec

# Verify mandatory build arguments
RUN if [ -z "${OKD_VERSION_TAG}" ]; then \
        echo "ERROR: OKD_VERSION_TAG is not set"; \
        echo "See quay.io/okd/scos-release for a list of tags"; \
        exit 1; \
    fi

RUN [ "$(uname -m)" = "aarch64" ] && ARCH="-arm64" || ARCH="" ; \
    OKD_CLIENT_URL="https://github.com/okd-project/okd/releases/download/${OKD_VERSION_TAG}/openshift-client-linux${ARCH}-${OKD_VERSION_TAG}.tar.gz" && \
    echo "OKD_CLIENT_URL: ${OKD_CLIENT_URL}" && \
    curl -L --retry 5 -o /tmp/okd-client.tar.gz "${OKD_CLIENT_URL}" && \
    tar -xzf /tmp/okd-client.tar.gz -C /usr/local/bin/ && \
    rm -rf /tmp/okd-client.tar.gz

WORKDIR ${HOME}

RUN git clone --branch "${USHIFT_GITREF}" --single-branch "${USHIFT_GIT_URL}" "${HOME}/microshift"

# Replace component images with OKD image references
COPY --chmod=755 ./src/image/prebuild.sh ${USHIFT_PREBUILD_SCRIPT}
RUN ARCH="x86_64" "${USHIFT_PREBUILD_SCRIPT}" --replace "${OKD_RELEASE_IMAGE_X86_64}" "${OKD_VERSION_TAG}" && \
    ARCH="aarch64" "${USHIFT_PREBUILD_SCRIPT}" --replace "${OKD_RELEASE_IMAGE_AARCH64}" "${OKD_VERSION_TAG}"

WORKDIR ${HOME}/microshift/

COPY ./src/kindnet/kindnet.spec "${SPEC_KINDNET}"
COPY ./src/kindnet/assets/  ./assets/optional/
COPY ./src/kindnet/dropins/ ./packaging/kindnet/
COPY ./src/kindnet/crio.conf.d/ ./packaging/crio.conf.d/

COPY ./src/topolvm/topolvm.spec "${SPEC_TOPOLVM}"
COPY ./src/topolvm/assets/  ./assets/optional/topolvm/
COPY ./src/topolvm/dropins/ ./packaging/microshift/dropins/
COPY ./src/topolvm/greenboot/ ./packaging/greenboot/
COPY ./src/topolvm/release/ ./assets/optional/topolvm/

RUN ARCH="x86_64" "${USHIFT_PREBUILD_SCRIPT}" --replace-kindnet "${OKD_RELEASE_IMAGE_X86_64}" "${OKD_VERSION_TAG}" && \
    ARCH="aarch64" "${USHIFT_PREBUILD_SCRIPT}" --replace-kindnet "${OKD_RELEASE_IMAGE_AARCH64}" "${OKD_VERSION_TAG}"

COPY --chmod=755 ./src/image/modify-spec.py ${USHIFT_MODIFY_SPEC_SCRIPT}
# Disable the RPM and SRPM checks in the make-rpm.sh script
# and modify the microshift.spec to remove packages not yet supported by the upstream
RUN sed -i -e 's,CHECK_RPMS="y",,g' -e 's,CHECK_SRPMS="y",,g' ./packaging/rpm/make-rpm.sh && \
    "${USHIFT_MODIFY_SPEC_SCRIPT}" ./packaging/rpm/microshift.spec "${SPEC_KINDNET}" "${SPEC_TOPOLVM}"

COPY --chmod=755 ./src/image/build-rpms.sh ${USHIFT_BUILDRPMS_SCRIPT}
RUN "${USHIFT_BUILDRPMS_SCRIPT}" srpm
