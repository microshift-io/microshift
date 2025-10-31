#!/bin/bash
set -euo pipefail

export LC_ALL=C.UTF-8
export LANG=C.UTF-8

TARGET_REGISTRY=${TARGET_REGISTRY:-ghcr.io/microshift-io/okd}
PULL_SECRET=${PULL_SECRET:-~/.pull-secret.json}

WORKDIR=$(mktemp -d /tmp/okd-build-images-XXXXXX)
trap 'cd ; rm -rf "${WORKDIR}"' EXIT

usage() {
  echo "Usage: $(basename "$0") <okd-version> <ocp-branch> <target-arch>"
  echo "  okd-version: The version of OKD to build (see https://amd64.origin.releases.ci.openshift.org/)"
  echo "  ocp-branch:  The branch of OCP to build (e.g. release-4.19)"
  echo "  target-arch: The architecture of the target images (amd64 or arm64)"
  exit 1
}

check_prereqs() {
  for tool in git oc skopeo podman ; do
    if ! which "${tool}" >/dev/null ; then
      echo "ERROR: Cannot find '${tool}' in the PATH"
      exit 1
    fi
  done
}

check_podman_login() {
  if ! podman login --get-login "${TARGET_REGISTRY}" &>/dev/null ; then
    echo "ERROR: Login to the registry using 'podman login ${TARGET_REGISTRY}' and try again"
    exit 1
  fi
}

check_release_image_exists() {
  if skopeo inspect --format "Digest: {{.Digest}}" "docker://${OKD_RELEASE_IMAGE}" &>/dev/null ; then
    echo "The '${OKD_RELEASE_IMAGE}:${OKD_VERSION}-${TARGET_ARCH}' release image already exists. Exiting..."
    exit 0
  fi
}

git_clone_repo() {
  local -r repo_url="$1"
  local    branch="$2"
  local -r repo_dir="$3"

  if [ "${branch}" == "main" ] || [ "${branch}" == "master" ] ; then
    branch="$(git ls-remote --symref "${repo_url}" HEAD 2>/dev/null \
      | grep 'ref: refs/heads/' \
      | awk '{print $2}' \
      | sed 's#refs/heads/##')"
  fi

  git clone --branch "${branch}" --single-branch "${repo_url}" "${repo_dir}"
  cd "${repo_dir}" || { echo "Failed to access repository directory"; return 1; }
}

# Function to handle base-image repository
base_image() {
  local -r repo_url="https://github.com/openshift/images"
  local -r dockerfile_path="base/Dockerfile.rhel9"
  local -r repo="${WORKDIR}/$(basename "${repo_url}")"

  git_clone_repo "${repo_url}" "${OCP_BRANCH}" "${repo}"
  sed -i 's|^FROM registry.ci.openshift.org/ocp/.*|FROM quay.io/centos/centos:stream9|' "${dockerfile_path}"

  podman build --platform "linux/${TARGET_ARCH}" -t "${images[base]}" -f "${dockerfile_path}" .
}

# Function to handle router-image repository
router_image() {
  local -r repo_url="https://github.com/openshift/router"
  local -r dockerfile_base_path="images/router/base/Dockerfile.ocp"
  local -r dockerfile_haproxy_path="images/router/haproxy/Dockerfile.ocp"
  local -r repo="${WORKDIR}/$(basename "${repo_url}")"

  git_clone_repo "${repo_url}" "${OCP_BRANCH}" "${repo}"
  sed -i 's|FROM registry.ci.openshift.org/ocp/builder:rhel-9-golang|FROM registry.ci.openshift.org/openshift/release:rhel-9-release-golang|' "$dockerfile_base_path"
  sed -i "s|^FROM registry.ci.openshift.org/ocp/.*:base-rhel9|FROM ${images[base]}|" "${dockerfile_base_path}"

  podman build --platform "linux/${TARGET_ARCH}" -t "${images[haproxy-router-base]}" -f "${dockerfile_base_path}" .

  # TODO: Implement a proper way to handle the haproxy28 package for the amd64 architecture
  if [ "${TARGET_ARCH}" != "arm64" ] ; then
    return
  fi

  sed -i "s|^FROM registry.ci.openshift.org/ocp/.*|FROM ${images[haproxy-router-base]}|" "${dockerfile_haproxy_path}"
  sed -i "s|haproxy28|https://github.com/praveenkumar/minp/releases/download/v0.0.1/haproxy28-2.8.10-1.rhaos4.17.el9.aarch64.rpm|" "${dockerfile_haproxy_path}"
  # shellcheck disable=SC2016
  sed -i 's|yum install -y $INSTALL_PKGS|yum --disablerepo=rt install -y $INSTALL_PKGS|' "${dockerfile_haproxy_path}"

  podman build --platform "linux/${TARGET_ARCH}" -t "${images[haproxy-router]}" -f "${dockerfile_haproxy_path}" .
}

