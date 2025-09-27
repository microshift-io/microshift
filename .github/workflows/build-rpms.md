### Install and Run

#### RPM

Review the instructions in [MicroShift RPMs](https://github.com/microshift-io/microshift/blob/main/docs/run.md#microshift-rpms)
to install the packages and run MicroShift.

#### Bootc Image

Load the Bootc container image using the following command:

```bash
sudo podman load -i "microshift-bootc-image-$(uname -m).tgz"
```

Review the instructions in [MicroShift Bootc Image](https://github.com/microshift-io/microshift/blob/main/docs/run.md#microshift-bootc-image)
to run the image.
