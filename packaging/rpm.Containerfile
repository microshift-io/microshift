FROM localhost/microshift-okd-srpm:latest AS srpm

FROM quay.io/centos/centos:stream9

RUN dnf install -y \
        --setopt=install_weak_deps=False \
        rpm-build which git cpio createrepo \
        gcc gettext golang jq make policycoreutils selinux-policy selinux-policy-devel systemd && \
    dnf clean all

# Install the latest Go from upstream (EL9's Go is too old)
# hadolint ignore=DL4006
RUN GO_VER=$(curl -sL 'https://go.dev/VERSION?m=text' | head -1 | sed 's/^go//') && \
    GO_ARCH=$([ "$(uname -m)" = "x86_64" ] && echo "amd64" || echo "arm64") && \
    curl --fail --retry 3 --retry-delay 5 -L \
        -o "/tmp/go${GO_VER}.linux-${GO_ARCH}.tar.gz" \
        "https://go.dev/dl/go${GO_VER}.linux-${GO_ARCH}.tar.gz" && \
    rm -rf /usr/local/go && \
    tar -C /usr/local -xzf "/tmp/go${GO_VER}.linux-${GO_ARCH}.tar.gz" && \
    rm -f "/tmp/go${GO_VER}.linux-${GO_ARCH}.tar.gz"

ENV PATH="/usr/local/go/bin:${PATH}"

COPY --from=srpm /home/microshift/microshift/_output/rpmbuild/SRPMS/ /tmp/

ARG BUILDER_RPM_REPO_PATH=/home/microshift/microshift/_output/rpmbuild/

WORKDIR /tmp

# hadolint ignore=DL4006
RUN \
    echo "# Extract the MicroShift source code into /home/microshift/microshift" && \
    echo "# Note: Bootc builder is reusing the source archive" && \
    rpm2cpio ./microshift-*.src.rpm | cpio -idmv && \
    mkdir -p /home/microshift/microshift && \
    tar xf ./microshift-*.tar.gz -C /home/microshift/microshift --strip-components=1 && \
    \
    echo "# Build the RPMs from the SRPM" && \
    rpmbuild --quiet --define 'microshift_variant community' --rebuild ./microshift-*.src.rpm && \
    \
    echo "# Move the RPMs" && \
    mkdir -p ${BUILDER_RPM_REPO_PATH}/ && \
    rm -rf ${BUILDER_RPM_REPO_PATH}/RPMS && \
    mv /root/rpmbuild/RPMS ${BUILDER_RPM_REPO_PATH}/ && \
    mkdir -p ${BUILDER_RPM_REPO_PATH}/RPMS/srpms/ && \
    mv ./microshift-*.src.rpm ${BUILDER_RPM_REPO_PATH}/RPMS/srpms/ && \
    mv ./version.txt ${BUILDER_RPM_REPO_PATH}/RPMS/ && \
    \
    echo "# Create the repository and cleanup" && \
    createrepo -v ${BUILDER_RPM_REPO_PATH}/RPMS && \
    rm -rf /root/rpmbuild /tmp/* /root/.cache/go-build
