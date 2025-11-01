
COPR_CONFIG ?= $(HOME)/.config/copr
COPR_BUILDS ?=
COPR_REPO_NAME ?= pmtk0/test123

COPR_SECRET_NAME := copr-cfg
COPR_BUILDER_IMAGE := rpm-copr-builder
COPR_CLI_IMAGE := localhost/copr-cli:latest

.PHONY: copr-rpm
copr-rpm:
	@echo "Building the MicroShift RPMs using the COPR build service"
	sudo podman build \
        --tag "${COPR_BUILDER_IMAGE}" \
		--secret id=${COPR_SECRET_NAME},src=${COPR_CONFIG} \
        --ulimit nofile=524288:524288 \
        --build-arg USHIFT_BRANCH="${USHIFT_BRANCH}" \
        --build-arg OKD_VERSION_TAG="${OKD_VERSION_TAG}" \
		--env COPR_REPO_NAME="${COPR_REPO_NAME}" \
        --file packaging/rpm-copr-builder.Containerfile .

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
