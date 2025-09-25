FROM quay.io/centos-bootc/centos-bootc:stream9 as builder

ARG OKD_REPO=quay.io/okd/scos-release
ARG USHIFT_GIT_URL=https://github.com/openshift/microshift.git
ENV USER=microshift
ENV HOME=/microshift
ARG REPO_DIR=/microshift/_output/rpmbuild/RPMS/
ENV GOPATH=/microshift
ENV GOMODCACHE=/microshift/.cache

# Variables controlling the list of MicroShift components to build
ARG OKD_VERSION_TAG
ARG USHIFT_BRANCH=main
ENV WITH_KINDNET=${WITH_KINDNET:-1}
ENV WITH_TOPOLVM=${WITH_TOPOLVM:-1}
ENV WITH_OLM=${WITH_OLM:-0}

# Verify mandatory build arguments
RUN if [ -z "${OKD_VERSION_TAG}" ]; then \
        echo "Error: OKD_VERSION_TAG is not set"; \
        echo "See quay.io/okd/scos-release for a list of tags"; \
        exit 1; \
    fi

# Install git and clone the MicroShift repository
RUN dnf install -y git && git clone --branch "${USHIFT_BRANCH}" --single-branch "${USHIFT_GIT_URL}" /microshift

# Adding non-root user for building microshift
RUN useradd -m -s /bin/bash microshift -d /microshift && \
    echo 'microshift  ALL=(ALL)  NOPASSWD: ALL' >/etc/sudoers.d/microshift && \
    chmod 0640 /etc/shadow
COPY ./src /src

# Set the user and group for the microshift user
RUN chown -R microshift:microshift /microshift /src
USER microshift:microshift
WORKDIR /microshift

# Preparing for the build
RUN echo '{"auths":{"fake":{"auth":"aWQ6cGFzcwo="}}}' > /tmp/.pull-secret && \
   /microshift/scripts/devenv-builder/configure-vm.sh --no-build --no-set-release-version --skip-dnf-update /tmp/.pull-secret && \
   /src/use_okd_assets.sh --replace "${OKD_REPO}" "${OKD_VERSION_TAG}"

# Building Microshift RPMs and local repo
RUN WITH_KINDNET="${WITH_KINDNET}" WITH_TOPOLVM="${WITH_TOPOLVM}" WITH_OLM="${WITH_OLM}" \
        make rpm && \
    createrepo -v "${REPO_DIR}"

# Building microshift container from local RPMs
FROM quay.io/centos-bootc/centos-bootc:stream9

ARG REPO_CONFIG_SCRIPT=/tmp/create_repos.sh
ARG OKD_CONFIG_SCRIPT=/tmp/configure.sh
ARG USHIFT_RPM_REPO_NAME=microshift-local
ARG USHIFT_RPM_REPO_PATH=/tmp/rpm-repo

# Environment variables controlling the list of MicroShift components to install
ENV WITH_KINDNET=${WITH_KINDNET:-1}
ENV WITH_TOPOLVM=${WITH_TOPOLVM:-1}
ENV WITH_OLM=${WITH_OLM:-0}
ENV EMBED_CONTAINER_IMAGES=${EMBED_CONTAINER_IMAGES:-0}

ENV KUBECONFIG=/var/lib/microshift/resources/kubeadmin/kubeconfig
COPY --chmod=755 ./src/create_repos.sh ${REPO_CONFIG_SCRIPT}
COPY --chmod=755 ./src/configure.sh ${OKD_CONFIG_SCRIPT}
COPY --from=builder /microshift/_output/rpmbuild/RPMS ${USHIFT_RPM_REPO_PATH}

# Install nfv-openvswitch repo which provides openvswitch extra policy package
RUN dnf install -y centos-release-nfv-openvswitch && \
    dnf clean all

# Installing MicroShift and cleanup
# With kindnet enabled, we do not need openvswitch service which is enabled by default
# once MicroShift is installed. Disable the service to avoid the need to configure it.
RUN ${REPO_CONFIG_SCRIPT} ${USHIFT_RPM_REPO_PATH} && \
    dnf install -y microshift microshift-release-info && \
    if [ -n "${WITH_KINDNET}" ] ; then \
        dnf install -y microshift-kindnet microshift-kindnet-release-info; \
        systemctl disable openvswitch ; \
    fi && \
    if [ -n "${WITH_TOPOLVM}" ] ; then \
        dnf install -y microshift-topolvm ; \
    fi && \
    if [ -n "${WITH_OLM}" ] ; then \
        dnf install -y microshift-olm microshift-olm-release-info ; \
    fi && \
    ${REPO_CONFIG_SCRIPT} -delete && \
    rm -f ${REPO_CONFIG_SCRIPT} && \
    rm -rf $USHIFT_RPM_REPO_PATH && \
    dnf clean all

RUN ${OKD_CONFIG_SCRIPT} && rm -vf ${OKD_CONFIG_SCRIPT}

# If the EMBED_CONTAINER_IMAGES environment variable is set to 1:
# 1. Temporarily configure user namespace UID and GID mappings by writing to /etc/subuid and  /etc/subgid and clean it later
#    - This allows the skopeo command to operate properly which requires user namespace support.
#    - Without it following error occur during image build
#       - FATA[0129] copying system image from manifest list:[...]unpacking failed (error: exit status 1; output: potentially insufficient UIDs or GIDs available[...]
# 2. Extract the list of image URLs from a JSON file (`release-$(uname -m).json`) while excluding the "lvms_operator" image.
#    - `lvms_operator` image is excluded because it is not available upstream
RUN if [ -n "${EMBED_CONTAINER_IMAGES}" ] ; then \
        echo "root:100000:65536" > /etc/subuid ; \
        echo "root:100000:65536" > /etc/subgid ; \
        for i in $(jq -r '.images | to_entries | map(select(.key != "lvms_operator")) | .[].value' "/usr/share/microshift/release/release-$(uname -m).json") ; do \
            skopeo copy --retry-times 3 --preserve-digests "docker://${i}" "containers-storage:${i}" ; \
        done ; \
        if [ "${WITH_KINDNET}" ]; then \
            kindnetImage=$(jq -r '.images.kindnet' "/usr/share/microshift/release/release-kindnet-$(uname -m).json") ; \
            skopeo copy --retry-times 3 --preserve-digests "docker://${kindnetImage}" "containers-storage:${kindnetImage}" ; \
            kubeproxyImage=$(jq -r '.images["kube-proxy"]' "/usr/share/microshift/release/release-kube-proxy-$(uname -m).json") ; \
            skopeo copy --retry-times 3 --preserve-digests "docker://${kubeproxyImage}" "containers-storage:${kubeproxyImage}" ; \
        fi && \
        rm -f /etc/subuid /etc/subgid ; \
    fi

# Create a systemd unit to recursively make the root filesystem subtree
# shared as required by OVN images
COPY --from=builder /microshift/packaging/imagemode/systemd/microshift-make-rshared.service /usr/lib/systemd/system/microshift-make-rshared.service
RUN systemctl enable microshift-make-rshared.service
