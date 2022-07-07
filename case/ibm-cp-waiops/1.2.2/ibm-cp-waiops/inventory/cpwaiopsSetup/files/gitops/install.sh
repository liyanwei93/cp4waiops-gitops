#!/bin/bash

####################
# Settings
####################

# OS and arch settings
HOSTOS=$(uname -s | tr '[:upper:]' '[:lower:]')
HOSTARCH=$(uname -m)
SAFEHOSTARCH=${HOSTARCH}
if [[ ${HOSTOS} == darwin ]]; then
  SAFEHOSTARCH=amd64
fi
if [[ ${HOSTARCH} == x86_64 ]]; then
  SAFEHOSTARCH=amd64
fi
HOST_PLATFORM=${HOSTOS}_${HOSTARCH}
SAFEHOSTPLATFORM=${HOSTOS}-${SAFEHOSTARCH}

# Directory settings
ROOT_DIR=$(cd -P $(dirname $0) >/dev/null 2>&1 && pwd)
DEPLOY_LOCAL_WORKDIR=${ROOT_DIR}/.work
TOOLS_HOST_DIR=${ROOT_DIR}/.cache/tools/${HOST_PLATFORM}

mkdir -p ${DEPLOY_LOCAL_WORKDIR}
mkdir -p ${TOOLS_HOST_DIR}

# Custom settings
. ${ROOT_DIR}/config.sh

####################
# Utility functions
####################

CYAN="\033[0;36m"
NORMAL="\033[0m"
RED="\033[0;31m"

function info {
  echo -e "${CYAN}INFO  ${NORMAL}$@" >&2
}

function error {
  echo -e "${RED}ERROR ${NORMAL}$@" >&2
}

