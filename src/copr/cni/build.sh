#!/usr/bin/env bash

set -euo pipefail

_package_name="containernetworking-plugins"
_scriptdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -ne 1 ]; then
    echo "Usage: $(basename "$0") <copr-repo-name>"
    exit 1
fi

COPR_REPO_NAME="$1"

[ -z "${COPR_REPO_NAME}" ] && echo "ERROR: COPR_REPO_NAME is not set" && exit 1
echo "COPR_REPO_NAME: '${COPR_REPO_NAME}'"

latest_tag=$(curl -L \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/containernetworking/plugins/releases/latest | jq -r '.tag_name')

echo "### containernetworking/plugins latest tag: '${latest_tag}'"
version="${latest_tag#v}"

echo "### Checking if package ${_package_name} ${version} already exists in the COPR repository"
cni_pkg="$(copr-cli list-packages "${COPR_REPO_NAME}" | jq -r '.[] | select(.name == "'${_package_name}'")')"
if [ -n "${cni_pkg}" ]; then
    existing_package_version=$(copr-cli get-package \
                                --name "${_package_name}" \
                                --with-latest-succeeded-build \
                                "${COPR_REPO_NAME}" \
                                | jq -r '.latest_succeeded_build.source_package.version')

    if [[ "${existing_package_version}" == "1:${version}-1" ]]; then
        echo "### Package ${_package_name} ${version} already exists in the COPR repository"
        exit 0
    fi
fi

temp_dir="$(mktemp -d "/tmp/containernetworking-plugins-${version}.XXXXXX")"
cp "${_scriptdir}/containernetworking-plugins.spec" "${temp_dir}/"

pushd "${temp_dir}" >/dev/null

echo "### Downloading the CNI plugins x86_64 and aarch64 releases for ${version}"
curl -L -o amd64.tgz "https://github.com/containernetworking/plugins/releases/download/v${version}/cni-plugins-linux-amd64-v${version}.tgz"
curl -L -o arm64.tgz "https://github.com/containernetworking/plugins/releases/download/v${version}/cni-plugins-linux-arm64-v${version}.tgz"

mkdir -p containernetworking-plugins-${version}/{x86_64,aarch64}

tar xf amd64.tgz -C containernetworking-plugins-${version}/x86_64
tar xf arm64.tgz -C containernetworking-plugins-${version}/aarch64
cp containernetworking-plugins-${version}/x86_64/LICENSE containernetworking-plugins-${version}/x86_64/README.md containernetworking-plugins-${version}/

tar czf containernetworking-plugins-${version}.tar.gz -C containernetworking-plugins-${version} .

mkdir -p buildroot/{RPMS,SRPMS,SOURCES,SPECS,BUILD}
mv containernetworking-plugins-${version}.tar.gz buildroot/SOURCES/

cat > buildroot/SPECS/containernetworking-plugins.spec <<EOF
%global ver ${version}

EOF
cat containernetworking-plugins.spec >> buildroot/SPECS/containernetworking-plugins.spec

echo "### Building the SRPM"
rpmbuild -bs --define "_topdir ./buildroot" ./buildroot/SPECS/containernetworking-plugins.spec

echo "### Pushing the SRPM to COPR (${COPR_REPO_NAME}) and waiting for the build"
# Just epel-10 chroots because of the obsolesence of the original package in the CentOS Stream 10.
if copr-cli build "${COPR_REPO_NAME}" \
    --chroot epel-10-aarch64 --chroot epel-10-x86_64 \
    "${temp_dir}/buildroot/SRPMS/containernetworking-plugins-${version}-1.src.rpm"; then
    copr-cli regenerate-repos "${COPR_REPO_NAME}"
else
    exit 1
fi

popd >/dev/null
rm -rf "${temp_dir}"