# Function to handle kube-proxy repository
kube_proxy_image() {
  local -r repo_url="https://github.com/openshift/sdn"
  local -r dockerfile_path="images/kube-proxy/Dockerfile.rhel"
  local -r repo="${WORKDIR}/$(basename "${repo_url}")"

  git_clone_repo "${repo_url}" "${OCP_BRANCH}" "${repo}"
  # This is a special case because the 4.17 image is not available in the registry
  # for the ARM64 platform, so we use the 4.19 image instead.
  sed -i 's|^FROM registry.ci.openshift.org/ocp/builder.*|FROM registry.ci.openshift.org/openshift/release:rhel-9-release-golang-1.22-openshift-4.19 AS builder|' "${dockerfile_path}"
  sed -i "s|^FROM registry.ci.openshift.org/ocp/.*:base-rhel9|FROM ${images[base]}|" "${dockerfile_path}"
  # shellcheck disable=SC2016
  sed -i 's|yum install -y --setopt=tsflags=nodocs $INSTALL_PKGS|yum --disablerepo=rt install -y --setopt=tsflags=nodocs $INSTALL_PKGS|' "${dockerfile_path}"

  podman build --platform "linux/${TARGET_ARCH}" -t "${images[kube-proxy]}" -f "${dockerfile_path}" .
}

# Function to handle coredns-image repository
coredns_image() {
  local -r repo_url="https://github.com/openshift/coredns"
  local -r dockerfile_path="Dockerfile.ocp"
  local -r repo="${WORKDIR}/$(basename "${repo_url}")"

  git_clone_repo "${repo_url}" "${OCP_BRANCH}" "${repo}"
  sed -i 's|FROM registry.ci.openshift.org/ocp/builder:rhel-9-golang|FROM registry.ci.openshift.org/openshift/release:rhel-9-release-golang|' "${dockerfile_path}"
  sed -i "s|^FROM registry.ci.openshift.org/ocp/.*:base-rhel9|FROM ${images[base]}|" "${dockerfile_path}"

  podman build --platform "linux/${TARGET_ARCH}" -t "${images[coredns]}" -f "${dockerfile_path}" .
}

# Function to handle csi-external-snapshotter-image repository
csi_external_snapshotter_image() {
  local -r repo_url="https://github.com/openshift/csi-external-snapshotter"
  local -r dockerfile_snapshot_controller_path="Dockerfile.snapshot-controller.openshift.rhel7"
  local -r repo="${WORKDIR}/$(basename "${repo_url}")"

  git_clone_repo "${repo_url}" "${OCP_BRANCH}" "${repo}"
  sed -i 's|FROM registry.ci.openshift.org/ocp/builder:rhel-9-golang|FROM registry.ci.openshift.org/openshift/release:rhel-9-release-golang|' "${dockerfile_snapshot_controller_path}"
  sed -i "s|^FROM registry.ci.openshift.org/ocp/.*:base-rhel9|FROM ${images[base]}|" "${dockerfile_snapshot_controller_path}"

  podman build --platform "linux/${TARGET_ARCH}" -t "${images[csi-snapshot-controller]}" -f "${dockerfile_snapshot_controller_path}" .
}

