#!/bin/bash


repo_path=$1
ocp_major_version=$(dnf --quiet --disablerepo="*" --repofrompath=ushift,file://"${repo_path}" --enablerepo=ushift  repoquery --quiet --qf "%{VERSION}" microshift | cut -d. -f1,2)

USHIFT_LOCAL_REPO_FILE=/etc/yum.repos.d/microshift-local.repo
OCP_MIRROR_REPO_FILE=/etc/yum.repos.d/openshift-mirror-beta.repo

    cat > "${USHIFT_LOCAL_REPO_FILE}" <<EOF
[microshift-local]
name=MicroShift Local Repository
baseurl=${repo_path}
enabled=1
gpgcheck=0
skip_if_unavailable=0
EOF

    cat > "${OCP_MIRROR_REPO_FILE}" <<EOF
[openshift-mirror-beta]
name=OpenShift Mirror Beta Repository
baseurl=https://mirror.openshift.com/pub/openshift-v4/$(uname -m)/dependencies/rpms/${ocp_major_version}-el9-beta/
enabled=1
gpgcheck=0
skip_if_unavailable=0
EOF


