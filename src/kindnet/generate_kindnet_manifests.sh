#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
KINDNET_ASSETS_DIR="${SCRIPT_DIR}/assets/kindnet"

KINDNET_IMAGE_BASE="docker.io/kindest/kindnetd"

KINDNET_FULL_IMAGE_AARCH64="$(cat "${KINDNET_ASSETS_DIR}/release-kindnet-aarch64.json" | jq -r '.images.kindnet')"
KINDNET_FULL_IMAGE_X86_64="$(cat "${KINDNET_ASSETS_DIR}/release-kindnet-x86_64.json" | jq -r '.images.kindnet')"

KINDNET_SHA256_AARCH64="$(echo "${KINDNET_FULL_IMAGE_AARCH64}" | sed -n 's/.*@//p')"
KINDNET_SHA256_X86_64="$(echo "${KINDNET_FULL_IMAGE_X86_64}" | sed -n 's/.*@//p')"

# Pod CIDR configuration (can be overridden)
POD_SUBNET="10.244.0.0/16"

generate_kindnet_manifests() {
    echo "Generating kindnet manifests for kindnetd..."

    # 00-namespace.yaml
    cat >"${KINDNET_ASSETS_DIR}/00-namespace.yaml" <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: kube-kindnet
  labels:
    name: kube-kindnet
    openshift.io/run-level: "0"
    openshift.io/cluster-monitoring: "true"
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
  annotations:
    openshift.io/node-selector: ""
    openshift.io/description: "kindnet Kubernetes components"
    workload.openshift.io/allowed: "management"
EOF

    # 01-service-account.yaml
    cat >"${KINDNET_ASSETS_DIR}/01-service-account.yaml" <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kindnet
  namespace: kube-kindnet
EOF

    # 02-cluster-role.yaml
    cat >"${KINDNET_ASSETS_DIR}/02-cluster-role.yaml" <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kindnet
rules:
  - apiGroups: [""]
    resources:
      - namespaces
      - nodes
      - pods
    verbs:
      - get
      - list
      - patch
      - watch
      - update
  - apiGroups: [""]
    resources:
      - pods
    verbs:
      - get
      - list
      - patch
      - watch
      - delete
  - apiGroups: [""]
    resources:
      - configmaps
    verbs:
      - get
      - create
      - update
      - patch
  - apiGroups: [""]
    resources:
      - services
      - endpoints
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - discovery.k8s.io
    resources:
      - endpointslices
    verbs:
      - list
      - watch
  - apiGroups: ["networking.k8s.io"]
    resources:
      - networkpolicies
    verbs:
      - get
      - list
      - watch
  - apiGroups: ["", "events.k8s.io"]
    resources:
      - events
    verbs:
      - create
      - patch
      - update
  - apiGroups: ["security.openshift.io"]
    resources:
      - securitycontextconstraints
    verbs:
      - use
    resourceNames:
      - privileged
  - apiGroups: [""]
    resources:
      - "nodes/status"
    verbs:
      - patch
      - update
  - apiGroups: ["apiextensions.k8s.io"]
    resources:
      - customresourcedefinitions
    verbs:
      - get
      - list
      - watch
  - apiGroups: ['authentication.k8s.io']
    resources: ['tokenreviews']
    verbs: ['create']
  - apiGroups: ['authorization.k8s.io']
    resources: ['subjectaccessreviews']
    verbs: ['create']
EOF

    # 03-cluster-role-binding.yaml
    cat >"${KINDNET_ASSETS_DIR}/03-cluster-role-binding.yaml" <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kindnet
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kindnet
subjects:
  - kind: ServiceAccount
    name: kindnet
    namespace: kube-kindnet
EOF

    # 04-daemonset.yaml
    cat >"${KINDNET_ASSETS_DIR}/04-daemonset.yaml" <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    app: kindnet
    k8s-app: kindnet
    tier: node
  name: kube-kindnet-ds
  namespace: kube-kindnet
spec:
  selector:
    matchLabels:
      app: kindnet
      k8s-app: kindnet
  template:
    metadata:
      labels:
        app: kindnet
        k8s-app: kindnet
        tier: node
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: kubernetes.io/os
                    operator: In
                    values:
                      - linux
      containers:
        - name: kube-kindnet
          image: kindnet
          imagePullPolicy: IfNotPresent
          env:
          - name: HOST_IP
            valueFrom:
              fieldRef:
                fieldPath: status.hostIP
          - name: POD_IP
            valueFrom:
              fieldRef:
                fieldPath: status.podIP
          - name: POD_SUBNET
            value: ${POD_SUBNET}
          resources:
            requests:
              cpu: 100m
              memory: 50Mi
          securityContext:
            capabilities:
              add:
                - NET_ADMIN
                - NET_RAW
            privileged: false
          volumeMounts:
            - name: cni
              mountPath: /etc/cni/net.d
            - name: xtables-lock
              mountPath: /run/xtables.lock
              readOnly: false
            - name: lib-modules
              mountPath: /lib/modules
              readOnly: true
            - name: nri-plugin
              mountPath: /var/run/nri
      hostNetwork: true
      priorityClassName: system-node-critical
      serviceAccountName: kindnet
      tolerations:
        - effect: NoSchedule
          operator: Exists
      volumes:
        - hostPath:
            path: /etc/cni/net.d
          name: cni
        - hostPath:
            path: /run/xtables.lock
            type: FileOrCreate
          name: xtables-lock
        - name: lib-modules
          hostPath:
            path: /lib/modules
        - name: nri-plugin
          hostPath:
            path: /var/run/nri
EOF

    # kustomization.yaml
    cat >"${KINDNET_ASSETS_DIR}/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - 00-namespace.yaml
  - 01-service-account.yaml
  - 02-cluster-role.yaml
  - 03-cluster-role-binding.yaml
  - 04-daemonset.yaml
EOF

    # kustomization.x86_64.yaml
    cat >"${KINDNET_ASSETS_DIR}/kustomization.x86_64.yaml" <<EOF

images:
  - name: kindnet
    newName: ${KINDNET_IMAGE_BASE}
    digest: ${KINDNET_SHA256_X86_64}
EOF

    # kustomization.aarch64.yaml
    cat >"${KINDNET_ASSETS_DIR}/kustomization.aarch64.yaml" <<EOF

images:
  - name: kindnet
    newName: ${KINDNET_IMAGE_BASE}
    digest: ${KINDNET_SHA256_AARCH64}
EOF

    echo "kindnet manifests generated in ${KINDNET_ASSETS_DIR}"
}

mkdir -p "${KINDNET_ASSETS_DIR}"

generate_kindnet_manifests
