COPR_CONFIG ?= $(HOME)/.config/copr
COPR_REPO_NAME ?= "@microshift-io/microshift"
COPR_BUILD_ID ?= $(shell cat "${SRPM_WORKDIR}/build.txt" 2>/dev/null)

COPR_SECRET_NAME := copr-cfg
COPR_CLI_IMAGE := localhost/copr-cli:latest
COPR_CHROOT ?= "epel-10-$(shell uname -m)"

.PHONY: copr-help
copr-help:
	@echo "make <rpm-copr | copr-delete-build | copr-regenerate-repos | copr-create-build | copr-watch-build>"
	@echo "   rpm-copr:                         build the MicroShift RPMs using COPR"
	@echo "   copr-delete-build:                delete the COPR build"
	@echo "   copr-regenerate-repos:            regenerate the COPR RPM repository"
	@echo "   copr-create-build:                create the COPR RPM build"
	@echo "   copr-watch-build:                 watch the COPR build"
	@echo "   copr-cfg-ensure-podman-secret:    ensure the COPR secret is available and is up to date"
	@echo "   copr-cli:                         build the COPR CLI container"
	@echo ""
	@echo "Variables:"
	@echo "   COPR_BUILD_ID:                    COPR build ID (default: read from \$$SRPM_WORKDIR/build.txt)"
	@echo "   COPR_REPO_NAME:                   COPR repository name (default: ${COPR_REPO_NAME})"
	@echo "   COPR_CONFIG:                      COPR configuration file - from https://copr.fedorainfracloud.org/api/ (default: ${COPR_CONFIG})"
	@echo "   COPR_CHROOT:                      COPR chroot (default: ${COPR_CHROOT})"
	@echo ""
	@echo "Recommended flow:"
	@echo "   1. mkdir -p /tmp/microshift-srpm-copr"
	@echo "   2. make srpm SRPM_WORKDIR=/tmp/microshift-srpm-copr"
	@echo "   3. make copr-create-build COPR_REPO_NAME=USER/PROJECT SRPM_WORKDIR=/tmp/microshift-srpm-copr"
	@echo "   4. make copr-watch-build SRPM_WORKDIR=/tmp/microshift-srpm-copr"
	@echo "   5. make rpm-copr SRPM_WORKDIR=/tmp/microshift-srpm-copr"
	@echo "   6. make image"
	@echo ""

.PHONY: rpm-copr
rpm-copr:
	@echo "Building MicroShift RPM image using COPR"
	sudo podman build \
        --tag "${RPM_IMAGE}" \
        --build-arg COPR_BUILD_ID="${COPR_BUILD_ID}" \
        --build-arg COPR_CHROOT="${COPR_CHROOT}" \
        --file packaging/rpms-copr.Containerfile .

	@echo "Extracting the MicroShift RPMs"
	outdir="$${RPM_OUTDIR:-$$(mktemp -d /tmp/microshift-rpms-XXXXXX)}" && \
	mntdir="$$(sudo podman image mount "${RPM_IMAGE}")" && \
	trap "sudo podman image umount '${RPM_IMAGE}' >/dev/null" EXIT && \
	sudo cp -r "$${mntdir}/home/microshift/microshift/_output/rpmbuild/RPMS/." "$${outdir}" && \
	echo -e "\nBuild completed successfully\nRPMs are available in '$${outdir}'"

.PHONY: copr-cfg-ensure-podman-secret
copr-cfg-ensure-podman-secret:
	@echo "Ensuring the COPR secret is available and is up to date"
	if sudo podman secret exists "${COPR_SECRET_NAME}"; then \
		sudo podman secret rm "${COPR_SECRET_NAME}" ; \
	fi ; \
	sudo podman secret create "${COPR_SECRET_NAME}" "${COPR_CONFIG}"

.PHONY: copr-cli
copr-cli:
	@echo "Building the COPR CLI container"
	sudo podman build \
		--tag "${COPR_CLI_IMAGE}" \
		--file src/copr/copr-cli.Containerfile src/copr/

.PHONY: copr-delete-build
copr-delete-build: copr-cfg-ensure-podman-secret copr-cli
	@echo "Deleting the COPR build ${COPR_BUILD_ID}"
	sudo podman run \
		--rm \
		--secret ${COPR_SECRET_NAME} \
		"${COPR_CLI_IMAGE}" \
		bash -c "copr-cli --config /run/secrets/${COPR_SECRET_NAME} delete-build ${COPR_BUILD_ID}"

.PHONY: copr-regenerate-repos
copr-regenerate-repos: copr-cfg-ensure-podman-secret copr-cli
	@echo "Regenerating the COPR repository"
	sudo podman run \
		--rm \
		--secret ${COPR_SECRET_NAME} \
		"${COPR_CLI_IMAGE}" \
		bash -c "copr-cli --config /run/secrets/${COPR_SECRET_NAME} regenerate-repos ${COPR_REPO_NAME}"

.PHONY: copr-create-build
copr-create-build: copr-cfg-ensure-podman-secret copr-cli
	@echo "Creating the COPR build"
	@if [ -z "${SRPM_WORKDIR}" ]; then \
		echo "ERROR: SRPM_WORKDIR is not set" ; \
		exit 1 ; \
	fi
	@if [ ! -d "${SRPM_WORKDIR}" ]; then \
		echo "ERROR: ${SRPM_WORKDIR} directory not found" ; \
		exit 1 ; \
	fi
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
		--volume "${SRPM_WORKDIR}:/srpms:Z" \
		"${COPR_CLI_IMAGE}" \
		bash -c "copr-cli watch-build ${COPR_BUILD_ID}"

copr-dependencies: copr-cfg-ensure-podman-secret copr-cli
	@echo "Building RPM with MicroShift dependencies repositories configuration"
	sudo podman run \
		--rm -ti \
		--secret ${COPR_SECRET_NAME},target=/root/.config/copr \
		"${COPR_CLI_IMAGE}" \
		/microshift-io-dependencies.sh "${OKD_VERSION_TAG}" "${COPR_REPO_NAME}"

copr-cni: copr-cfg-ensure-podman-secret copr-cli
	@echo "Building RPM with CNI plugins"
	sudo podman run \
		--rm -ti \
		--secret ${COPR_SECRET_NAME},target=/root/.config/copr \
		"${COPR_CLI_IMAGE}" \
		/cni/build.sh "${COPR_REPO_NAME}"
