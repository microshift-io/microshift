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
USHIFT_IMAGE := microshift-okd
LVM_DISK := /var/lib/microshift-okd/lvmdisk.image
VG_NAME := myvg1

#
# Define the main targets
#
.PHONY: all
all:
	@echo "make <rpm | image | run | login | stop | clean | check>"
	@echo "   rpm:       	build the MicroShift RPMs"
	@echo "   image:     	build the MicroShift bootc container image"
	@echo "   run:       	run the MicroShift bootc container"
	@echo "   login:     	login to the MicroShift bootc container"
	@echo "   stop:      	stop the MicroShift bootc container"
	@echo "   clean:     	clean up the MicroShift container and the LVM backend"
	@echo "   check:     	run the presubmit checks"
	@echo ""
	@echo "Sub-targets:"
	@echo "   run-ready: 	wait until the MicroShift service is ready"
	@echo "   run-healthy:	wait until the MicroShift service is healthy"
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

.PHONY: image
image:
	@if ! sudo podman image exists microshift-okd-builder ; then \
		echo "Error: Run 'make rpm' to build the MicroShift RPMs"; \
		exit 1; \
	fi

	@echo "Building the MicroShift bootc container image"
	sudo podman build \
		-t "${USHIFT_IMAGE}" \
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
	@echo "Running the MicroShift container"
	sudo modprobe openvswitch
	$(MAKE) _topolvm_create

	NETWORK_OPTS="" ; \
	if [ "${ISOLATED_NETWORK}" = "1" ] ; then \
		NETWORK_OPTS="--network none" ; \
	fi ; \
	VOL_OPTS="--tty --volume /dev:/dev" ; \
	for device in input snd dri; do \
		[ -d "/dev/$${device}" ] && VOL_OPTS="$${VOL_OPTS} --tmpfs /dev/$${device}" ; \
	done ; \
	sudo podman run --privileged --rm -d \
		--replace \
		$${NETWORK_OPTS} \
		$${VOL_OPTS} \
		--tmpfs /var/lib/containers \
		--name "${USHIFT_IMAGE}" \
		--hostname 127.0.0.1.nip.io \
		"${USHIFT_IMAGE}" ; \
	$(MAKE) _isolated_network_config

.PHONY: run-ready
run-ready:
	@echo "Waiting 5m for the MicroShift service to be ready"
	@for _ in $$(seq 60); do \
		if sudo podman exec -i "${USHIFT_IMAGE}" systemctl -q is-active microshift.service ; then \
			printf "\nOK\n" && exit 0; \
		fi ; \
		echo -n "." && sleep 5 ; \
	done ; \
	printf "\nFAILED\n" && exit 1

.PHONY: run-healthy
run-healthy:
	@echo "Waiting 15m for the MicroShift service to be healthy"
	@for _ in $$(seq 60); do \
		state=$$(sudo podman exec -i "${USHIFT_IMAGE}" systemctl show --property=SubState --value greenboot-healthcheck) ; \
		if [ "$${state}" = "exited" ] ; then \
			printf "\nOK\n" && exit 0; \
		fi ; \
		echo -n "." && sleep 15 ; \
	done ; \
	printf "\nThe state of the greenboot-healthcheck service is '$${state}'" && \
	printf "\nFAILED\n" && exit 1

.PHONY: login
login:
	@echo "Logging into the MicroShift container"
	sudo podman exec -it "${USHIFT_IMAGE}" bash

.PHONY: stop
stop:
	@echo "Stopping the MicroShift container"
	sudo podman stop --time 0 "${USHIFT_IMAGE}" || true

.PHONY: clean
clean:
	@echo "Cleaning up the MicroShift container and the TopoLVM CSI backend"
	$(MAKE) stop
	sudo rmmod openvswitch || true
	$(MAKE) _topolvm_delete

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
# The configurations for the isolated network are done inside the container
.PHONY: _isolated_network_config
_isolated_network_config:
	if [ "${ISOLATED_NETWORK}" = "1" ] ; then \
		sudo podman cp ./src/config_isolated_net.sh "${USHIFT_IMAGE}:/tmp/config_isolated_net.sh" && \
		sudo podman exec -i "${USHIFT_IMAGE}" /tmp/config_isolated_net.sh && \
		sudo podman exec -i "${USHIFT_IMAGE}" rm -vf /tmp/config_isolated_net.sh ; \
	fi

.PHONY: _topolvm_create
_topolvm_create:
	if [ ! -f "${LVM_DISK}" ] ; then \
		echo "Creating the TopoLVM CSI backend" ; \
		sudo mkdir -p "$$(dirname "${LVM_DISK}")" ; \
		sudo truncate --size="${LVM_VOLSIZE}" "${LVM_DISK}" ; \
		DEVICE_NAME="$$(sudo losetup --find --show --nooverlap "${LVM_DISK}")" && \
		sudo vgcreate -f -y "${VG_NAME}" "$${DEVICE_NAME}" ; \
	fi

.PHONY: _topolvm_delete
_topolvm_delete:
	if [ -f "${LVM_DISK}" ] ; then \
		echo "Deleting the TopoLVM CSI backend" ; \
		sudo lvremove -y "${VG_NAME}" || true ; \
		sudo vgremove -y "${VG_NAME}" || true ; \
		DEVICE_NAME="$$(sudo losetup -j "${LVM_DISK}" | cut -d: -f1)" ; \
		[ -n "$${DEVICE_NAME}" ] && sudo losetup -d $${DEVICE_NAME} || true ; \
		sudo rm -rf "$$(dirname "${LVM_DISK}")" ; \
	fi

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