function wait-deployment {
  local object=$1
  local ns=$2
  echo -n "Waiting for deployment $object in $ns namespace ready "
  retries=600
  until [[ $retries == 0 ]]; do
    echo -n "."
    local result=$(${KUBECTL} get deploy $object -n $ns -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    if [[ $result == 1 ]]; then
      echo " Done"
      break
    fi
    sleep 1
    retries=$((retries - 1))
  done
  [[ $retries == 0 ]] && echo
}

####################
# Preflight check
####################

function preflight-check {
  if ! command -v docker >/dev/null 2>&1; then
    error "docker not installed, exit."
    exit 1
  fi
}

####################
# Install kind
####################

KIND=${TOOLS_HOST_DIR}/kind-${KIND_VERSION}

function install-kind {
  info "Installing kind ${KIND_VERSION} ..."

  if [[ ! -f ${KIND} ]]; then
    curl -fsSLo ${KIND} https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-${SAFEHOSTPLATFORM} || exit -1
    chmod +x ${KIND}
  else
    echo "kind ${KIND_VERSION} detected."
  fi

  info "Installing kind ${KIND_VERSION} ... OK"
}

####################
# Install kubectl
####################

KUBECTL=${TOOLS_HOST_DIR}/kubectl-${KUBECTL_VERSION}

function install-kubectl {
  info "Installing kubectl ${KUBECTL_VERSION} ..."

  if [[ ! -f ${KUBECTL} ]]; then
    curl -fsSLo ${KUBECTL} https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/${HOSTOS}/${SAFEHOSTARCH}/kubectl || exit -1
    chmod +x ${KUBECTL}
  else
    echo "kubectl ${KUBECTL_VERSION} detected."
  fi

  info "Installing kubectl ${KUBECTL_VERSION} ... OK"
}

####################
# Launch kind
####################

function kind-up {
  info "kind up ..."

  KIND_CONFIG_FILE=${DEPLOY_LOCAL_WORKDIR}/kind-${KIND_CLUSTER_NAME}.yaml

  cat << EOF > ${KIND_CONFIG_FILE}
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: "$(print_host_ip)"
  apiServerPort: 6443
nodes:
  - role: control-plane
    image: kindest/node:${K8S_VERSION}
    extraPortMappings:
    - containerPort: 30443
      hostPort: 9443
      listenAddress: "0.0.0.0"
    - containerPort: 30097
      hostPort: 9097
      listenAddress: "0.0.0.0"
    - containerPort: 30445
      hostPort: 9445
      listenAddress: "0.0.0.0"
$(print-extra-port-mappings)
  - role: worker
    image: kindest/node:${K8S_VERSION}
  - role: worker
    image: kindest/node:${K8S_VERSION}
  - role: worker
    image: kindest/node:${K8S_VERSION}
EOF

  ${KIND} get kubeconfig --name ${KIND_CLUSTER_NAME} >/dev/null 2>&1 || ${KIND} create cluster --name=${KIND_CLUSTER_NAME} --config="${KIND_CONFIG_FILE}"

  info "kind up ... OK"
}

function print_host_ip {
  if [[ -z ${KIND_HOST_IP} ]]; then
    KIND_HOST_IP=${KIND_HOST_IP:-$(host $(hostname) | awk '/has.*address/{print $NF; exit}')}
    KIND_HOST_IP=${KIND_HOST_IP:-127.0.0.1}
  fi
  echo ${KIND_HOST_IP}
}

function print-extra-port-mappings {
  local mapping segments
  for mapping in ${EXTRA_PORT_MAPPINGS[@]}; do
    IFS=':' read -ra segments <<< "${mapping}"

    cat << EOF
    - containerPort: ${segments[0]}
      hostPort: ${segments[1]}
      listenAddress: "${segments[2]}"
EOF

  done
}

function kind-down {
  info "kind down ..."

  ${KIND} delete cluster --name=${KIND_CLUSTER_NAME}

  info "kind down ... OK"
}

####################
# Install Argo CD
####################

ARGOCD_CLI=${TOOLS_HOST_DIR}/argocd-${ARGOCD_CLI_VERSION}

function install-argocd {
  info "Installing Argo CD ${ARGOCD_VERSION} ..."

  ${KUBECTL} get ns -o name | grep -q argocd || ${KUBECTL} create namespace argocd
  ${KUBECTL} apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml
  patch-sa-pull-secret argocd-redis -n argocd

  ${KUBECTL} apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/applicationset/${ARGOCD_APPSET_VERSION}/manifests/install.yaml

  wait-deployment argocd-server argocd

  ${KUBECTL} patch service/argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"name":"https", "nodePort": 30443, "port": 443}]}}'

  wait-deployment argocd-applicationset-controller argocd

  restart-pods-with-image-errors -n argocd

  info "Installing Argo CD ${ARGOCD_VERSION} ... OK"
}

function install-argocd-cli {
  info "Installing Argo CD CLI ${ARGOCD_CLI_VERSION} ..."

  if [[ ! -f ${ARGOCD_CLI} ]]; then
    curl -fsSLo ${ARGOCD_CLI} https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_CLI_VERSION}/argocd-${HOSTOS}-${SAFEHOSTARCH} || exit -1
    chmod +x ${ARGOCD_CLI}
  else
    echo "Argo CD CLI ${ARGOCD_CLI_VERSION} detected."
  fi

  info "Installing Argo CD CLI ${ARGOCD_CLI_VERSION} ... OK"
}

####################
# Install Helm CLI
####################

HELM_CLI=${TOOLS_HOST_DIR}/helm-${HELM_VERSION}

function install-helm {
  info "Installing Helm ${HELM_VERSION} ..."

  if [[ ! -f ${HELM_CLI} ]]; then
    curl -fsSLo ${HELM_CLI} https://get.helm.sh/helm-${HELM_VERSION}-${SAFEHOSTARCH}.tar.gz || exit -1
    chmod +x ${HELM_CLI}
  else
    echo "Helm CLI ${HELM_VERSION} detected."
  fi

  info "Installing Helm CLI ${HELM_VERSION} ... OK"
}

####################
# Install KubeSeal CLI
####################

KUBESEAL_CLI=${TOOLS_HOST_DIR}/kubeseal-${KUBESEAL_CLI_VERSION}

