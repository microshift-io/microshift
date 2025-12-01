COPR_CONFIG ?= $(HOME)/.config/copr
COPR_REPO_NAME ?= "@microshift-io/microshift"

COPR_SECRET_NAME := copr-cfg
COPR_BUILDER_IMAGE := rpm-copr-builder
COPR_CLI_IMAGE := localhost/copr-cli:latest

COPR_BUILD_ID ?= $$(cat "${SRPM_WORKDIR}/build.txt")

.PHONY: rpm-copr
rpm-copr:
	@echo "Building MicroShift RPM image using COPR"
	sudo podman build \
        --tag "${COPR_BUILDER_IMAGE}" \
        --build-arg COPR_BUILD_ID="${COPR_BUILD_ID}" \
        --file packaging/rpms-copr.Containerfile .

	@echo "Extracting the MicroShift RPMs"
	outdir="$${RPM_OUTDIR:-$$(mktemp -d /tmp/microshift-rpms-XXXXXX)}" && \
	mntdir="$$(sudo podman image mount "${COPR_BUILDER_IMAGE}")" && \
	sudo cp -r "$${mntdir}/home/microshift/microshift/_output/rpmbuild/RPMS/." "$${outdir}" && \
	sudo podman image umount "${COPR_BUILDER_IMAGE}" && \
	echo "" && \
	echo "Build completed successfully" && \
	echo "RPMs are available in '$${outdir}'"

.PHONY: copr-cfg-ensure-podman-secret
copr-cfg-ensure-podman-secret:
	@echo "Ensuring the COPR secret is available and is up to date"
	if sudo podman secret exists "${COPR_SECRET_NAME}"; then \
		sudo podman secret rm "${COPR_SECRET_NAME}" ; \
	fi && \
	sudo podman secret create "${COPR_SECRET_NAME}" "${COPR_CONFIG}"

.PHONY: copr-cli
copr-cli:
	@echo "Building the COPR CLI container"
	sudo podman build \
		--tag "${COPR_CLI_IMAGE}" \
		--file src/copr/copr-cli.Containerfile .

.PHONY: copr-delete-builds
copr-delete-builds: copr-cfg-ensure-podman-secret copr-cli
	@echo "Deleting the COPR builds"
	sudo podman run \
		--rm \
		--secret ${COPR_SECRET_NAME} \
		"${COPR_CLI_IMAGE}" \
		bash -c "copr-cli --config /run/secrets/copr-cfg delete-build ${COPR_BUILDS}"

.PHONY: copr-regenerate-repos
copr-regenerate-repos: copr-cfg-ensure-podman-secret copr-cli
	@echo "Regenerating the COPR repository"
	sudo podman run \
		--rm \
		--secret ${COPR_SECRET_NAME} \
		"${COPR_CLI_IMAGE}" \
		bash -c "copr-cli --config /run/secrets/copr-cfg regenerate-repos ${COPR_REPO_NAME}"

.PHONY: copr-create-build
copr-create-build: copr-cfg-ensure-podman-secret copr-cli
	@echo "Creating the COPR build"
	sudo podman run \
		--rm \
		--secret ${COPR_SECRET_NAME} \
		--env COPR_REPO_NAME="${COPR_REPO_NAME}" \
		--volume "${SRPM_WORKDIR}:/srpms:Z" \
		--volume "./src/copr/create-build.sh:/create-build.sh:Z" \
		"${COPR_CLI_IMAGE}" \
		bash -c "bash -x /create-build.sh"

.PHONY: copr-watch-build
copr-watch-build: copr-cli
	@echo "Watching the COPR build"
	sudo podman run \
		--rm \
		--secret ${COPR_SECRET_NAME} \
		--volume "${SRPM_WORKDIR}:/srpms:Z" \
		"${COPR_CLI_IMAGE}" \
		bash -c "copr-cli watch-build \$$(cat /srpms/build.txt)"