# Function to handle kube-rbac-proxy-image repository
kube_rbac_proxy_image() {
  local -r repo_url="https://github.com/openshift/kube-rbac-proxy"
  local -r dockerfile_path="Dockerfile.ocp"
  local -r repo="${WORKDIR}/$(basename "${repo_url}")"

  git_clone_repo "${repo_url}" "${OCP_BRANCH}" "${repo}"
  sed -i 's|FROM registry.ci.openshift.org/ocp/builder:rhel-9-golang|FROM registry.ci.openshift.org/openshift/release:rhel-9-release-golang|' "${dockerfile_path}"
  sed -i "s|^FROM registry.ci.openshift.org/ocp/.*:base-rhel9|FROM ${images[base]}|" "${dockerfile_path}"

  podman build --platform "linux/${TARGET_ARCH}" -t "${images[kube-rbac-proxy]}" -f "${dockerfile_path}" .
}

# Function to handle pod-image repository
pod_image() {
  local -r repo_url="https://github.com/openshift/kubernetes"
  local -r dockerfile_path="build/pause/Dockerfile.Rhel"
  local -r repo="${WORKDIR}/$(basename "${repo_url}")"

  git_clone_repo "${repo_url}" "${OCP_BRANCH}" "${repo}"
  sed -i 's|FROM registry.ci.openshift.org/ocp/builder:rhel-9-golang|FROM registry.ci.openshift.org/openshift/release:rhel-9-release-golang|' "${dockerfile_path}"
  sed -i "s|^FROM registry.ci.openshift.org/ocp/.*:base-rhel9|FROM ${images[base]}|" "${dockerfile_path}"

  pushd build/pause &>/dev/null
  podman build --platform "linux/${TARGET_ARCH}" -t "${images[pod]}" -f "$(basename "${dockerfile_path}")" .
  popd &>/dev/null
}

# Function to handle cli-image repository
cli_image() {
  local -r repo_url="https://github.com/openshift/oc"
  local -r dockerfile_path="images/cli/Dockerfile.rhel"
  local -r repo="${WORKDIR}/$(basename "${repo_url}")"

  git_clone_repo "${repo_url}" "${OCP_BRANCH}" "${repo}"
  sed -i 's|FROM registry.ci.openshift.org/ocp/builder:rhel-9-golang|FROM registry.ci.openshift.org/openshift/release:rhel-9-release-golang|' "${dockerfile_path}"
  sed -i "s|^FROM registry.ci.openshift.org/ocp/.*:base-rhel9|FROM ${images[base]}|" "${dockerfile_path}"

  podman build --platform "linux/${TARGET_ARCH}" -t "${images[cli]}" -f "${dockerfile_path}" .
}

# Function to handle service-ca-operator-image repository
service_ca_operator_image() {
  local -r repo_url="https://github.com/openshift/service-ca-operator"
  local -r dockerfile_path="Dockerfile.rhel7"
  local -r repo="${WORKDIR}/$(basename "${repo_url}")"

  git_clone_repo "${repo_url}" "${OCP_BRANCH}" "${repo}"
  sed -i 's|FROM registry.ci.openshift.org/ocp/builder:rhel-9-golang|FROM registry.ci.openshift.org/openshift/release:rhel-9-release-golang|' "${dockerfile_path}"
  sed -i "s|^FROM registry.ci.openshift.org/ocp/.*:base-rhel9|FROM ${images[base]}|" "${dockerfile_path}"

  podman build --platform "linux/${TARGET_ARCH}" -t "${images[service-ca-operator]}" -f "${dockerfile_path}" .
}

# Function to handle operator-lifecycle-manager-image repository
operator_lifecycle_manager_image() {
  local -r repo_url="https://github.com/openshift/operator-framework-olm"
  local -r dockerfile_base_path="operator-lifecycle-manager.Dockerfile"
  local -r dockerfile_reg_path="operator-registry.Dockerfile"
  local -r repo="${WORKDIR}/$(basename "${repo_url}")"

  git_clone_repo "${repo_url}" "${OCP_BRANCH}" "${repo}"
  sed -i 's|FROM registry.ci.openshift.org/ocp/builder:rhel-9-golang|FROM registry.ci.openshift.org/openshift/release:rhel-9-release-golang|' "${dockerfile_base_path}"
  sed -i "s|^FROM registry.ci.openshift.org/ocp/.*:base-rhel9|FROM ${images[base]}|" "${dockerfile_base_path}"

  podman build --platform "linux/${TARGET_ARCH}" -t "${images[operator-lifecycle-manager]}" -f "${dockerfile_base_path}" .

  sed -i 's|FROM registry.ci.openshift.org/ocp/builder:rhel-9-golang|FROM registry.ci.openshift.org/openshift/release:rhel-9-release-golang|' "${dockerfile_reg_path}"
  sed -i "s|^FROM registry.ci.openshift.org/ocp/.*:base-rhel9|FROM ${images[base]}|" "${dockerfile_reg_path}"

  podman build --platform "linux/${TARGET_ARCH}" -t "${images[operator-registry]}" -f "${dockerfile_reg_path}" .
}

