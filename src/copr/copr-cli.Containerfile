FROM quay.io/fedora/fedora:latest

RUN dnf install \
        --setopt=install_weak_deps=False \
        -y \
        copr-cli jq \
    && dnf clean all

COPY microshift-io-dependencies.sh /microshift-io-dependencies.sh
