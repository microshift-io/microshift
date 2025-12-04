FROM quay.io/fedora/fedora:42

RUN dnf install -y copr-cli && dnf clean all
