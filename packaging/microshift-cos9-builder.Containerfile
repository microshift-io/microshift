FROM quay.io/centos-bootc/centos-bootc:stream9

ARG OKD_REPO=quay.io/okd/scos-release
ARG USHIFT_GIT_URL=https://github.com/openshift/microshift.git
ENV USER=microshift
ENV HOME=/microshift
ENV GOPATH=/microshift/_output/go
ENV GOMODCACHE=/microshift/_output/.cache
ARG BUILDER_RPM_REPO_PATH=/microshift/_output/rpmbuild/RPMS

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

# Building Microshift RPMs and SRPMs
RUN WITH_KINDNET="${WITH_KINDNET}" WITH_TOPOLVM="${WITH_TOPOLVM}" WITH_OLM="${WITH_OLM}" \
        make rpm srpm
# Create a local repository for RPMs and add SRPMs on top of it
RUN mkdir -p "${BUILDER_RPM_REPO_PATH}/srpms" && \
    createrepo -v "${BUILDER_RPM_REPO_PATH}" && \
    cp -r "${BUILDER_RPM_REPO_PATH}/../SRPMS/." "${BUILDER_RPM_REPO_PATH}/srpms/"
