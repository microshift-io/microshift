#!/bin/bash
set -euo pipefail

MICROSHIFT_ROOT="/home/microshift/microshift"
declare -A UNAME_TO_GOARCH_MAP=( ["x86_64"]="amd64" ["aarch64"]="arm64" )

verify() {
    local -r okd_url=$1
    local -r okd_releaseTag=$2

    if ! stdout=$(oc adm release info "${okd_url}:${okd_releaseTag}" 2>&1)  ; then
        echo -e "error verifying okd release (URL: ${okd_url} , TAG: ${okd_releaseTag}) \nERROR: ${stdout}"
        exit 1
    fi
}

replace_base_assets() {
    local -r okd_url=$1
    local -r okd_releaseTag=$2
    local -r arch=$(uname -m)
    local -r temp_json=$(mktemp "/tmp/release-${arch}.XXXXX.json")

    # Replace Microshift images with upstream (from OKD release)
    local -r okd_json=$(mktemp "/tmp/okd-release.XXXXX.json")
    oc adm release info "${okd_url}:${okd_releaseTag}" -o json > "${okd_json}"

    for op in $(jq -e -r  '.images | keys []' "${MICROSHIFT_ROOT}/assets/release/release-${arch}.json")
    do
        local image
        image=$(jq -r --arg NAME "${op}" '.references.spec.tags[] | select(.name == $NAME) | .from.name' "${okd_json}" || true)
        if [ -n "${image}" ] ; then
            echo "${op} ${image}"
            jq --arg a "${op}" --arg b "${image}"  '.images[$a] = $b' "${MICROSHIFT_ROOT}/assets/release/release-${arch}.json" >"${temp_json}"
            mv "${temp_json}" "${MICROSHIFT_ROOT}/assets/release/release-${arch}.json"
        fi
    done

    pod_image=$(jq -r --arg NAME pod '.references.spec.tags[] | select(.name == $NAME) | .from.name' "${okd_json}" || true)
    # Update the infra pods for crio
    sed -i 's,pause_image .*,pause_image = '"\"${pod_image}\""',' "${MICROSHIFT_ROOT}/packaging/crio.conf.d/10-microshift_${UNAME_TO_GOARCH_MAP[${arch}]}.conf"
}

replace_olm_assets() {
    local -r okd_url=$1
    local -r okd_releaseTag=$2
    local -r arch=$(uname -m)
    local -r temp_json=$(mktemp "/tmp/release-olm-${arch}.XXXXX.json")

    # Install the yq tool
    "${MICROSHIFT_ROOT}"/scripts/fetch_tools.sh yq

    # Replace olm images with upstream (from OKD release)
    # This is extracted from openshift/microshift/scripts/auto-rebase/rebase.sh and modified to work with OKD release
    local olm_image_refs_file="${MICROSHIFT_ROOT}/assets/optional/operator-lifecycle-manager/image-references"
    local kustomization_arch_file="${MICROSHIFT_ROOT}/assets/optional/operator-lifecycle-manager/kustomization.${arch}.yaml"
    local olm_release_json="${MICROSHIFT_ROOT}/assets/optional/operator-lifecycle-manager/release-olm-${arch}.json"

    # Create the OLM release-${arch}.json file with base structure
    jq -n '{"release": {"base": "upstream"}, "images": {}}' > "${olm_release_json}"

    # Create extra kustomization for each arch in separate file
    cat <<EOF > "${kustomization_arch_file}"

images:
EOF

    local -r okd_json=$(mktemp "/tmp/okd-release.XXXXX.json")
    oc adm release info "${okd_url}:${okd_releaseTag}" -o json > "${okd_json}"

    # Read from the image-references file to find the images we need to update
    local -r containers=$("${MICROSHIFT_ROOT}"/_output/bin/yq -r '.spec.tags[].name' "${olm_image_refs_file}")
    for container in "${containers[@]}" ; do
        # Get image (registry.com/image) without the tag or digest from image-references
        local orig_image_name
        orig_image_name=$("${MICROSHIFT_ROOT}"/_output/bin/yq -r ".spec.tags[] | select(.name == \"${container}\") | .from.name" "${olm_image_refs_file}" | awk -F '[@:]' '{ print $1; }')

        # Get the new image from OKD release
        local new_image
        new_image=$(jq -r --arg NAME "${op}" '.references.spec.tags[] | select(.name == $NAME) | .from.name' "${okd_json}" || true)

        if [ -n "${new_image}" ] ; then
            echo "${container} ${new_image}"
            local new_image_name="${new_image%@*}"
            local new_image_digest="${new_image#*@}"

            # Update kustomization file with image mapping
            cat <<EOF >> "${kustomization_arch_file}"
  - name: ${orig_image_name}
    newName: ${new_image_name}
    digest: ${new_image_digest}
EOF

            # Update JSON file
            jq --arg container "${container}" --arg img "${new_image}" '.images[$container] = $img' "${olm_release_json}" >"${temp_json}"
            mv "${temp_json}" "${olm_release_json}"
        fi
    done

    # Add patches section for environment variables
    # Get specific images for the patches
    local olm_image
    olm_image=$(oc adm release info --image-for="operator-lifecycle-manager" "${okd_url}:${okd_releaseTag}" || true)
    local registry_image
    registry_image=$(oc adm release info --image-for="operator-registry" "${okd_url}:${okd_releaseTag}" || true)

    if [ -n "${olm_image}" ] && [ -n "${registry_image}" ] ; then
        cat << EOF >> "${kustomization_arch_file}"

patches:
  - patch: |-
     - op: add
       path: /spec/template/spec/containers/0/env/-
       value:
         name: OPERATOR_REGISTRY_IMAGE
         value: ${registry_image}
     - op: add
       path: /spec/template/spec/containers/0/env/-
       value:
         name: OLM_IMAGE
         value: ${olm_image}
    target:
      kind: Deployment
      labelSelector: app=catalog-operator
EOF
    fi
}

