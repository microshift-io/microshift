FROM quay.io/fedora/fedora:latest

RUN dnf install -y \
        --setopt=install_weak_deps=False \
        copr-cli createrepo rpm2cpio cpio && \
    dnf clean all

ARG COPR_BUILD_ID=
ARG BUILDER_RPM_REPO_PATH=/home/microshift/microshift/_output/rpmbuild/RPMS
ARG COPR_CHROOT="epel-10-$(uname -m)"

# hadolint ignore=DL4006,DL3003
RUN \
    echo "# Download the RPMs from COPR" && \
    copr download-build --rpms --chroot "${COPR_CHROOT}" --dest /tmp/rpms ${COPR_BUILD_ID} && \
    \
    echo "# Extract the MicroShift source code into /home/microshift/microshift" && \
    mkdir -p /home/microshift/microshift && \
    cd /tmp/rpms/"${COPR_CHROOT}"/ && \
    rpm2cpio microshift-*.src.rpm | cpio -idmv && \
    tar xf microshift-*.tar.gz -C /home/microshift/microshift --strip-components=1 && \
    \
    echo "# Move the RPMs" && \
    mkdir -p ${BUILDER_RPM_REPO_PATH} && \
    mv /tmp/rpms/"${COPR_CHROOT}"/*.rpm ${BUILDER_RPM_REPO_PATH}/ && \
    \
    echo "# Create the repository and cleanup" && \
    createrepo -v ${BUILDER_RPM_REPO_PATH} && \
    rm -rf /tmp/rpms
