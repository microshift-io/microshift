#!/usr/bin/env bash
set -euo pipefail

_package_name="microshift-io-dependencies"

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

declare -A LAST_MINOR_FOR_MAJOR=([4]=22)

get_prev_version() {
    local major=$1
    local minor=$2
    if (( minor > 0 )); then
        prev_major="${major}"
        prev_minor=$(( minor - 1 ))
    else
        prev_major=$(( major - 1 ))
        prev_minor="${LAST_MINOR_FOR_MAJOR[${prev_major}]:-}"
    fi
}

if copr-cli list-packages "${COPR_REPO_NAME}" | jq -r '.[].name' | grep -q "${_package_name}"; then
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

# Include 3 repos (X.Y, X.Y-1, and X.Y-2) just in case there's some dependencies misalignment.
# Handles cross-major boundaries (e.g. from 5.0 back to 4.22).
rhocp_versions="${major}.${minor}"
cur_major=$major
cur_minor=$minor
for ((i = 0; i < 2; i++)); do
    prev_major=""
    prev_minor=""
    get_prev_version "${cur_major}" "${cur_minor}"
    if [[ -z "${prev_minor}" ]]; then
        break
    fi
    rhocp_versions+=" ${prev_major}.${prev_minor}"
    cur_major="${prev_major}"
    cur_minor="${prev_minor}"
done
rhocp_versions+=" "

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
URL:            https://github.com/microshift-io/microshift
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
