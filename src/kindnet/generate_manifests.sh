#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# Assets directories
KINDNET_ASSETS_DIR="${SCRIPT_DIR}/assets/kindnet"
KUBE_PROXY_ASSETS_DIR="${SCRIPT_DIR}/assets/kube-proxy"

# Image configuration
KINDNET_IMAGE_BASE="docker.io/kindest/kindnetd"
KUBE_PROXY_IMAGE_BASE="registry.k8s.io/kube-proxy"

# Network configuration (can be overridden)
POD_SUBNET="10.244.0.0/16"
CLUSTER_CIDR="10.42.0.0/16"

#######################################
# Kindnet image resolution
#######################################

get_kindnet_image_info() {
    echo "Fetching latest kindnet image info..."

    # Get the latest kindnet tag from Docker Hub
    KINDNET_LATEST_TAG="$(curl -s 'https://registry.hub.docker.com/v2/repositories/kindest/kindnetd/tags?page_size=1&ordering=last_updated' | jq -r '.results[0].name')"
    echo "Latest kindnet tag: ${KINDNET_LATEST_TAG}"

    # Get the manifest list to extract architecture-specific digests
    KINDNET_MANIFEST="$(curl -s "https://registry.hub.docker.com/v2/repositories/kindest/kindnetd/tags/${KINDNET_LATEST_TAG}")"
    KINDNET_SHA256_AARCH64="sha256:$(echo "${KINDNET_MANIFEST}" | jq -r '.images[] | select(.architecture == "arm64") | .digest' | sed 's/sha256://')"
    KINDNET_SHA256_X86_64="sha256:$(echo "${KINDNET_MANIFEST}" | jq -r '.images[] | select(.architecture == "amd64") | .digest' | sed 's/sha256://')"

    echo " - aarch64 digest: ${KINDNET_SHA256_AARCH64}"
    echo " - x86_64 digest: ${KINDNET_SHA256_X86_64}"
}

#######################################
# Kube-proxy image resolution
#######################################
get_kube_proxy_image_info() {
    echo "Fetching latest kube-proxy image info..."

    # Fetch all tags from registry.k8s.io and get the latest stable version
    # (excludes alpha, beta, rc versions)
    KUBE_PROXY_LATEST_TAG="$(curl -sL "https://registry.k8s.io/v2/kube-proxy/tags/list" | \
        jq -r '.tags[]' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)"

    if [ -z "${KUBE_PROXY_LATEST_TAG}" ]; then
        echo "Error: No kube-proxy tags found"
        exit 1
    fi
    echo "Latest kube-proxy tag: ${KUBE_PROXY_LATEST_TAG}"

    # Get the manifest list for the tag using OCI registry API
    # We need to accept the manifest list media type to get multi-arch info
    KUBE_PROXY_MANIFEST="$(curl -sL \
        -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" \
        "https://registry.k8s.io/v2/kube-proxy/manifests/${KUBE_PROXY_LATEST_TAG}")"

    # Extract architecture-specific digests from the manifest list
    KUBE_PROXY_SHA256_X86_64="$(echo "${KUBE_PROXY_MANIFEST}" | jq -r '.manifests[] | select(.platform.architecture == "amd64") | .digest')"
    KUBE_PROXY_SHA256_AARCH64="$(echo "${KUBE_PROXY_MANIFEST}" | jq -r '.manifests[] | select(.platform.architecture == "arm64") | .digest')"

    echo " - aarch64 digest: ${KUBE_PROXY_SHA256_AARCH64}"
    echo " - x86_64 digest: ${KUBE_PROXY_SHA256_X86_64}"
}

#######################################
# Kindnet manifest generation
#######################################

generate_kindnet_manifests() {
    echo "Generating kindnet manifests..."

    mkdir -p "${KINDNET_ASSETS_DIR}"

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

    # release-kindnet-aarch64.json
    cat >"${KINDNET_ASSETS_DIR}/release-kindnet-aarch64.json" <<EOF
{
  "images": {
    "kindnet": "${KINDNET_IMAGE_BASE}@${KINDNET_SHA256_AARCH64}"
  }
}
EOF

    # release-kindnet-x86_64.json
    cat >"${KINDNET_ASSETS_DIR}/release-kindnet-x86_64.json" <<EOF
{
  "images": {
    "kindnet": "${KINDNET_IMAGE_BASE}@${KINDNET_SHA256_X86_64}"
  }
}
EOF

    echo "kindnet manifests generated in ${KINDNET_ASSETS_DIR}"
}

#######################################
# Kube-proxy manifest generation
#######################################

generate_kube_proxy_manifests() {
    echo "Generating kube-proxy manifests..."

    mkdir -p "${KUBE_PROXY_ASSETS_DIR}"

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

    # release-kube-proxy-aarch64.json
    cat >"${KUBE_PROXY_ASSETS_DIR}/release-kube-proxy-aarch64.json" <<EOF
{
  "images": {
    "kube-proxy": "${KUBE_PROXY_IMAGE_BASE}@${KUBE_PROXY_SHA256_AARCH64}"
  }
}
EOF

    # release-kube-proxy-x86_64.json
    cat >"${KUBE_PROXY_ASSETS_DIR}/release-kube-proxy-x86_64.json" <<EOF
{
  "images": {
    "kube-proxy": "${KUBE_PROXY_IMAGE_BASE}@${KUBE_PROXY_SHA256_X86_64}"
  }
}
EOF

    echo "kube-proxy manifests generated in ${KUBE_PROXY_ASSETS_DIR}"
}

#######################################
# Main
#######################################

main() {
    echo "========================================="
    echo "Generating kindnet and kube-proxy manifests"
    echo "========================================="
    echo ""

    # Fetch image info
    get_kindnet_image_info
    echo ""
    get_kube_proxy_image_info
    echo ""

    # Generate manifests
    generate_kindnet_manifests
    echo ""
    generate_kube_proxy_manifests
    echo ""

    echo "========================================="
    echo "All manifests generated successfully!"
    echo "========================================="
}

main "$@"
