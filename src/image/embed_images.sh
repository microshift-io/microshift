#!/bin/bash
set -euo pipefail
set -x

IMAGE_STORAGE_DIR=/usr/lib/containers/storage
IMAGE_LIST_FILE=${IMAGE_STORAGE_DIR}/image-list.txt

# Pull the container images into /usr/lib/containers/storage:
# - Each image goes into a separate sub-directory
# - Sub-directories are named after the image reference string SHA
# - An image list file maps image references to their name SHA
pull_images() {
    mkdir -p "${IMAGE_STORAGE_DIR}"
    for images in /usr/share/microshift/release/release-*"$(uname -m)".json ; do
        for img in $(jq -r ".images[]" "${images}") ; do
            # Skip Red Hat images because they are not available upstream.
            # For example, registry.redhat.io/lvms4 operator images.
            if [[ "${img}" == registry.redhat.io/* ]]; then
                echo "Skipping Red Hat image: ${img}"
                continue
            fi

            sha="$(echo "${img}" | sha256sum | awk '{print $1}')"
            skopeo copy --all --preserve-digests \
                "docker://${img}" "dir:$IMAGE_STORAGE_DIR/${sha}"
            echo "${img},${sha}" >> "${IMAGE_LIST_FILE}"
        done
    done
}

# Install a systemd drop-in unit to address the problem with image upgrades
# overwriting the container images in additional store. The workaround is to
# copy the images from the pre-loaded to the main container storage.
# In this case, it is not necessary to update /etc/containers/storage.conf with
# the additional store path.
# See https://issues.redhat.com/browse/RHEL-75827
install_copy_images_script() {
    cat > /usr/bin/microshift-copy-images <<EOF
#!/bin/bash
set -eux -o pipefail
while IFS="," read -r img sha ; do
    skopeo copy --preserve-digests \
        "dir:${IMAGE_STORAGE_DIR}/\${sha}" \
        "containers-storage:\${img}"
done < "${IMAGE_LIST_FILE}"
EOF

    chmod 755 /usr/bin/microshift-copy-images
    mkdir -p /usr/lib/systemd/system/microshift.service.d

    cat > /usr/lib/systemd/system/microshift.service.d/microshift-copy-images.conf <<'EOF'
[Service]
ExecStartPre=/usr/bin/microshift-copy-images
EOF
}

#
# Main
#

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Run the functions
pull_images
install_copy_images_script
