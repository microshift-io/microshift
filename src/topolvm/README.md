# TopoLVM upstream Integration for MicroShift

This script integrates [TopoLVM](https://github.com/topolvm/topolvm) with
[MicroShift](https://github.com/openshift/microshift) upstream by generating
manifests from helm charts.

TopoLVM is a CSI (Container Storage Interface) driver that provides logical
volume management using LVM, enabling dynamic provisioning, volume resizing,
and topology-aware scheduling.

## Overview

This repository includes:
- **Helm-based manifest generation** for TopoLVM
- A **wrapper script** to automate manifest rendering and deployment
- Configuration tailored for **upstream compatibility**

## Deployment

To install all the prerequisites and generate the TopoLVM manifests,
run the following command:

```bash
./prepare_topolvm_manifests.sh
```

This script will:
- Download cert-manager manifests from the upstream repository
- Download and template the upstream TopoLVM Helm chart
- Patch it for compatibility with MicroShift by changing deployment replicas to 1

The following manifest files will be generated:

```
├── manifests
│   ├── cert-manager.yaml
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   └── topolvm.yaml
```

## Integrating with MicroShift RPMs

- Clone MicroShift `git clone https://github.com/openshift/microshift.git ~/microshift` 
- Replace the content of ~/microshift/assets/optional/topolvm with the generated `manifests/`
- Build the MicroShift RPMs using `cd ~/microshift && MICROSHIFT_VARIANT=community make rpm`

## License

This project follows the same license as the MicroShift project (Apache License 2.0).