replace_kindnet_assets() {
    local -r okd_url=$1
    local -r okd_releaseTag=$2
    local -r arch=$(uname -m)
    local -r temp_json=$(mktemp "/tmp/release-kindnet-${arch}.XXXXX.json")

    # Install the yq tool
    "${MICROSHIFT_ROOT}"/scripts/fetch_tools.sh yq

    # kube proxy is required for kindnet
    local -r image_with_hash=$(oc adm release info --image-for="kube-proxy" "${okd_url}:${okd_releaseTag}")
    echo "kube-proxy ${image_with_hash}"
    # The OKD image we retrieve is in the format quay.io/okd/scos-content@sha256:<hash>,
    # where the image name and digest (hash) are combined in a single string.
    # However, in the kustomization.${arch}.yaml file, we need the image name (newName) and
    # the digest in separate fields. To achieve this, we first extract the image name and digest
    # using parameter expansion, then use the yq command to insert these values into the
    # appropriate places within the YAML file.
    local -r image_name="${image_with_hash%%@*}"
    local -r image_hash="${image_with_hash##*@}"

    # Update the image and hash
    "${MICROSHIFT_ROOT}"/_output/bin/yq eval \
        ".images[] |= select(.name == \"kube-proxy\") |= (.newName = \"${image_name}\" | .digest = \"${image_hash}\")" \
        -i "${MICROSHIFT_ROOT}/assets/optional/kube-proxy/kustomization.${arch}.yaml"
    jq --arg img "$image_with_hash" '.images["kube-proxy"] = $img' \
        "${MICROSHIFT_ROOT}/assets/optional/kube-proxy/release-kube-proxy-${arch}.json" >"${temp_json}"
    mv "${temp_json}" "${MICROSHIFT_ROOT}/assets/optional/kube-proxy/release-kube-proxy-${arch}.json"
}

fix_rpm_spec() {
    # Fix the RPM spec by removing the microshift-networking package hard dependency
    sed -i 's/Requires: microshift-networking/Recommends: microshift-networking/' "${MICROSHIFT_ROOT}/packaging/rpm/microshift.spec"
}

usage() {
    echo "Usage:"
    echo "$(basename "$0") --verify          OKD_URL RELEASE_TAG    verify OKD upstream release"
    echo "$(basename "$0") --replace         OKD_URL RELEASE_TAG    replace MicroShift assets with OKD upstream images"
    echo "$(basename "$0") --replace-kindnet OKD_URL RELEASE_TAG    replace Kindnet assets with OKD upstream images"
    exit 1
}

#
# Main
#
if [ $# -ne 3 ] ; then
    usage
fi

case "$1" in
--replace)
    verify              "$2" "$3"
    replace_base_assets "$2" "$3"
    replace_olm_assets  "$2" "$3"
    fix_rpm_spec
    ;;
--replace-kindnet)
    verify                 "$2" "$3"
    replace_kindnet_assets "$2" "$3"
    ;;
--verify)
    verify "$2" "$3"
    ;;
*)
    usage
    ;;
esac
