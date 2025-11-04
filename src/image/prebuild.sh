#!/bin/bash
set -euo pipefail

MICROSHIFT_ROOT="/home/microshift/microshift"
ARCH="$(uname -m)"
declare -A UNAME_TO_GOARCH_MAP=( ["x86_64"]="amd64" ["aarch64"]="arm64" )

oc_release_info() {
    local -r okd_url=$1
    local -r okd_releaseTag=$2
    local -r image=${3:-}

    if [ -z "${image}" ] ; then
        oc adm release info "${okd_url}:${okd_releaseTag}"
        return
    fi

    local -r okd_image="$(oc adm release info --image-for="${image}" "${okd_url}:${okd_releaseTag}")"
    if [ -z "${okd_image}" ] ; then
        echo "ERROR: No OKD image found for '${image}'"
        exit 1
    fi
    echo "${okd_image}"
}

verify_okd_release() {
    local -r okd_url=$1
    local -r okd_releaseTag=$2

    if ! oc_release_info "${okd_url}" "${okd_releaseTag}" >/dev/null ; then
        echo "ERROR: No OKD release found at '${okd_url}:${okd_releaseTag}'"
        exit 1
    fi
}

replace_base_assets() {
    local -r okd_url=$1
    local -r okd_releaseTag=$2
    local -r temp_json="$(mktemp "/tmp/release-${ARCH}.XXXXX.json")"

    # Replace MicroShift images with OKD upstream images
    for cur_image in $(jq -e -r  '.images | keys []' "${MICROSHIFT_ROOT}/assets/release/release-${ARCH}.json") ; do
        # LVMS operator is not part of the OKD release
        if [ "${cur_image}" = "lvms_operator" ] ; then
            echo "Skipping '${cur_image}'"
            continue
        fi

        local new_image
        new_image=$(oc_release_info "${okd_url}" "${okd_releaseTag}" "${cur_image}")

        echo "Replacing '${cur_image}' with '${new_image}'"
        jq --arg a "${cur_image}" --arg b "${new_image}"  '.images[$a] = $b' "${MICROSHIFT_ROOT}/assets/release/release-${ARCH}.json" >"${temp_json}"
        mv "${temp_json}" "${MICROSHIFT_ROOT}/assets/release/release-${ARCH}.json"
    done

    # Update the infra pods for crio
    local -r pod_image=$(oc_release_info "${okd_url}" "${okd_releaseTag}" "pod")
    sed -i 's,pause_image .*,pause_image = '"\"${pod_image}\""',' "${MICROSHIFT_ROOT}/packaging/crio.conf.d/10-microshift_${UNAME_TO_GOARCH_MAP[${ARCH}]}.conf"
}

# This code is extracted from openshift/microshift/scripts/auto-rebase/rebase.sh
# and modified to work with OKD release
replace_olm_assets() {
    local -r okd_url=$1
    local -r okd_releaseTag=$2
    local -r temp_json=$(mktemp "/tmp/release-olm-${ARCH}.XXXXX.json")

    # Install the yq tool
    "${MICROSHIFT_ROOT}"/scripts/fetch_tools.sh yq

    # Replace OLM images with OKD upstream images
    local olm_image_refs_file="${MICROSHIFT_ROOT}/assets/optional/operator-lifecycle-manager/image-references"
    local kustomization_arch_file="${MICROSHIFT_ROOT}/assets/optional/operator-lifecycle-manager/kustomization.${ARCH}.yaml"
    local olm_release_json="${MICROSHIFT_ROOT}/assets/optional/operator-lifecycle-manager/release-olm-${ARCH}.json"

    # Create the OLM release json file with base structure
    jq -n '{"release": {"base": "upstream"}, "images": {}}' > "${olm_release_json}"

    # Create extra kustomization file for each architecture
    cat <<EOF > "${kustomization_arch_file}"
images:
EOF

    # Read from the image-references file to find the images we need to update
    local -r containers=$("${MICROSHIFT_ROOT}"/_output/bin/yq -r '.spec.tags[].name' "${olm_image_refs_file}")
    # shellcheck disable=SC2068
    for container in ${containers[@]} ; do
        # Get image (registry.com/image) without the tag or digest from image-references
        local orig_image_name
        orig_image_name=$("${MICROSHIFT_ROOT}"/_output/bin/yq -r ".spec.tags[] | select(.name == \"${container}\") | .from.name" "${olm_image_refs_file}" | awk -F '[@:]' '{ print $1; }')

        # Get the new image from OKD release
        local new_image
        new_image=$(oc_release_info "${okd_url}" "${okd_releaseTag}" "${container}")
        echo "Replacing '${container}' with '${new_image}'"
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
    done

    # Add patches section for environment variables
    # Get specific images for the patches
    local -r olm_image=$(oc_release_info "${okd_url}" "${okd_releaseTag}" "operator-lifecycle-manager")
    local -r registry_image=$(oc_release_info "${okd_url}" "${okd_releaseTag}" "operator-registry")

    cat >> "${kustomization_arch_file}" <<EOF
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
}

replace_kindnet_assets() {
    local -r okd_url=$1
    local -r okd_releaseTag=$2
    local -r temp_json="$(mktemp "/tmp/release-kindnet-${ARCH}.XXXXX.json")"

    # Install the yq tool
    "${MICROSHIFT_ROOT}"/scripts/fetch_tools.sh yq

    # Kube proxy is required for kindnet
    local -r image_with_hash=$(oc_release_info "${okd_url}" "${okd_releaseTag}" "kube-proxy")
    echo "Replacing 'kube-proxy' with '${image_with_hash}'"
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
        -i "${MICROSHIFT_ROOT}/assets/optional/kube-proxy/kustomization.${ARCH}.yaml"
    jq --arg img "$image_with_hash" '.images["kube-proxy"] = $img' \
        "${MICROSHIFT_ROOT}/assets/optional/kube-proxy/release-kube-proxy-${ARCH}.json" >"${temp_json}"
    mv "${temp_json}" "${MICROSHIFT_ROOT}/assets/optional/kube-proxy/release-kube-proxy-${ARCH}.json"
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
    verify_okd_release  "$2" "$3"
    replace_base_assets "$2" "$3"
    replace_olm_assets  "$2" "$3"
    fix_rpm_spec
    ;;
--replace-kindnet)
    verify_okd_release     "$2" "$3"
    replace_kindnet_assets "$2" "$3"
    ;;
--verify)
    verify_okd_release "$2" "$3"
    ;;
*)
    usage
    ;;
esac
