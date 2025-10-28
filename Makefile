#
# The following variables can be overriden from the command line
# using NAME=value make arguments
#

# Options used in the 'rpm' target
USHIFT_BRANCH ?= main
OKD_VERSION_TAG ?= $$(curl -s https://quay.io/api/v1/repository/okd/scos-release/tag/ | jq -r ".tags[].name" | sort | tail -1)
RPM_OUTDIR ?=
# Options used in the 'image' target
BOOTC_IMAGE_URL ?= quay.io/centos-bootc/centos-bootc
BOOTC_IMAGE_TAG ?= stream9
WITH_KINDNET ?= 1
WITH_TOPOLVM ?= 1
WITH_OLM ?= 0
EMBED_CONTAINER_IMAGES ?= 0
# Options used in the 'run' target
LVM_VOLSIZE ?= 1G
ISOLATED_NETWORK ?= 0

# Internal variables
SHELL := /bin/bash
BUILDER_IMAGE := microshift-okd-builder
SRPM_BUILDER_IMAGE := microshift-srpm-builder
USHIFT_IMAGE := microshift-okd
LVM_DISK := /var/lib/microshift-okd/lvmdisk.image
VG_NAME := myvg1

#
# Define the main targets
#
.PHONY: all
all:
	@echo "make <rpm | image | run | add-node | start | stop | clean | check>"
	@echo "   rpm:       	build the MicroShift RPMs"
	@echo "   image:     	build the MicroShift bootc container image"
	@echo "   run:       	create and run a MicroShift cluster (1 node) in a bootc container"
	@echo "   add-node:  	add a new node to the MicroShift cluster in a bootc container"
	@echo "   start:     	start the MicroShift cluster that was already created"
	@echo "   stop:      	stop the MicroShift cluster"
	@echo "   clean:     	clean up the MicroShift cluster and the LVM backend"
	@echo "   check:     	run the presubmit checks"
	@echo ""
	@echo "Sub-targets:"
	@echo "   rpm-to-deb:	convert the MicroShift RPMs to Debian packages"
	@echo "   run-ready: 	wait until the MicroShift service is ready across the cluster"
	@echo "   run-healthy:	wait until the MicroShift service is healthy across the cluster"
	@echo "   run-status:	show the status of the MicroShift cluster"
	@echo "   clean-all:	perform a full cleanup, including the container images"
	@echo ""

.PHONY: rpm
rpm:
	@echo "Building the MicroShift builder image"
	sudo podman build \
        -t "${BUILDER_IMAGE}" \
        --ulimit nofile=524288:524288 \
        --build-arg USHIFT_BRANCH="${USHIFT_BRANCH}" \
        --build-arg OKD_VERSION_TAG="${OKD_VERSION_TAG}" \
        -f packaging/microshift-builder.Containerfile .

	@echo "Extracting the MicroShift RPMs"
	outdir="$${RPM_OUTDIR:-$$(mktemp -d /tmp/microshift-rpms-XXXXXX)}" && \
	mntdir="$$(sudo podman image mount "${BUILDER_IMAGE}")" && \
	sudo cp -r "$${mntdir}/home/microshift/microshift/_output/rpmbuild/RPMS/." "$${outdir}" && \
	sudo podman image umount "${BUILDER_IMAGE}" && \
	echo "" && \
	echo "Build completed successfully" && \
	echo "RPMs are available in '$${outdir}'"

.PHONY: srpm
srpm:
	@echo "Building the MicroShift SRPMs"
	outdir="$${SRPM_OUTDIR:-$$(mktemp -d /tmp/microshift-srpms-XXXXXX)}" && \
	sudo podman build \
        -t "${SRPM_BUILDER_IMAGE}" \
		-v "$${outdir}:/output:z" \
        --ulimit nofile=524288:524288 \
        --build-arg USHIFT_BRANCH="${USHIFT_BRANCH}" \
        --build-arg OKD_VERSION_TAG="${OKD_VERSION_TAG}" \
		--build-arg CACHE_BUST="$$(date +%s)" \
        -f packaging/microshift-srpm-builder.Containerfile . && \
	sudo chown -R "$$(id -u):$$(id -g)" "$${outdir}" && \
	echo "" && \
	echo "Build completed successfully" && \
	echo "SRPMs are available in '$${outdir}'"

.PHONY: rpm-to-deb
rpm-to-deb:
	if [ -z "${RPM_OUTDIR}" ] ; then \
		echo "ERROR: RPM_OUTDIR is not set" ; \
		exit 1 ; \
	fi && \
	sudo ./src/deb/convert.sh "${RPM_OUTDIR}" && \
	echo "" && \
	echo "Conversion completed successfully" && \
	echo "Debian packages are available in '${RPM_OUTDIR}/deb'"

.PHONY: image
image:
	@if ! sudo podman image exists microshift-okd-builder ; then \
		echo "ERROR: Run 'make rpm' to build the MicroShift RPMs" ; \
		exit 1 ; \
	fi

	@echo "Building the MicroShift bootc container image"
	sudo podman build \
		-t "${USHIFT_IMAGE}" \
        --ulimit nofile=524288:524288 \
     	--label microshift.branch="${USHIFT_BRANCH}" \
     	--label okd.version="${OKD_VERSION_TAG}" \
        --build-arg BOOTC_IMAGE_URL="${BOOTC_IMAGE_URL}" \
        --build-arg BOOTC_IMAGE_TAG="${BOOTC_IMAGE_TAG}" \
    	--env WITH_KINDNET="${WITH_KINDNET}" \
    	--env WITH_TOPOLVM="${WITH_TOPOLVM}" \
    	--env WITH_OLM="${WITH_OLM}" \
    	--env EMBED_CONTAINER_IMAGES="${EMBED_CONTAINER_IMAGES}" \
        -f packaging/microshift-runner.Containerfile .

# Notes:
# - An isolated network is created if the ISOLATED_NETWORK environment variable is set
# - The /dev directory is shared with the container to enable TopoLVM CSI driver,
#   masking the devices that may conflict with the host
# - The containers storage is mounted on a tmpfs to avoid usage of fuse-overlayfs,
#   which is less efficient than the default driver
.PHONY: run
run:
	@USHIFT_IMAGE=${USHIFT_IMAGE} ISOLATED_NETWORK=${ISOLATED_NETWORK} LVM_DISK=${LVM_DISK} LVM_VOLSIZE=${LVM_VOLSIZE} VG_NAME=${VG_NAME} ./src/cluster_manager.sh create

.PHONY: add-node
add-node:
	@USHIFT_IMAGE=${USHIFT_IMAGE} ISOLATED_NETWORK=${ISOLATED_NETWORK} LVM_DISK=${LVM_DISK} LVM_VOLSIZE=${LVM_VOLSIZE} VG_NAME=${VG_NAME} ./src/cluster_manager.sh add-node

.PHONY: start
start:
	@USHIFT_IMAGE=${USHIFT_IMAGE} ISOLATED_NETWORK=${ISOLATED_NETWORK} LVM_DISK=${LVM_DISK} LVM_VOLSIZE=${LVM_VOLSIZE} VG_NAME=${VG_NAME} ./src/cluster_manager.sh start

.PHONY: stop
stop:
	@USHIFT_IMAGE=${USHIFT_IMAGE} ISOLATED_NETWORK=${ISOLATED_NETWORK} LVM_DISK=${LVM_DISK} LVM_VOLSIZE=${LVM_VOLSIZE} VG_NAME=${VG_NAME} ./src/cluster_manager.sh stop

.PHONY: run-ready
run-ready:
	@echo "Waiting 5m for the MicroShift service to be ready"
	@for _ in $$(seq 60); do \
		if USHIFT_IMAGE=${USHIFT_IMAGE} ISOLATED_NETWORK=${ISOLATED_NETWORK} LVM_DISK=${LVM_DISK} LVM_VOLSIZE=${LVM_VOLSIZE} VG_NAME=${VG_NAME} ./src/cluster_manager.sh ready ; then \
			printf "\nOK\n" && exit 0; \
		fi ; \
		sleep 5 ; \
	done ; \
	printf "\nFAILED\n" && exit 1

.PHONY: run-healthy
run-healthy:
	@echo "Waiting 15m for the MicroShift service to be healthy"
	@for _ in $$(seq 60); do \
		if USHIFT_IMAGE=${USHIFT_IMAGE} ISOLATED_NETWORK=${ISOLATED_NETWORK} LVM_DISK=${LVM_DISK} LVM_VOLSIZE=${LVM_VOLSIZE} VG_NAME=${VG_NAME} ./src/cluster_manager.sh healthy ; then \
			printf "\nOK\n" && exit 0; \
		fi ; \
		sleep 5 ; \
	done ; \
	printf "\nFAILED\n" && exit 1

.PHONY: run-status
run-status:
	@USHIFT_IMAGE=${USHIFT_IMAGE} ISOLATED_NETWORK=${ISOLATED_NETWORK} LVM_DISK=${LVM_DISK} LVM_VOLSIZE=${LVM_VOLSIZE} VG_NAME=${VG_NAME} ./src/cluster_manager.sh status

.PHONY: clean
clean:
	@USHIFT_IMAGE=${USHIFT_IMAGE} ISOLATED_NETWORK=${ISOLATED_NETWORK} LVM_DISK=${LVM_DISK} LVM_VOLSIZE=${LVM_VOLSIZE} VG_NAME=${VG_NAME} ./src/cluster_manager.sh delete

.PHONY: clean-all
clean-all:
	@echo "Performing a full cleanup"
	$(MAKE) clean
	sudo podman rmi -f "${USHIFT_IMAGE}" || true
	sudo podman rmi -f "${BUILDER_IMAGE}" || true

.PHONY: check
check: _hadolint _shellcheck

#
# Define the private targets
#

# When run inside a container, the file contents are redirected via stdin and
# the output of errors does not contain the file path. Work around this issue
# by replacing the '^-:' token in the output by the actual file name.
.PHONY: _hadolint
_hadolint:
	set -euo pipefail && \
	RET=0 && \
	FILES=$$(find . -iname '*containerfile*' -o -iname '*dockerfile*' | grep -v "vendor\|_output\|origin\|.git") && \
	for f in $${FILES} ; do \
    	echo "$${f}" ; \
    	if ! podman run --rm -i \
        		-v "$(CURDIR)/.hadolint.yaml:/.hadolint.yaml:Z" \
        		ghcr.io/hadolint/hadolint:2.12.0 < "$${f}" | sed "s|^-:|$${f}:|" ; then \
			RET=1 ; \
		fi ; \
	done ; \
	exit $${RET}

.PHONY: _shellcheck
_shellcheck:
	shopt -s globstar nullglob && \
	podman run --rm -i \
		-v "$(CURDIR):/mnt:Z" \
		docker.io/koalaman/shellcheck:v0.11.0 --format=gcc --external-sources \
		**/*.sh
