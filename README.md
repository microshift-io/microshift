# MicroShift upstream Build and Run Scripts
This repository provides scripts to build and run [MicroShift](https://github.com/openshift/microshift/) upstream.

## Overview

MicroShift is a project that optimizes OpenShift Kubernetes for small form factor and edge computing.
 It is intended for upstream development and testing by building MicroShift directly from the original OpenShift MicroShift sources, while replacing the default payload images with OKD (the community distribution of Kubernetes that powers OpenShift).

The goal is to enable contributors and testers to work with a fully open-source MicroShift setup using OKD components, making it easier to develop, verify, and iterate on features outside the downstream Red Hat payloads.

## MicroShift Upstream Build Process

The RPM/container build process includes the following steps:

1. Replace the MicroShift payload/images with the OKD [released images](https://github.com/okd-project/okd-scos/releases).
2. Build the MicroShift RPMs and repository from the MicroShift source.
3. Build the `microshift-okd` Bootc container based on `centos-bootc:stream9`.
4. Apply upstream customizations (see below).

## Build and Run Microshift upstream without subscription/pull-secret
- Only build the RPMs 
  ```bash
  sudo podman build --target builder --env WITH_FLANNEL=1 --env WITH_TOPOLVM=1 -f microshift-okd-multi-build.Containerfile . -t microshift-okd
  ```
- Build the RPMs & container locally using podman

  - use `ovn-kubernetes` as CNI (default)
    ```bash
        sudo podman build -f microshift-okd-multi-build.Containerfile . -t microshift-okd
    ```
  - To use flannel as CNI
    ```bash
        sudo podman build --env WITH_FLANNEL=1 -f microshift-upstream/microshift-okd-multi-build.Containerfile . -t microshift-okd-4.19
    ```
  - To embed all component images
    ```bash
        sudo podman build --env EMBED_CONTAINER_IMAGES=1 -f microshift-upstream/microshift-okd-multi-build.Containerfile . -t microshift-okd
    ```
  - To use flannel CNI with [TopoLVM](https://github.com/topolvm/topolvm) upstream as CSI 
    ```bash
        sudo podman build --env WITH_FLANNEL=1 --env WITH_TOPOLVM=1 -f okd/src/microshift-okd-multi-build.Containerfile . -t microshift-okd
    ```

- running the container with ovn-kubernetes 
  - make sure to load the openvswitch kernel module  :
    > `sudo modprobe openvswitch`

  - run the container :
    > `sudo podman run --privileged --rm --name microshift-okd -d microshift-okd`

- running the container with TopoLVM upstream

    1. Prepare the LVM backend on the host (example only)
        ```bash
            sudo truncate --size=20G /tmp/lvmdisk
            sudo losetup -f /tmp/lvmdisk
            device_name=$(losetup -j /tmp/lvmdisk | cut -d: -f1)
            sudo vgcreate -f -y myvg1 ${device_name}
            sudo lvcreate -T myvg1/thinpool -L 6G
        ```

    1. Run microshift in container and wait for it to be ready
        ```bash
            sudo podman run --privileged --rm --name microshift-okd \
            --volume /dev:/dev:rslave \
            -d localhost/microshift-okd
        ```
        Note:  We need to mount the entire /dev directory here, as LVM management requires full visibility of new volumes under /dev/dm-*.
    1. Wait for all the components to come up 
        ```bash
        > sudo podman exec  microshift-okd bash -c "microshift healthcheck --namespace topolvm-system --deployments topolvm-controller "
        ??? I0331 14:38:46.838208    5894 service.go:29] microshift.service is enabled 
        ??? I0331 14:38:46.838235    5894 service.go:31] Waiting 5m0s for microshift.service to be ready
        ??? I0331 14:38:46.839291    5894 service.go:38] microshift.service is ready
        ??? I0331 14:38:46.840014    5894 workloads.go:94] Waiting 5m0s for deployment/topolvm-controller in topolvm-system
        ??? I0331 14:38:46.844984    5894 workloads.go:132] Deployment/topolvm-controller in topolvm-system is ready
        ??? I0331 14:38:46.845003    5894 healthcheck.go:75] Workloads are ready

        > oc get pods -A
        NAMESPACE              NAME                                       READY   STATUS    RESTARTS        AGE
        cert-manager           cert-manager-5f864bbfd-bpd6h               1/1     Running   0               4m49s
        cert-manager           cert-manager-cainjector-589dc747b5-cfwjf   1/1     Running   0               4m49s
        cert-manager           cert-manager-webhook-5987c7ff58-mzq6l      1/1     Running   0               4m49s
        kube-flannel           kube-flannel-ds-6nvq6                      1/1     Running   0               4m12s
        kube-proxy             kube-proxy-zlvb2                           1/1     Running   0               4m12s
        kube-system            csi-snapshot-controller-75d84cb97c-nkfsz   1/1     Running   0               4m50s
        openshift-dns          dns-default-dbjh4                          2/2     Running   0               4m1s
        openshift-dns          node-resolver-mt8m7                        1/1     Running   0               4m12s
        openshift-ingress      router-default-59cbb858cc-6mzbx            1/1     Running   0               4m49s
        openshift-service-ca   service-ca-df6759f9d-24d2n                 1/1     Running   0               4m49s
        topolvm-system         topolvm-controller-9cd8649c9-5tcln         5/5     Running   0               4m49s
        topolvm-system         topolvm-lvmd-0-2bmjq                       1/1     Running   0               4m1s
        topolvm-system         topolvm-node-lwxz5                         3/3     Running   1 (3m36s ago)   4m1s
        ```
- connect to the container
   > `sudo podman exec -ti microshift-okd /bin/bash`

- verify everything is working:
  ```bash
    export KUBECONFIG=/var/lib/microshift/resources/kubeadmin/kubeconfig
    > oc get nodes  
    NAME           STATUS   ROLES                         AGE     VERSION
    d2877aa41787   Ready    control-plane,master,worker   7m39s   v1.30.3
    
    > oc get pods
    NAMESPACE                  NAME                                       READY   STATUS    RESTARTS        AGE
    kube-system                csi-snapshot-controller-7d6c78bc58-5p7tb   1/1     Running   0               8m52s
    openshift-dns              dns-default-2q89q                          2/2     Running   0               7m34s
    openshift-dns              node-resolver-k2c5h                        1/1     Running   0               8m54s
    openshift-ingress          router-default-db4b598b9-x8lvb             1/1     Running   0               8m52s
    openshift-ovn-kubernetes   ovnkube-master-c75c7                       4/4     Running   1 (7m36s ago)   8m54s
    openshift-ovn-kubernetes   ovnkube-node-jfx86                         1/1     Running   0               8m54s
    openshift-service-ca       service-ca-68d58669f8-rns2p                1/1     Running   0               8m51s


  ```
  
