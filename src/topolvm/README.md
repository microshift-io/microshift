# TopoLVM upstream Integration for MicroShift

This script integrates [TopoLVM](https://github.com/topolvm/topolvm) with [MicroShift](https://github.com/openshift/microshift) upstream by generating manifests from helm charts. TopoLVM is a CSI (Container Storage Interface) driver that provides logical volume management using LVM, enabling dynamic provisioning, volume resizing, and topology-aware scheduling.

## Overview

This repository includes:
- **Helm-based manifest generation** for TopoLVM
- A **wrapper script** to automate manifest rendering and deployment
- Configuration tailored for **upstream compatibility**

## Deployment

To Install all the pre-req and generate the TopoLVM manifests:

```bash
./prepare_topolvm_manifests.sh
```

This script will:
- download cert-manager manifests from upstream repo
- Download and template the upstream TopoLVM Helm chart
- Patch it for compatibility with MicroShift (changing deployment replicas to 1)

those manifests files will be generated:
```
├── manifests
│   ├── cert-manager.yaml
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   └── topolvm.yaml
```

## Integrating with Microshift RPMs
- clone Microshift `git clone https://github.com/openshift/microshift.git ~/microshift` 
- replace the content of ~/microshift/assets/optional/topolvm with the generated `manifests/`
- build the RPMs using microshift using `cd ~/microshift && make build`

## License

This project follows the same license as the MicroShift project (Apache License 2.0).