FROM localhost/microshift-okd-srpm:latest AS srpm

FROM quay.io/centos/centos:stream9

RUN dnf install -y \
        --setopt=install_weak_deps=False \
        rpm-build which git cpio createrepo \
        gcc gettext golang jq make policycoreutils selinux-policy selinux-policy-devel systemd && \
    dnf clean all

COPY --from=srpm /home/microshift/microshift/_output/rpmbuild/SRPMS/ /tmp/

ARG BUILDER_RPM_REPO_PATH=/home/microshift/microshift/_output/rpmbuild/

WORKDIR /tmp

# hadolint ignore=DL4006
RUN \
    echo "# Extract the MicroShift source code into /home/microshift/microshift - bootc builder is reusing file" && \
    rpm2cpio ./microshift-*.src.rpm | cpio -idmv && \
    mkdir -p /home/microshift/microshift && \
    tar xf ./microshift-*.tar.gz -C /home/microshift/microshift --strip-components=1 && \
    \
    echo "# Build the RPMs from the SRPM" && \
    rpmbuild --quiet --define 'microshift_variant community' --rebuild ./microshift-*.src.rpm && \
    \
    echo "# Finally, move the RPMs" && \
    mkdir -p ${BUILDER_RPM_REPO_PATH} && \
    mv /root/rpmbuild/RPMS ${BUILDER_RPM_REPO_PATH}/ && \
    createrepo -v ${BUILDER_RPM_REPO_PATH}/RPMS && \
    rm -rf /root/rpmbuild /tmp/*
