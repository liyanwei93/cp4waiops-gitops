# The version of kind
KIND_VERSION=${KIND_VERSION:-v0.11.1}
# The version of kubernetes
K8S_VERSION=${K8S_VERSION:-v1.21.2}
# The version of kubectl
KUBECTL_VERSION=${KUBECTL_VERSION:-v1.17.11}
# The version of argocd
ARGOCD_VERSION=${ARGOCD_VERSION:-v2.2.5}
# The version of argocd cli
ARGOCD_CLI_VERSION=${ARGOCD_CLI_VERSION:-v2.2.5}
# The version of argocd application set
ARGOCD_APPSET_VERSION=${ARGOCD_APPSET_VERSION:-v0.3.0}
# The version of kubeseal cli
KUBESEAL_CLI_VERSION=${KUBESEAL_CLI_VERSION:-v0.16.0}
# The version of tekton
TEKTON_VERSION=${TEKTON_VERSION:-v0.35.0}
# The version of tekton dashboard
TEKTON_DASHBOARD_VERSION=${TEKTON_DASHBOARD_VERSION:-v0.25.0}
# The version of tekton cli
TEKTON_CLI_VERSION=${TEKTON_CLI_VERSION:-v0.23.1}
# The version of kube dashboard
KUBE_DASHBOARD_VERSION=${KUBE_DASHBOARD_VERSION:-v2.0.0}
# The version of helm cli
HELM_VERSION=${HELM_VERSION:-v3.9.0}
# The KIND custom settings
# ----------------------------------------------------
# The KIND cluster name
KIND_CLUSTER_NAME=${KIND_CLUSTER_NAME:-gitops-sandbox}
# The KIND host IP
KIND_HOST_IP=${KIND_HOST_IP:-}
# The extra port mapings
EXTRA_PORT_MAPPINGS=(
  "30388:30388:0.0.0.0"
)
# The Docker Hub credential
DOCKER_USERNAME=${DOCKER_USERNAME:-}
DOCKER_PASSWORD=${DOCKER_PASSWORD:-}
