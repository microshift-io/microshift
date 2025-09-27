### Install and Run

#### RPM

Review the instructions in [MicroShift RPMs](../../docs/run.md#microshift-rpms)
to install the packages and run MicroShift.

#### Bootc Image

Load the Bootc container image using the following command:

```bash
sudo podman load -i "microshift-bootc-image-$(uname -m).tgz"
```

Review the instructions in [MicroShift Bootc Image](../../docs/run.md#microshift-bootc-image)
to run the image.
