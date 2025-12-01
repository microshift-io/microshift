FROM quay.io/fedora/fedora:42

RUN dnf install -y \
        --setopt=install_weak_deps=False \
        copr-cli createrepo rpm2cpio cpio && \
    dnf clean all

ARG COPR_BUILD_ID=
ARG BUILDER_RPM_REPO_PATH=/home/microshift/microshift/_output/rpmbuild/RPMS

RUN \
    copr download-build --rpms --chroot "epel-9-$(uname -m)" --dest /tmp/rpms ${COPR_BUILD_ID} && \
    mkdir -p /home/microshift/microshift && \
    cd /tmp/rpms/"epel-9-$(uname -m)"/ && \
    rpm2cpio microshift-*.src.rpm | cpio -idmv && \
    tar xf microshift-*.tar.gz -C /home/microshift/microshift --strip-components=1 && \
    mkdir -p ${BUILDER_RPM_REPO_PATH} && \
    mv /tmp/rpms/"epel-9-$(uname -m)"/*.rpm ${BUILDER_RPM_REPO_PATH}/ && \
    createrepo -v ${BUILDER_RPM_REPO_PATH} && \
    rm -rf /tmp/rpms
