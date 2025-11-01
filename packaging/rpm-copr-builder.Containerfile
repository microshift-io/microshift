FROM quay.io/fedora/fedora:42

RUN dnf install -y \
        --setopt=install_weak_deps=False \
        git rpm-build jq python3-pip copr-cli python3-specfile createrepo && \
    dnf clean all

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

ENV COPR_REPO_NAME=pmtk0/test123

# Verify mandatory build arguments
RUN if [ -z "${OKD_VERSION_TAG}" ]; then \
        echo "ERROR: OKD_VERSION_TAG is not set"; \
        echo "See quay.io/okd/scos-release for a list of tags"; \
        exit 1; \
    fi

RUN ARCH="" ; if [ "$(uname -m)" = "aarch64" ]; then ARCH="-arm64"; fi && \
    OKD_CLIENT_URL=https://github.com/okd-project/okd/releases/download/${OKD_VERSION_TAG}/openshift-client-linux${ARCH}-${OKD_VERSION_TAG}.tar.gz && \
    echo "OKD_CLIENT_URL: ${OKD_CLIENT_URL}" && \
    curl -L -o /tmp/okd-client.tar.gz "${OKD_CLIENT_URL}" && \
    tar -xzf /tmp/okd-client.tar.gz -C /tmp && \
    mv /tmp/oc /usr/local/bin/oc && \
    rm -rf /tmp/okd-client.tar.gz ;

WORKDIR ${HOME}

RUN git clone --branch "${USHIFT_BRANCH}" --single-branch "${USHIFT_GIT_URL}" "${HOME}/microshift"

# Preparing the build scripts
COPY --chmod=755 ./src/image/prebuild.sh ${USHIFT_PREBUILD_SCRIPT}
RUN "${USHIFT_PREBUILD_SCRIPT}" --replace "${OKD_REPO}" "${OKD_VERSION_TAG}"

COPY --chmod=755 ./src/image/build-rpms.sh ${USHIFT_BUILDRPMS_SCRIPT}
COPY --chmod=755 ./src/image/modify-spec.py ${USHIFT_MODIFY_SPEC_SCRIPT}
RUN cd "${HOME}/microshift/" && \
    sed -i -e 's,CHECK_RPMS="y",,g' -e 's,CHECK_SRPMS="y",,g' ./packaging/rpm/make-rpm.sh && \
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

COPY ./src/copr/create-builds-and-wait.sh /tmp/create-builds-and-wait.sh
RUN --mount=type=secret,id=copr-cfg bash /tmp/create-builds-and-wait.sh
