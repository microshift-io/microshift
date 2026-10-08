#!/bin/bash

set -eux

KUBECONFIG=${KUBECONFIG:-/var/lib/microshift/resources/kubeadmin/kubeconfig}

ns="test-lvms"
appLabel="app-lvms"

cleanup() {
    oc --kubeconfig "${KUBECONFIG}" delete ns "${ns}" --ignore-not-found 2>/dev/null || true
}
trap cleanup EXIT

echo "INFO: Create Namespace, PVC and Deployment resources..."
oc --kubeconfig "${KUBECONFIG}" create ns "${ns}"

cat <<EOF | oc --kubeconfig "${KUBECONFIG}" -n "${ns}" apply -f -
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: mypvc-lvms
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: topolvm-provisioner
  volumeMode: Filesystem
  resources:
    requests:
      storage: 1Mi
---
kind: Deployment
apiVersion: apps/v1
metadata:
  name: mydep-lvms
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${appLabel}
  template:
    metadata:
      labels:
        app: ${appLabel}
    spec:
      containers:
      - name: http-server
        image: quay.io/openshifttest/hello-openshift@sha256:1e70b596c05f46425c39add70bf749177d78c1e98b2893df4e5ae3883c2ffb5e
        ports:
          - name: httpd
            containerPort: 80
        volumeMounts:
        - name: local
          mountPath: /mnt/storage
      volumes:
      - name: local
        persistentVolumeClaim:
            claimName: mypvc-lvms
EOF

echo "INFO: Waiting for deployment pod to become ready (max 4 minutes)..."
if ! oc --kubeconfig "${KUBECONFIG}" wait pod -n "${ns}" -l "app=${appLabel}" \
        --for=condition=Ready --timeout=240s; then
    echo "ERROR: Deployment pod failed to become ready."
    oc --kubeconfig "${KUBECONFIG}" -n "${ns}" describe pod -l "app=${appLabel}"
    oc --kubeconfig "${KUBECONFIG}" -n "${ns}" get pvc
    oc --kubeconfig "${KUBECONFIG}" -n "${ns}" describe pvc mypvc-lvms
    oc --kubeconfig "${KUBECONFIG}" -n "${ns}" get events --sort-by=.lastTimestamp
    exit 1
fi

podName=$(oc --kubeconfig "${KUBECONFIG}" get pod -n "${ns}" -l "app=${appLabel}" --no-headers | awk '{print $1}')
echo "INFO: Deployment pod ${podName} is Running."

echo "INFO: Check if data can be read/written into pod mounted volume..."
#shellcheck disable=SC2016
oc --kubeconfig "${KUBECONFIG}" exec -n "${ns}" "${podName}" -- /bin/sh -c 'echo Storage_Test $(date) > /mnt/storage/testfile'
data=$(oc --kubeconfig "${KUBECONFIG}" exec -n "${ns}" "${podName}" -- /bin/sh -c 'cat /mnt/storage/testfile')
if [[ ${data} =~ "Storage_Test" ]]; then
    echo "SUCCESS: Data successfully written into pod"
else
    echo "ERROR: Failed to write data into the pod"
    exit 1
fi
