#!/usr/bin/env bash
set -euxo pipefail

SRPMS="${HOME}/microshift/_output/rpmbuild/SRPMS"

out="$(copr-cli --config /run/secrets/copr-cfg build --nowait "${COPR_REPO_NAME}" "${SRPMS}"/microshift*.src.rpm)"
echo "${out}"

builds=$(echo "$out" | grep "Created builds" | cut -d: -f2 | xargs)
copr-cli watch-build ${builds}
mkdir -p ./rpms
for b in $builds ; do
    copr download-build --rpms --chroot centos-stream-9-x86_64 --dest ./rpms $b;
done

mkdir -p "${HOME}/microshift/_output/rpmbuild/RPMS/"
echo "${builds}" > "${HOME}/microshift/_output/rpmbuild/RPMS/builds.txt"
cp "${HOME}/microshift/_output/rpmbuild/version.txt" "${HOME}/microshift/_output/rpmbuild/RPMS/version.txt"

cp -v ./rpms/centos-stream-9-x86_64/*.rpm "${HOME}/microshift/_output/rpmbuild/RPMS/"
createrepo -v "${HOME}/microshift/_output/rpmbuild/RPMS/"
