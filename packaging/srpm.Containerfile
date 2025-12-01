# Using Fedora for easy dnf install
FROM quay.io/fedora/fedora:42

RUN dnf install -y \
        --setopt=install_weak_deps=False \
        git rpm-build jq python3-pip python3-specfile && \
    dnf clean all

# Variables controlling the source of MicroShift components to build
ARG USHIFT_GITREF=main
ARG OKD_VERSION_TAG

ENV OKD_VERSION_TAG=${OKD_VERSION_TAG}
ENV USHIFT_GITREF=${USHIFT_GITREF}

# Internal variables
ARG OKD_REPO=quay.io/okd/scos-release
ARG USHIFT_GIT_URL=https://github.com/openshift/microshift.git
ENV HOME=/home/microshift
ARG BUILDER_RPM_REPO_PATH=${HOME}/microshift/_output/rpmbuild/RPMS
ARG USHIFT_PREBUILD_SCRIPT=/tmp/prebuild.sh
ARG USHIFT_POSTBUILD_SCRIPT=/tmp/postbuild.sh
ARG USHIFT_BUILDRPMS_SCRIPT=/tmp/build-rpms.sh
ARG USHIFT_MODIFY_SPEC_SCRIPT=/tmp/modify-spec.py
ARG USHIFT_BUILDRPMS_SCRIPT=/tmp/build-rpms.sh

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

RUN git clone --branch "${USHIFT_GITREF}" --single-branch "${USHIFT_GIT_URL}" "${HOME}/microshift"

# Replace component images with OKD image references
COPY --chmod=755 ./src/image/prebuild.sh ${USHIFT_PREBUILD_SCRIPT}
RUN "${USHIFT_PREBUILD_SCRIPT}" --replace "${OKD_REPO}" "${OKD_VERSION_TAG}"

WORKDIR ${HOME}/microshift/


COPY ./src/kindnet/kindnet.spec /tmp/kindnet.spec
COPY ./src/kindnet/assets/  ./assets/optional/
COPY ./src/kindnet/dropins/ ./packaging/kindnet/
COPY ./src/kindnet/crio.conf.d/ ./packaging/crio.conf.d/

COPY ./src/topolvm/topolvm.spec /tmp/topolvm.spec
COPY ./src/topolvm/assets/  ./assets/optional/topolvm/
COPY ./src/topolvm/dropins/ ./packaging/microshift/dropins/
COPY ./src/topolvm/greenboot/ ./packaging/greenboot/
COPY ./src/topolvm/release/ ./assets/optional/topolvm/

RUN "${USHIFT_PREBUILD_SCRIPT}" --replace-kindnet "${OKD_REPO}" "${OKD_VERSION_TAG}"

COPY --chmod=755 ./src/image/modify-spec.py ${USHIFT_MODIFY_SPEC_SCRIPT}
RUN python3 ${USHIFT_MODIFY_SPEC_SCRIPT} /tmp/kindnet.spec /tmp/topolvm.spec

# Disable the RPM and SRPM checks in the make-rpm.sh script
# and modify the microshift.spec to remove packages not yet supported by the upstream
RUN sed -i -e 's,CHECK_RPMS="y",,g' -e 's,CHECK_SRPMS="y",,g' ./packaging/rpm/make-rpm.sh

COPY --chmod=755 ./src/image/build-rpms.sh ${USHIFT_BUILDRPMS_SCRIPT}
RUN "${USHIFT_BUILDRPMS_SCRIPT}" srpm

RUN cp ./_output/rpmbuild/SRPMS/* /output/
