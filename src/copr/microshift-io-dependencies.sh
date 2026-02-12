#!/usr/bin/env bash
set -euo pipefail

_package_name="microshift-io-dependencies"
_minor_version_start=18

if [ $# -ne 2 ]; then
    echo "Usage: $(basename "$0") <okd-version-tag> <copr-repo-name>"
    exit 1
fi

OKD_VERSION_TAG="$1"
COPR_REPO_NAME="$2"

echo "OKD_VERSION_TAG: '${OKD_VERSION_TAG}'"
echo "COPR_REPO_NAME: '${COPR_REPO_NAME}'"

[ -z "${OKD_VERSION_TAG}" ] && echo "ERROR: OKD_VERSION_TAG is not set" && exit 1
[ -z "${COPR_REPO_NAME}" ] && echo "ERROR: COPR_REPO_NAME is not set" && exit 1

major=$(echo "${OKD_VERSION_TAG}" | cut -d. -f1)
minor=$(echo "${OKD_VERSION_TAG}" | cut -d. -f2)
pkg_version="${major}.${minor}"
echo "New package version: '${pkg_version}'"

if $(copr-cli list-packages "${COPR_REPO_NAME}" | jq -r '.[].name' | grep -q "${_package_name}"); then
    existing_package_version=$(copr-cli get-package \
                                --name "${_package_name}" \
                                --with-latest-succeeded-build \
                                "${COPR_REPO_NAME}" \
                                | jq -r '.latest_succeeded_build.source_package.version')

    if [[ "${existing_package_version}" == "${pkg_version}-1" ]]; then
        echo "Package ${_package_name} ${pkg_version} already exists in the COPR repository"
        exit 0
    fi
fi

rhocp_versions=""
for min in $(seq "${_minor_version_start}" "${minor}") ; do
    rhocp_versions+="${major}.${min} "
done

echo "RHOCP versions to create .repo files for: '${rhocp_versions}'"

dest=$(mktemp -d "/tmp/${_package_name}.XXXXXX")
cat > "${dest}/${_package_name}.spec" <<EOF
%global rhocp_versions ${rhocp_versions}
%global version ${pkg_version}

Name:           ${_package_name}
Version:        %{version}
Release:        1%{?dist}
Summary:        RPM repository configurations for MicroShift dependencies

License:        Apache-2.0
URL:            https://github.com/microshift-io/microshift-io
BuildArch:      noarch

%description
This package installs RPM repository configuration files required
for installing MicroShift dependencies from the OpenShift beta mirror repository.

%install
install -d %{buildroot}%{_sysconfdir}/yum.repos.d

for v in %{rhocp_versions}; do
    cat >> %{buildroot}%{_sysconfdir}/yum.repos.d/openshift-mirror-beta.repo <<EOF2
[openshift-mirror-\${v}-beta]
name=OpenShift \${v} Mirror Beta Repository
baseurl=https://mirror.openshift.com/pub/openshift-v4/\\\$basearch/dependencies/rpms/\${v}-el9-beta/
enabled=1
gpgcheck=0
skip_if_unavailable=0

EOF2
done

%files
%config(noreplace) %{_sysconfdir}/yum.repos.d/openshift-mirror-beta.repo

EOF

echo "--------------- SPEC FILE ---------------"
cat "${dest}/${_package_name}.spec"
echo "-----------------------------------------"

if copr-cli build "${COPR_REPO_NAME}" "${dest}/${_package_name}.spec"; then
    copr-cli regenerate-repos "${COPR_REPO_NAME}"
else
    exit 1
fi
