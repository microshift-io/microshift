#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
KUBE_PROXY_ASSETS_DIR="${SCRIPT_DIR}/assets/kube-proxy"

KUBE_PROXY_IMAGE_BASE="quay.io/okd/scos-content"

KUBE_PROXY_FULL_IMAGE_AARCH64="$(cat "${KUBE_PROXY_ASSETS_DIR}/release-kube-proxy-aarch64.json" | jq -r '.images."kube-proxy"')"
KUBE_PROXY_FULL_IMAGE_X86_64="$(cat "${KUBE_PROXY_ASSETS_DIR}/release-kube-proxy-x86_64.json" | jq -r '.images."kube-proxy"')"

KUBE_PROXY_SHA256_AARCH64="$(echo "${KUBE_PROXY_FULL_IMAGE_AARCH64}" | sed -n 's/.*@//p')"
KUBE_PROXY_SHA256_X86_64="$(echo "${KUBE_PROXY_FULL_IMAGE_X86_64}" | sed -n 's/.*@//p')"

# Cluster CIDR configuration (can be overridden)
CLUSTER_CIDR="10.42.0.0/16"

generate_kube_proxy_manifests() {
    echo "Generating kube-proxy manifests..."

    # 00-namespace.yaml
    cat >"${KUBE_PROXY_ASSETS_DIR}/00-namespace.yaml" <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: kube-proxy
  labels:
    name: kindnet
    openshift.io/run-level: "0"
    openshift.io/cluster-monitoring: "true"
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
  annotations:
    openshift.io/node-selector: ""
    openshift.io/description: "kube-proxy Kubernetes components"
    workload.openshift.io/allowed: "management"
EOF

    # 01-service-account.yaml
    cat >"${KUBE_PROXY_ASSETS_DIR}/01-service-account.yaml" <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    k8s-app: kube-proxy
  name: kube-proxy
  namespace: kube-proxy
EOF

    # 02-cluster-role.yaml
    cat >"${KUBE_PROXY_ASSETS_DIR}/02-cluster-role.yaml" <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: system:kube-proxy
rules:
  - apiGroups:
      - ""
    resources:
      - services
      - endpoints
      - nodes
      - configmaps
    verbs:
      - list
      - watch
      - get
  - apiGroups: ["discovery.k8s.io"]
    resources:
      - endpointslices
    verbs:
      - list
      - watch
      - get
EOF

    # 03-cluster-role-binding.yaml
    cat >"${KUBE_PROXY_ASSETS_DIR}/03-cluster-role-binding.yaml" <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-proxy
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-proxy
subjects:
  - kind: ServiceAccount
    name: kube-proxy
    namespace: kube-proxy
EOF

    # 04-configmap.yaml
    cat >"${KUBE_PROXY_ASSETS_DIR}/04-configmap.yaml" <<EOF
apiVersion: v1
data:
  config.conf: |
    apiVersion: kubeproxy.config.k8s.io/v1alpha1
    kind: KubeProxyConfiguration
    clusterCIDR: ${CLUSTER_CIDR}
    mode: iptables
    clientConnection:
      kubeconfig: /var/lib/kubeconfig
    iptables:
      masqueradeAll: true
    conntrack:
      maxPerCore: 0
    featureGates:
      AllAlpha: false
kind: ConfigMap
metadata:
  labels:
    app: kube-proxy
    k8s-app: kube-proxy
  name: kube-proxy
  namespace: kube-proxy
EOF

    # 05-daemonset.yaml
    cat >"${KUBE_PROXY_ASSETS_DIR}/05-daemonset.yaml" <<'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kube-proxy
  namespace: kube-proxy
spec:
  selector:
    matchLabels:
      k8s-app: kube-proxy
  template:
    metadata:
      labels:
        k8s-app: kube-proxy
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
      serviceAccountName: kube-proxy  # Reference the Service Account here
      containers:
        - name: kube-proxy
          image: kube-proxy
          command:
            - /usr/bin/kube-proxy
            - --config=/var/lib/kube-proxy/config.conf
          volumeMounts:
            - name: config
              mountPath: /var/lib/kube-proxy/
              readOnly: true
            - name: kubeconfig
              mountPath: /var/lib/kubeconfig
              readOnly: true
          securityContext:
            privileged: true
      hostNetwork: true  # Allows the pod to use the host network
      dnsPolicy: ClusterFirstWithHostNet
      tolerations:
        - effect: NoSchedule
          operator: Exists
      volumes:
        - name: config
          configMap:
            name: kube-proxy
        - hostPath:
            path: /var/lib/microshift/resources/kubeadmin/kubeconfig
            type: FileOrCreate
          name: kubeconfig
EOF

    # kustomization.yaml
    cat >"${KUBE_PROXY_ASSETS_DIR}/kustomization.yaml" <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - 00-namespace.yaml
  - 01-service-account.yaml
  - 02-cluster-role.yaml
  - 03-cluster-role-binding.yaml
  - 04-configmap.yaml
  - 05-daemonset.yaml
EOF

    # kustomization.x86_64.yaml
    cat >"${KUBE_PROXY_ASSETS_DIR}/kustomization.x86_64.yaml" <<EOF

images:
  - name: kube-proxy
    newName: ${KUBE_PROXY_IMAGE_BASE}
    digest: ${KUBE_PROXY_SHA256_X86_64}
EOF

    # kustomization.aarch64.yaml
    cat >"${KUBE_PROXY_ASSETS_DIR}/kustomization.aarch64.yaml" <<EOF

images:
  - name: kube-proxy
    newName: ${KUBE_PROXY_IMAGE_BASE}
    digest: ${KUBE_PROXY_SHA256_AARCH64}
EOF

    echo "kube-proxy manifests generated in ${KUBE_PROXY_ASSETS_DIR}"
}

mkdir -p "${KUBE_PROXY_ASSETS_DIR}"

generate_kube_proxy_manifests
