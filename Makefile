#
# The following variables can be overriden from the command line
# using NAME=value make arguments
#
USHIFT_BRANCH ?= main
OKD_VERSION_TAG ?=
RPM_OUTDIR ?=
WITH_KINDNET ?= 1
WITH_TOPOLVM ?= 1
WITH_OLM ?= 0
EMBED_CONTAINER_IMAGES ?= 0
LVM_VOLSIZE ?= 1G
# Internal variables
BUILDER_IMAGE := microshift-okd-builder
USHIFT_IMAGE := microshift-okd
LVM_DISK := /var/lib/microshift-okd/lvmdisk.image
VG_NAME := myvg1

#
# Define the main targets
#
.PHONY: all
all:
	@echo "make <rpm | image | run | login | stop | clean>"
	@echo "   rpm:       build the MicroShift RPMs"
	@echo "   image:     build the MicroShift bootc container image"
	@echo "   run:       run the MicroShift bootc container"
	@echo "   login:     login to the MicroShift bootc container"
	@echo "   stop:      stop the MicroShift bootc container"
	@echo "   clean:     clean up the MicroShift container and the TopoLVM CSI backend"
	@echo "   clean-all: perform a full cleanup, including the container images"
	@echo ""

.PHONY: rpm
rpm: _builder
	@echo "Extracting the MicroShift RPMs"
	outdir="$${RPM_OUTDIR:-$$(mktemp -d /tmp/microshift-rpms-XXXXXX)}" && \
	mntdir="$$(sudo podman image mount "${BUILDER_IMAGE}")" && \
	sudo cp -r "$${mntdir}/home/microshift/microshift/_output/rpmbuild/RPMS/." "$${outdir}" && \
	sudo podman image umount "${BUILDER_IMAGE}" && \
	echo "" && \
	echo "Build completed successfully" && \
	echo "RPMs are available in '$${outdir}'"

.PHONY: image
image: _builder
	@echo "Building the MicroShift bootc container image"
	sudo podman build \
		-t "${USHIFT_IMAGE}" \
    	--env WITH_KINDNET="${WITH_KINDNET}" \
    	--env WITH_TOPOLVM="${WITH_TOPOLVM}" \
    	--env WITH_OLM="${WITH_OLM}" \
    	--env EMBED_CONTAINER_IMAGES="${EMBED_CONTAINER_IMAGES}" \
        -f packaging/microshift-cos9.Containerfile .

.PHONY: run
run:
	@echo "Running the MicroShift container"
	sudo modprobe openvswitch
	$(MAKE) _topolvm_create

	VOL_OPTS="--tty --volume /dev:/dev" ; \
	for device in input snd dri; do \
		[ -d "/dev/$${device}" ] && VOL_OPTS="$${VOL_OPTS} --tmpfs /dev/$${device}" ; \
	done ; \
	sudo podman run --privileged --rm -d \
		--replace \
		$${VOL_OPTS} \
		--name "${USHIFT_IMAGE}" \
		--hostname 127.0.0.1.nip.io \
		"${USHIFT_IMAGE}"

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

#
# Define the private targets
#
.PHONY: _builder
_builder:
	@echo "Building the MicroShift builder image"
ifndef OKD_VERSION_TAG
	$(error Specify USHIFT_BRANCH=value and OKD_VERSION_TAG=value arguments')
endif
	sudo podman build \
        -t "${BUILDER_IMAGE}" \
        --build-arg USHIFT_BRANCH="${USHIFT_BRANCH}" \
    	--build-arg OKD_VERSION_TAG="${OKD_VERSION_TAG}" \
    	--env WITH_KINDNET="${WITH_KINDNET}" \
    	--env WITH_TOPOLVM="${WITH_TOPOLVM}" \
    	--env WITH_OLM="${WITH_OLM}" \
        -f packaging/microshift-cos9-builder.Containerfile .

.PHONY: _topolvm_create
_topolvm_create:
	@echo "Creating the TopoLVM CSI backend"
	sudo mkdir -p "$$(dirname "${LVM_DISK}")"
	sudo truncate --size="${LVM_VOLSIZE}" "${LVM_DISK}"
	DEVICE_NAME="$$(sudo losetup --find --show --nooverlap "${LVM_DISK}")" && \
	sudo vgcreate -f -y "${VG_NAME}" "$${DEVICE_NAME}"

.PHONY: _topolvm_delete
_topolvm_delete:
	@echo "Deleting the TopoLVM CSI backend"
	sudo lvremove -y "${VG_NAME}" || true
	sudo vgremove -y "${VG_NAME}" || true
	DEVICE_NAME="$$(sudo losetup -j "${LVM_DISK}" | cut -d: -f1)" && \
	[ -n "$${DEVICE_NAME}" ] && sudo losetup -d $${DEVICE_NAME} || true
	sudo rm -rf "$$(dirname "${LVM_DISK}")" || true
