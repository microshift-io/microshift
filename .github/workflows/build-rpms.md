### Install and Run

#### RPM

Review the instructions in [MicroShift RPMs](https://github.com/microshift-io/microshift/blob/main/docs/run.md#microshift-rpms) to install the packages and run MicroShift.

#### Bootc Image

Load the Bootc container image using the following command:

```bash
sudo podman pull ghcr.io/microshift-io/microshift:$TAG
```

Or use the image with the `quickstart.sh`:
```bash
curl -s https://raw.githubusercontent.com/microshift-io/microshift/main/src/quickstart.sh | sudo TAG=$TAG bash
```

Review the instructions in [MicroShift Bootc Image](https://github.com/microshift-io/microshift/blob/main/docs/run.md#microshift-bootc-image) to run the image.
