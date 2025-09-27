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
# Internal variables
BUILDER_IMAGE := microshift-okd-builder
USHIFT_IMAGE := microshift-okd

#
# Define the main targets
#
.PHONY: all
all:
	@echo "make <rpm | image | run | login | stop | clean>"
	@echo "   rpm:      build the MicroShift RPMs"
	@echo "   image:    build the MicroShift bootc container image"
	@echo "   run:      run the MicroShift bootc container"
	@echo "   login:    login to the MicroShift bootc container"
	@echo "   stop:     stop the MicroShift bootc container"
	@echo "   clean:    clean up the MicroShift container"
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

# Prerequisites for running the MicroShift container:
# - If the OVN-K CNI driver is used (`WITH_KINDNET=0` non-default build option),
#   the `openvswitch` module must be loaded on the host.
# - If the TopoLVM CSI driver is used (`WITH_TOPOLVM=1` default build option),
#   the /dev/dm-* device must be shared with the container.
.PHONY: run
run:
	@echo "Running the MicroShift container"
	sudo modprobe openvswitch
	sudo podman run --privileged --rm -d \
		--name "${USHIFT_IMAGE}" \
		--volume /dev:/dev:rslave \
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
	@echo "Cleaning up the MicroShift container"
	sudo podman rmi -f "${USHIFT_IMAGE}" || true
	sudo podman rmi -f "${BUILDER_IMAGE}" || true
	sudo rmmod openvswitch || true

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
