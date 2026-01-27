FROM quay.io/fedora/fedora:latest

RUN dnf install -y copr-cli && dnf clean all