# Function to handle ovn-kubernetes-image repository
ovn_kubernetes_microshift_image() {
  local -r repo_url="https://github.com/openshift/ovn-kubernetes"
  local -r dockerfile_base_path="Dockerfile.base"
  local -r dockerfile_microshift_path="Dockerfile.microshift"
  local -r repo="${WORKDIR}/$(basename "${repo_url}")"

  git_clone_repo "${repo_url}" "${OCP_BRANCH}" "${repo}"
  sed -i 's|FROM registry.ci.openshift.org/ocp/builder:rhel-9-golang|FROM registry.ci.openshift.org/openshift/release:rhel-9-release-golang|' "${dockerfile_base_path}"
  sed -i "s|^FROM registry.ci.openshift.org/ocp/.*:base-rhel9|FROM ${images[base]}|" "${dockerfile_base_path}"

  podman build --platform "linux/${TARGET_ARCH}" -t "${images[ovn-kubernetes-base]}" -f "${dockerfile_base_path}" .

  sed -i 's|FROM registry.ci.openshift.org/ocp/builder:rhel-9-golang|FROM registry.ci.openshift.org/openshift/release:rhel-9-release-golang|' "${dockerfile_microshift_path}"
  sed -i "s|^FROM registry.ci.openshift.org/ocp/.*:ovn-kubernetes-base|FROM ${images[ovn-kubernetes-base]}|" "${dockerfile_microshift_path}"

  podman build --platform "linux/${TARGET_ARCH}" -t "${images[ovn-kubernetes-microshift]}" -f "${dockerfile_microshift_path}" .
}

# Run all the image creation procedures
create_images() {
  base_image
  router_image
  kube_proxy_image
  coredns_image
  csi_external_snapshotter_image
  kube_rbac_proxy_image
  pod_image
  cli_image
  service_ca_operator_image
  operator_lifecycle_manager_image
  # ovn_kubernetes_microshift_image
}

# Push the images and manifests to the registry
push_image_manifests() {
  local digest
  local manifest_name
  local alt_image

  for key in "${!images[@]}" ; do
    # TODO: Implement a proper way to handle the haproxy-router for the amd64 architecture
    if [ "${TARGET_ARCH}" != "arm64" ] && [ "${key}" = "haproxy-router" ] ; then
      echo "Skipping haproxy-router for ${TARGET_ARCH}"
      continue
    fi

    # Push the image to the registry and get its digest
    podman push "${images[$key]}"
    digest="$(skopeo inspect --format "{{.Name}}@{{.Digest}}" docker://"${images["${key}"]}")"
    images_sha["${key}"]="${digest}"

    # Create a manifest for the image without the architecture suffix
    manifest_name="${images[$key]//-${TARGET_ARCH}/}"
    alt_image="${images[$key]//-${TARGET_ARCH}/-${ALT_ARCH}}"

    # Create a manifest and add the target architecture image
    podman manifest create --amend "${manifest_name}"
    podman manifest add  "${manifest_name}" "${images_sha[$key]}"

    # Add the alternate architecture image to the manifest if it exists
    if skopeo inspect --raw docker://"${alt_image}" &>/dev/null ; then
      digest="$(skopeo inspect --format "{{.Name}}@{{.Digest}}" docker://"${alt_image}")"
      podman manifest add "${manifest_name}" "${digest}"
    fi
    podman manifest push "${manifest_name}"
  done
}

