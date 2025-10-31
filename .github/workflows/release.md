### Install and Run

#### RPM

Enable COPR repository (optionally specify chroot such as `centos-stream-9-{x86_64,aarch64}`, `fedora-42-{x86_64,aarch64}`):
```sh
sudo dnf copr enable $COPR_REPO_NAME [chroot]
```

Next, install MicroShift:
```sh
sudo dnf install -y \
    microshift-$VERSION \
    microshift-kindnet-$VERSION \
    microshift-topolvm-$VERSION
```

Review the instructions in [MicroShift RPMs](https://github.com/microshift-io/microshift/blob/main/docs/run.md#microshift-rpms) to run MicroShift.

#### Bootc Image

Load the Bootc container image using the following command:

```bash
sudo podman pull ghcr.io/microshift-io/microshift:$VERSION
```

Or use the image with the `quickstart.sh`:
```bash
curl -s https://microshift-io.github.io/microshift/quickstart.sh | sudo TAG=$VERSION bash
```

Review the instructions in [MicroShift Bootc Image](https://github.com/microshift-io/microshift/blob/main/docs/run.md#microshift-bootc-image) to run the image.
