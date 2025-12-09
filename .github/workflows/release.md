### Install and Run

#### Quick Start

MicroShift can be run on the host or inside a Bootc container.

* Install MicroShift RPM packages on your host and start the MicroShift service.

  ```bash
  curl -s https://microshift-io.github.io/microshift/quickrpm.sh | \
    sudo TAG=${TAG} bash
  ```

* Bootstrap MicroShift inside a Bootc container on your host.

  ```bash
  curl -s https://microshift-io.github.io/microshift/quickstart.sh | \
    sudo TAG=${TAG} bash
  ```

#### RPM and DEB

Review the instructions in [MicroShift Host Deployment](https://github.com/microshift-io/microshift/blob/main/docs/run.md) to install the packages and run MicroShift.

#### Bootc Image

Load the Bootc container image using the following command:

```bash
sudo podman pull ${IMAGE}:${TAG}
```

Review the instructions in [MicroShift Bootc Deployment](https://github.com/microshift-io/microshift/blob/main/docs/run-bootc.md) to run the image.