# Create a new release of OKD using oc
create_new_okd_release() {
  # TODO: Implement a proper way to handle the haproxy-router for the amd64 architecture
  local haproxy_router_image
  if [ "${TARGET_ARCH}" != "arm64" ] ; then
    haproxy_router_image=""
  else
    haproxy_router_image="haproxy-router=${images_sha[haproxy-router]}"
  fi

  # shellcheck disable=SC2086
  oc adm release new --from-release "quay.io/okd/scos-release:${OKD_VERSION}" \
      --keep-manifest-list \
      "cli=${images_sha[cli]}" \
      ${haproxy_router_image} \
      "kube-proxy=${images_sha[kube-proxy]}" \
      "coredns=${images_sha[coredns]}" \
      "csi-snapshot-controller=${images_sha[csi-snapshot-controller]}" \
      "kube-rbac-proxy=${images_sha[kube-rbac-proxy]}" \
      "pod=${images_sha[pod]}" \
      "service-ca-operator=${images_sha[service-ca-operator]}" \
      "operator-lifecycle-manager=${images_sha[operator-lifecycle-manager]}" \
      "operator-registry=${images_sha[operator-registry]}" \
      --to-image "${OKD_RELEASE_IMAGE}"

      # "ovn-kubernetes-base=${images_sha[ovn-kubernetes-base]}" \
      # "ovn-kubernetes-microshift=${images_sha[ovn-kubernetes-microshift]}" \
}

#
# Main
#
if [[ $# -ne 3 ]]; then
  usage
fi

OKD_VERSION="$1"
OCP_BRANCH="$2"
TARGET_ARCH="$3"
OKD_RELEASE_IMAGE="${TARGET_REGISTRY}/okd-release-${TARGET_ARCH}:${OKD_VERSION}"

# Determine the alternate architecture
case "${TARGET_ARCH}" in
  "amd64")
    ALT_ARCH="arm64"
    ;;
  "arm64")
    ALT_ARCH="amd64"
    ;;
  *)
    echo "ERROR: Invalid target architecture: ${TARGET_ARCH}"
    exit 1
    ;;
esac

# Populate associative arrays with image names and tags
declare -A images
declare -A images_sha
images=(
    [base]="${TARGET_REGISTRY}/scos-${OKD_VERSION}:base-stream9-${TARGET_ARCH}"
    [cli]="${TARGET_REGISTRY}/cli:${OKD_VERSION}-${TARGET_ARCH}"
    [haproxy-router-base]="${TARGET_REGISTRY}/haproxy-router-base:${OKD_VERSION}-${TARGET_ARCH}"
    [haproxy-router]="${TARGET_REGISTRY}/haproxy-router:${OKD_VERSION}-${TARGET_ARCH}"
    [kube-proxy]="${TARGET_REGISTRY}/kube-proxy:${OKD_VERSION}-${TARGET_ARCH}"
    [coredns]="${TARGET_REGISTRY}/coredns:${OKD_VERSION}-${TARGET_ARCH}"
    [csi-snapshot-controller]="${TARGET_REGISTRY}/csi-snapshot-controller:${OKD_VERSION}-${TARGET_ARCH}"
    [kube-rbac-proxy]="${TARGET_REGISTRY}/kube-rbac-proxy:${OKD_VERSION}-${TARGET_ARCH}"
    [pod]="${TARGET_REGISTRY}/pod:${OKD_VERSION}-${TARGET_ARCH}"
    [service-ca-operator]="${TARGET_REGISTRY}/service-ca-operator:${OKD_VERSION}-${TARGET_ARCH}"
    [operator-lifecycle-manager]="${TARGET_REGISTRY}/operator-lifecycle-manager:${OKD_VERSION}-${TARGET_ARCH}"
    [operator-registry]="${TARGET_REGISTRY}/operator-registry:${OKD_VERSION}-${TARGET_ARCH}"
    # [ovn-kubernetes-base]="${TARGET_REGISTRY}/ovn-kubernetes-base:${OKD_VERSION}-${TARGET_ARCH}"
    # [ovn-kubernetes-microshift]="${TARGET_REGISTRY}/ovn-kubernetes-microshift:${OKD_VERSION}-${TARGET_ARCH}"
)

# Check the prerequisites
check_prereqs
check_podman_login
check_release_image_exists
# Create and push images
create_images
push_image_manifests
# Create a new OKD release
create_new_okd_release