function install-kubeseal-cli {
  info "Installing KubeSeal CLI ${KUBESEAL_CLI_VERSION} ..."

  if [[ ! -f ${KUBESEAL_CLI} ]]; then
    curl -fsSLo ${KUBESEAL_CLI} https://github.com/bitnami-labs/sealed-secrets/releases/download/${KUBESEAL_CLI_VERSION}/kubeseal-${HOSTOS}-${SAFEHOSTARCH} || exit -1
    chmod +x ${KUBESEAL_CLI}
  else
    echo "KubeSeal CLI ${KUBESEAL_CLI_VERSION} detected."
  fi

  info "Installing KubeSeal CLI ${KUBESEAL_CLI_VERSION} ... OK"
}

####################
# Install Tekton
####################

function install-tekton {
  info "Installing Tekton ${TEKTON_VERSION} ..."

  ${KUBECTL} apply -f https://storage.googleapis.com/tekton-releases/pipeline/previous/${TEKTON_VERSION}/release.yaml
  ${KUBECTL} apply -f https://storage.googleapis.com/tekton-releases/dashboard/previous/${TEKTON_DASHBOARD_VERSION}/tekton-dashboard-release.yaml

  ${KUBECTL} patch service/tekton-dashboard -n tekton-pipelines -p '{"spec": {"type": "NodePort", "ports": [{"name":"http", "nodePort": 30097, "port": 9097, "targetPort": 9097}]}}'

  wait-deployment tekton-pipelines-controller tekton-pipelines
  wait-deployment tekton-pipelines-webhook tekton-pipelines
  wait-deployment tekton-dashboard tekton-pipelines

  ${KUBECTL} patch cm/feature-flags -n tekton-pipelines -p '{"data": {"enable-api-fields": "alpha"}}'

  ${KUBECTL} apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/git-clone/0.6/git-clone.yaml
  ${KUBECTL} apply -f https://raw.githubusercontent.com/tektoncd/catalog/main/task/ansible-runner/0.2/ansible-runner.yaml
  ${KUBECTL} apply -f ${ROOT_DIR}/../tekton/ -R

  patch-sa-pull-secret default -n default

  info "Installing Tekton ${TEKTON_VERSION} ... OK"
}

####################
# Install Tekton CLI
####################

