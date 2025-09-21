#
# The following variables can be overriden from the command line
# using NAME=value make arguments
#
USHIFT_BRANCH ?= main
OKD_VERSION_TAG ?=
WITH_KINDNET ?= 1
WITH_TOPOLVM ?= 1
WITH_OLM ?= 0
EMBED_CONTAINER_IMAGES ?= 0

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
rpm:
ifndef OKD_VERSION_TAG
	$(error Run 'make rpm USHIFT_BRANCH=value OKD_VERSION_TAG=value')
endif
	@echo "Building the MicroShift RPMs"
	sudo podman build --target builder \
    	--build-arg USHIFT_BRANCH="${USHIFT_BRANCH}" \
    	--build-arg OKD_VERSION_TAG="${OKD_VERSION_TAG}" \
    	--env WITH_KINDNET="${WITH_KINDNET}" \
    	--env WITH_TOPOLVM="${WITH_TOPOLVM}" \
    	--env WITH_OLM="${WITH_OLM}" \
    	-t microshift-okd -f packaging/microshift-cos9.Containerfile . && \
	outdir="$$(mktemp -d /tmp/microshift-rpms-XXXXXX)" && \
	mntdir="$$(sudo podman image mount microshift-okd)" && \
	sudo cp -r "$${mntdir}/microshift/_output/rpmbuild/RPMS/." "$${outdir}" && \
	sudo podman image umount microshift-okd && \
	echo "" && \
	echo "Build completed successfully" && \
	echo "RPMs are available in '$${outdir}'"

.PHONY: image
image:
ifndef OKD_VERSION_TAG
	$(error Run 'make image USHIFT_BRANCH=value OKD_VERSION_TAG=value')
endif
	@echo "Building the MicroShift bootc container image"
	sudo podman build \
    	--build-arg USHIFT_BRANCH="${USHIFT_BRANCH}" \
    	--build-arg OKD_VERSION_TAG="${OKD_VERSION_TAG}" \
    	--env WITH_KINDNET="${WITH_KINDNET}" \
    	--env WITH_TOPOLVM="${WITH_TOPOLVM}" \
    	--env WITH_OLM="${WITH_OLM}" \
    	--env EMBED_CONTAINER_IMAGES="${EMBED_CONTAINER_IMAGES}" \
    	-t microshift-okd -f packaging/microshift-cos9.Containerfile .

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
		--name microshift-okd \
		--volume /dev:/dev:rslave \
		microshift-okd

.PHONY: login
login:
	@echo "Logging into the MicroShift container"
	sudo podman exec -it microshift-okd bash

.PHONY: stop
stop:
	@echo "Stopping the MicroShift container"
	sudo podman stop --time 0 microshift-okd || true

.PHONY: clean
clean:
	@echo "Cleaning up the MicroShift container"
	sudo podman rmi -f microshift-okd || true
	sudo rmmod openvswitch || true
