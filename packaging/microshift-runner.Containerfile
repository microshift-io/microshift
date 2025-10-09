# Optionally allow for the base image override
ARG BOOTC_IMAGE_URL=quay.io/centos-bootc/centos-bootc
ARG BOOTC_IMAGE_TAG=stream9

FROM localhost/microshift-okd-builder:latest AS builder
FROM ${BOOTC_IMAGE_URL}:${BOOTC_IMAGE_TAG}

ARG REPO_CONFIG_SCRIPT=/tmp/create_repos.sh
ARG USHIFT_POSTINSTALL_SCRIPT=/tmp/postinstall.sh
ARG USHIFT_EMBED_IMAGES_SCRIPT=/tmp/embed_images.sh
ARG USHIFT_RPM_REPO_PATH=/tmp/rpm-repo

# Builder image related variables
ARG BUILDER_RPM_REPO_PATH=/home/microshift/microshift/_output/rpmbuild/RPMS
ARG BUILDER_RSHARED_SERVICE=/home/microshift/microshift/packaging/imagemode/systemd/microshift-make-rshared.service

# Environment variables controlling the list of MicroShift components to install
ENV WITH_KINDNET=${WITH_KINDNET:-1}
ENV WITH_TOPOLVM=${WITH_TOPOLVM:-1}
ENV WITH_OLM=${WITH_OLM:-0}
ENV EMBED_CONTAINER_IMAGES=${EMBED_CONTAINER_IMAGES:-0}

# Run repository configuration script, install MicroShift and cleanup
COPY --chmod=755 ./src/create_repos.sh ${REPO_CONFIG_SCRIPT}
COPY --from=builder ${BUILDER_RPM_REPO_PATH} ${USHIFT_RPM_REPO_PATH}
RUN ${REPO_CONFIG_SCRIPT} -create ${USHIFT_RPM_REPO_PATH} && \
    dnf install -y microshift microshift-release-info && \
    if [ "${WITH_KINDNET}" = "1" ] ; then \
        dnf install -y microshift-kindnet microshift-kindnet-release-info; \
    fi && \
    if [ "${WITH_TOPOLVM}" = "1" ] ; then \
        dnf install -y microshift-topolvm ; \
    fi && \
    if [ "${WITH_OLM}" = "1" ] ; then \
        dnf install -y microshift-olm microshift-olm-release-info ; \
    fi && \
    ${REPO_CONFIG_SCRIPT} -delete && \
    rm -vf  ${REPO_CONFIG_SCRIPT} && \
    rm -rvf ${USHIFT_RPM_REPO_PATH} && \
    dnf clean all

# Post-install MicroShift configuration
COPY --chmod=755 ./src/image/postinstall.sh ${USHIFT_POSTINSTALL_SCRIPT}
RUN ${USHIFT_POSTINSTALL_SCRIPT} && rm -vf "${USHIFT_POSTINSTALL_SCRIPT}"

# If the EMBED_CONTAINER_IMAGES environment variable is set to 1, temporarily
# configure user namespace UID and GID mappings. This allows the skopeo command
# to operate without errors when copying the container images.
COPY --chmod=755 ./src/image/embed_images.sh ${USHIFT_EMBED_IMAGES_SCRIPT}
RUN if [ "${EMBED_CONTAINER_IMAGES}" = "1" ] ; then \
        echo "root:100000:65536" > /etc/subuid && \
        echo "root:100000:65536" > /etc/subgid && \
        ${USHIFT_EMBED_IMAGES_SCRIPT} && rm -vf "${USHIFT_EMBED_IMAGES_SCRIPT}" && \
        rm -vf /etc/subuid /etc/subgid ; \
    fi

# Create a systemd unit to recursively make the root filesystem subtree
# shared as required by OVN images
COPY --from=builder ${BUILDER_RSHARED_SERVICE} /usr/lib/systemd/system/microshift-make-rshared.service
RUN systemctl enable microshift-make-rshared.service