TEKTON_CLI=${TOOLS_HOST_DIR}/tkn-${TEKTON_CLI_VERSION}
TEKTON_CLI_TEMP=tkn_${TEKTON_CLI_VERSION#v}_${HOSTOS}_${HOSTARCH}

function install-tekton-cli {
  info "Installing Tekton CLI ${TEKTON_CLI_VERSION} ..."

  if [[ ! -f ${TEKTON_CLI} ]]; then
    mkdir -p ${TEKTON_CLI_TEMP}
    curl -fsSLO https://github.com/tektoncd/cli/releases/download/${TEKTON_CLI_VERSION}/${TEKTON_CLI_TEMP}.tar.gz || exit -1
    tar -xvf ${TEKTON_CLI_TEMP}.tar.gz -C ${TEKTON_CLI_TEMP}
    mv ${TEKTON_CLI_TEMP}/tkn ${TEKTON_CLI}
    rm -rf ${TEKTON_CLI_TEMP} ${TEKTON_CLI_TEMP}.tar.gz
  else
    echo "TEKTON CLI ${TEKTON_CLI_VERSION} detected."
  fi

  info "Installing TEKTON CLI ${TEKTON_CLI_VERSION} ... OK"
}

# Install Kube Dashboard
####################

function install-kube-dashboard {
  info "Installing Kube Dashboard ${KUBE_DASHBOARD_VERSION} ..."

  ${KUBECTL} apply -f https://raw.githubusercontent.com/kubernetes/dashboard/${KUBE_DASHBOARD_VERSION}/aio/deploy/recommended.yaml

  patch-sa-pull-secret kubernetes-dashboard -n kubernetes-dashboard

  restart-pods-with-image-errors -n kubernetes-dashboard 30

  wait-deployment kubernetes-dashboard kubernetes-dashboard

  ${KUBECTL} patch service/kubernetes-dashboard -n kubernetes-dashboard -p '{"spec": {"type": "NodePort", "ports": [{"name":"https", "nodePort": 30445, "port": 443}]}}'

  cat << EOF | ${KUBECTL} apply -f -
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF

  info "Installing Kube Dashboard ${KUBE_DASHBOARD_VERSION} ... OK"
}

# Install Helm repo
####################

function install-helm-repo {
  info "Installing Helm Repo ..."
 
  echo "-------------Installing Helm Repo-------------"

  mkdir /opt/charts
  docker run -d \
  -p 8080:8080 \
  -e DEBUG=1 \
  -e STORAGE=local \
  -e STORAGE_LOCAL_ROOTDIR=/charts \
  -v /opt/charts:/charts \
  chartmuseum/chartmuseum:latest

  sleep 10s

  HOSTNAME=$(hostname)
  ${HELM_CLI} repo add localrepo http://${HOSTNAME}:8080
  cp "${casePath}"/inventory/"${inventory}"/files/gitops/aimanager33-0.0.1.tgz /opt/charts
  ${HELM_CLI} search repo localrepo

  echo "done"

  info "Installing Helm Repo http://${HOSTNAME}:8080 ... OK"

}

####################
# Print summary after install
####################

function print-summary {
  cat << EOF

👏 Congratulations! The GitOps demo environment is available!
It launched a kind cluster, installed following tools and applitions:
- kind ${KIND_VERSION}
- kubectl ${KUBECTL_VERSION}
- argocd ${ARGOCD_VERSION}
- argocd cli ${ARGOCD_CLI_VERSION}
- kubeseal cli ${KUBESEAL_CLI_VERSION}
- tekton ${TEKTON_VERSION}
- tekton dashboard ${TEKTON_DASHBOARD_VERSION}
- tekton cli ${TEKTON_CLI_VERSION}
- kube dashboard ${KUBE_DASHBOARD_VERSION}

$(print-console)

For tools you want to run anywhere, create links in a directory defined in your PATH, e.g:
ln -s -f ${KUBECTL} /usr/local/bin/kubectl
ln -s -f ${KIND} /usr/local/bin/kind
ln -s -f ${ARGOCD_CLI} /usr/local/bin/argocd
ln -s -f ${KUBESEAL_CLI} /usr/local/bin/kubeseal
ln -s -f ${TEKTON_CLI} /usr/local/bin/tkn

EOF
}

function print-console {
  ARGOCD_PASSWORD="$(${KUBECTL} -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
  DASHBOARD_TOKEN="$(${KUBECTL} -n kubernetes-dashboard get secret $(${KUBECTL} -n kubernetes-dashboard get sa/admin-user -o jsonpath="{.secrets[0].name}") -o go-template="{{.data.token | base64decode}}")"

  cat << EOF
To access Argo CD UI, open https://$(hostname):9443 in browser.
- username: admin
- password: ${ARGOCD_PASSWORD}

To access Tekton Dashboard UI, open http://$(hostname):9097 in browser.

To access Kube Dashboard UI, open https://$(hostname):9445 in browser.
- Token: ${DASHBOARD_TOKEN}
EOF
}

####################
# Generate cluster info
####################

function gen-cluster-config {
  info "Generating cluster information ..."

  local ns=${1:-dev}

  CLUSTER_CONFIG_PATH=$(cd -P ${ROOT_DIR}/../environments/${ns}/env >/dev/null 2>&1 && pwd)

  KUBESVC_IP=$(${KUBECTL} get service kubernetes -o jsonpath='{.spec.clusterIP}')
  CLUSTER_CONFIG=$(${KIND} get kubeconfig --name ${KIND_CLUSTER_NAME} | sed -e "s|server:\s*.*$|server: https://${KUBESVC_IP}|g")
  ${KUBECTL} create secret generic cluster-config --from-literal=kubeconfig="${CLUSTER_CONFIG}" --dry-run -o yaml > ${CLUSTER_CONFIG_PATH}/cluster-config.yaml
  ${KUBESEAL_CLI} -n ${ns} --controller-namespace argocd < ${CLUSTER_CONFIG_PATH}/cluster-config.yaml > ${CLUSTER_CONFIG_PATH}/cluster-config.json.tmp
  if [[ $? == 0 ]]; then
    mv ${CLUSTER_CONFIG_PATH}/cluster-config.json{.tmp,}
    echo "The file ${CLUSTER_CONFIG_PATH}/cluster-config.json is updated, please check in to git."
  else
    rm ${CLUSTER_CONFIG_PATH}/cluster-config.json.tmp
    exit 1
  fi
  # rm -f ${CLUSTER_CONFIG_PATH}/cluster-config.yaml

  info "Generating cluster information ... OK"
}

####################
# Patch pull secret to sa
####################

function patch-sa-pull-secret {
  local ns='default'
  local sa=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
    -n|--namespace)
      ns="$2"; shift; shift ;;
    *)
      sa+=("$1"); shift ;;
    esac
  done

  if [[ -n ${DOCKER_USERNAME} && -n ${DOCKER_PASSWORD} && -n ${sa[@]} ]]; then
    ${KUBECTL} create secret docker-registry docker-pull --docker-server=docker.io --docker-username=${DOCKER_USERNAME} --docker-password=${DOCKER_PASSWORD} -n ${ns}
    ${KUBECTL} patch ${sa[@]/#/sa/} -n ${ns} -p '{"imagePullSecrets": [{"name": "docker-pull"}]}'
  fi
}

