FROM localhost/microshift-okd-builder:latest AS builder
FROM quay.io/centos-bootc/centos-bootc:stream9

ARG REPO_CONFIG_SCRIPT=/tmp/create_repos.sh
ARG USHIFT_CONFIG_SCRIPT=/tmp/configure.sh
ARG USHIFT_RPM_REPO_PATH=/tmp/rpm-repo

# Builder image related variables
ARG BUILDER_RPM_REPO_PATH=/home/microshift/microshift/_output/rpmbuild/RPMS
ARG BUILDER_RSHARED_SERVICE=/home/microshift/microshift/packaging/imagemode/systemd/microshift-make-rshared.service

# Environment variables controlling the list of MicroShift components to install
ENV WITH_KINDNET=${WITH_KINDNET:-1}
ENV WITH_TOPOLVM=${WITH_TOPOLVM:-1}
ENV WITH_OLM=${WITH_OLM:-0}
ENV EMBED_CONTAINER_IMAGES=${EMBED_CONTAINER_IMAGES:-0}

# Copy the scripts and the builder RPM repository
COPY --chmod=755 ./src/create_repos.sh ${REPO_CONFIG_SCRIPT}
COPY --chmod=755 ./src/configure.sh ${USHIFT_CONFIG_SCRIPT}
COPY --from=builder ${BUILDER_RPM_REPO_PATH} ${USHIFT_RPM_REPO_PATH}

# Install nfv-openvswitch repo which provides openvswitch extra policy package
RUN dnf install -y centos-release-nfv-openvswitch && \
    dnf clean all

# Installing MicroShift and cleanup
# With kindnet enabled, we do not need openvswitch service which is enabled by default
# once MicroShift is installed. Disable the service to avoid the need to configure it.
RUN ${REPO_CONFIG_SCRIPT} -create ${USHIFT_RPM_REPO_PATH} && \
    dnf install -y microshift microshift-release-info && \
    if [ "${WITH_KINDNET}" = "1" ] ; then \
        dnf install -y microshift-kindnet microshift-kindnet-release-info; \
        systemctl disable openvswitch ; \
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
RUN ${USHIFT_CONFIG_SCRIPT} && rm -vf ${USHIFT_CONFIG_SCRIPT}

# If the EMBED_CONTAINER_IMAGES environment variable is set to 1:
# 1. Temporarily configure user namespace UID and GID mappings by writing to /etc/subuid and  /etc/subgid and clean it later
#    - This allows the skopeo command to operate properly which requires user namespace support.
#    - Without it following error occur during image build
#       - FATA[0129] copying system image from manifest list:[...]unpacking failed (error: exit status 1; output: potentially insufficient UIDs or GIDs available[...]
# 2. Extract the list of image URLs from a JSON file (`release-$(uname -m).json`) while excluding the "lvms_operator" image.
#    - `lvms_operator` image is excluded because it is not available upstream
RUN if [ "${EMBED_CONTAINER_IMAGES}" = "1" ] ; then \
        echo "root:100000:65536" > /etc/subuid ; \
        echo "root:100000:65536" > /etc/subgid ; \
        for i in $(jq -r '.images | to_entries | map(select(.key != "lvms_operator")) | .[].value' "/usr/share/microshift/release/release-$(uname -m).json") ; do \
            skopeo copy --retry-times 3 --preserve-digests "docker://${i}" "containers-storage:${i}" ; \
        done ; \
        if [ "${WITH_KINDNET}" = "1" ] ; then \
            kindnetImage=$(jq -r '.images.kindnet' "/usr/share/microshift/release/release-kindnet-$(uname -m).json") ; \
            skopeo copy --retry-times 3 --preserve-digests "docker://${kindnetImage}" "containers-storage:${kindnetImage}" ; \
            kubeproxyImage=$(jq -r '.images["kube-proxy"]' "/usr/share/microshift/release/release-kube-proxy-$(uname -m).json") ; \
            skopeo copy --retry-times 3 --preserve-digests "docker://${kubeproxyImage}" "containers-storage:${kubeproxyImage}" ; \
        fi && \
        rm -vf /etc/subuid /etc/subgid ; \
    fi

# Create a systemd unit to recursively make the root filesystem subtree
# shared as required by OVN images
COPY --from=builder ${BUILDER_RSHARED_SERVICE} /usr/lib/systemd/system/microshift-make-rshared.service
RUN systemctl enable microshift-make-rshared.service
