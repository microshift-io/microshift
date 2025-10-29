FROM quay.io/centos/centos:stream9

# Variables controlling the source of MicroShift components to build
ARG USHIFT_BRANCH=main
ARG OKD_VERSION_TAG

# Internal variables
ARG OKD_REPO=quay.io/okd/scos-release
ARG USHIFT_GIT_URL=https://github.com/openshift/microshift.git
ENV HOME=/home/microshift
ARG BUILDER_RPM_REPO_PATH=${HOME}/microshift/_output/rpmbuild/RPMS
ARG USHIFT_PREBUILD_SCRIPT=/tmp/prebuild.sh
ARG USHIFT_POSTBUILD_SCRIPT=/tmp/postbuild.sh
ARG USHIFT_BUILDRPMS_SCRIPT=/tmp/build-rpms.sh
ARG USHIFT_MODIFY_SPEC_SCRIPT=/tmp/modify-spec.py

# Verify mandatory build arguments
RUN if [ -z "${OKD_VERSION_TAG}" ]; then \
        echo "ERROR: OKD_VERSION_TAG is not set"; \
        echo "See quay.io/okd/scos-release for a list of tags"; \
        exit 1; \
    fi

RUN ARCH=amd64 ; if [ "$(uname -m)" = "aarch64" ]; then ARCH=arm64; fi && \
    OKD_CLIENT_URL=https://github.com/okd-project/okd/releases/download/${OKD_VERSION_TAG}/openshift-client-linux-${ARCH}-rhel9-${OKD_VERSION_TAG}.tar.gz && \
    curl -L -o /tmp/okd-client.tar.gz "${OKD_CLIENT_URL}" && \
    tar -xzf /tmp/okd-client.tar.gz -C /tmp && \
    mv /tmp/oc /usr/local/bin/oc && \
    rm -rf /tmp/okd-client.tar.gz

RUN dnf install -y git rpm-build jq python3-pip && dnf clean all

WORKDIR ${HOME}

RUN git clone --branch "${USHIFT_BRANCH}" --single-branch "${USHIFT_GIT_URL}" "${HOME}/microshift"

# Preparing the build scripts
COPY --chmod=755 ./src/image/prebuild.sh ${USHIFT_PREBUILD_SCRIPT}
RUN "${USHIFT_PREBUILD_SCRIPT}" --replace "${OKD_REPO}" "${OKD_VERSION_TAG}"

COPY --chmod=755 ./src/image/build-rpms.sh ${USHIFT_BUILDRPMS_SCRIPT}
COPY --chmod=755 ./src/image/modify-spec.py ${USHIFT_MODIFY_SPEC_SCRIPT}
RUN cd "${HOME}/microshift/" && \
    sed -i -e 's,CHECK_RPMS="y",,g' -e 's,CHECK_SRPMS="y",,g' ./packaging/rpm/make-rpm.sh && \
    python3 -m pip install specfile && \
    python3 ${USHIFT_MODIFY_SPEC_SCRIPT} && \
    "${USHIFT_BUILDRPMS_SCRIPT}" srpm

# Building Kindnet upstream RPM
COPY ./src/kindnet/kindnet.spec "${HOME}/microshift/packaging/rpm/microshift.spec"
COPY ./src/kindnet/assets/  "${HOME}/microshift/assets/optional/"
COPY ./src/kindnet/dropins/ "${HOME}/microshift/packaging/kindnet/"
COPY ./src/kindnet/crio.conf.d/ "${HOME}/microshift/packaging/crio.conf.d/"
# Prepare and build Kindnet upstream RPM
RUN "${USHIFT_PREBUILD_SCRIPT}" --replace-kindnet "${OKD_REPO}" "${OKD_VERSION_TAG}" && \
    "${USHIFT_BUILDRPMS_SCRIPT}" srpm

# Building TopoLVM upstream RPM
COPY ./src/topolvm/topolvm.spec "${HOME}/microshift/packaging/rpm/microshift.spec"
COPY ./src/topolvm/assets/  "${HOME}/microshift/assets/optional/topolvm/"
COPY ./src/topolvm/dropins/ "${HOME}/microshift/packaging/microshift/dropins/"
COPY ./src/topolvm/greenboot/ "${HOME}/microshift/packaging/greenboot/"
COPY ./src/topolvm/release/ "${HOME}/microshift/assets/optional/topolvm/"
RUN "${USHIFT_BUILDRPMS_SCRIPT}" srpm

# Argument to make sure that the last step will always be executed.
# Otherwise, if cache is used, the files won't be copied to the host.
ARG CACHE_BUST
RUN cp -r "${HOME}/microshift/_output/rpmbuild/SRPMS/." /output