function restart-pods-with-image-errors {
  if [[ -n ${DOCKER_USERNAME} && -n ${DOCKER_PASSWORD} ]]; then

    local ns='default'
    local sleep_in_seconds=0

    while [[ $# -gt 0 ]]; do
      case "$1" in
      -n|--namespace)
        ns="$2"; shift; shift ;;
      *)
        sleep_in_seconds=$1; shift ;;
      esac
    done

    sleep $sleep_in_seconds

    info "Restarting pods with image errors ..."

    ${KUBECTL} get pod --ignore-not-found --no-headers -n ${ns} | grep -E 'ImagePullBackOff|ErrImagePull' | awk '{print $1}' | xargs -r -t ${KUBECTL} delete pod -n ${ns}

    info "Restarting pods with image errors ... OK"

  fi
}

####################
# Print help
####################

function print-help {
  cat << EOF
Usage: $0 up
       $0 down
       $0 cluster-config <namespace>
       $0 patch-sa-pull-secret <sa> -n <namespace>
       $0 console

Examples:
  # Bring up the demo environment on your machine
  $0 up

  # Take down the demo environment on your machine
  $0 down

  # Generate and update the cluster-config secret encrypted by kubeseal for the demo environment
  # <namespace> default to dev if omitted
  $0 cluster-config

  # Patch image pull secret to service account for docker hub access
  $0 patch-sa-pull-secret argocd-redis -n argocd

  # Print Argo CD UI Console access information
  $0 console
EOF
}

####################
# Main entrance
####################

if [[ -n ${DOCKER_USERNAME} && -n ${DOCKER_PASSWORD} ]]; then
  docker login docker.io -u ${DOCKER_USERNAME} -p ${DOCKER_PASSWORD} 2>/dev/null
fi

case $1 in
  "down")
    install-kind
    kind-down
    ;;
  "up")
    install-kubectl
    install-kind
    kind-up
    install-kube-dashboard
    install-argocd
    install-argocd-cli
    install-kubeseal-cli
    install-tekton
    install-tekton-cli
    install-helm
    install-helm-repo
    print-summary
    ;;
  "cluster-config")
    install-kubeseal-cli
    gen-cluster-config ${@:2}
    ;;
  "patch-sa-pull-secret")
    patch-sa-pull-secret ${@:2}
    ;;
  "console")
    print-console
    ;;
  *)
    print-help
    ;;
esac
