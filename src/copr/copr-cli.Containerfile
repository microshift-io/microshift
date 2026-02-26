FROM quay.io/fedora/fedora:latest

RUN dnf install \
        --setopt=install_weak_deps=False \
        -y \
        copr-cli jq rpmbuild \
    && dnf clean all

COPY create-build.sh microshift-io-dependencies.sh cni/containernetworking-plugins.spec /
COPY cni/build.sh cni/containernetworking-plugins.spec /cni/
