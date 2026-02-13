FROM quay.io/fedora/fedora:latest

RUN dnf install \
        --setopt=install_weak_deps=False \
        -y \
        copr-cli jq rpmbuild \
    && dnf clean all

COPY microshift-io-dependencies.sh /microshift-io-dependencies.sh
COPY cni/build.sh cni/containernetworking-plugins.spec /cni/
