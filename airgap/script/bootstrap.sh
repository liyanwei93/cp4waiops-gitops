storage_class=
registry=
user=
pass=
kubernetesCLI="oc"

launch_registry=
load_image=

aiops_case=
aiops_case_versoin="1.3.0"

DOCKER_USERNAME=
DOCKER_PASSWORD=

ROOT_DIR=$(cd -P $(dirname $0) >/dev/null 2>&1 && pwd)
DEPLOY_LOCAL_WORKDIR=${ROOT_DIR}/.work
TOOLS_HOST_DIR=${ROOT_DIR}/.cache/tools/${HOST_PLATFORM}

airgap_cluster_pre() {

    echo "-------------Create ImageContentSourcePolicy-------------"

  cat << EOF | $kubernetesCLI apply -f -
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: ibm-cp-waiops
spec:
  repositoryDigestMirrors:
  - mirrors:
    - ${registry}/cp
    source: cp.icr.io/cp
  - mirrors:
    - ${registry}/ibmcom
    source: docker.io/ibmcom
  - mirrors:
    - ${registry}/cpopen
    source: icr.io/cpopen
  - mirrors:
    - ${registry}/opencloudio
    source: quay.io/opencloudio
  - mirrors:
    - ${registry}/openshift
    source: quay.io/openshift
EOF

    echo "-------------Patch insecureRegistries-------------"

    $kubernetesCLI patch image.config.openshift.io/cluster --type=merge \
    -p '{"spec":{"registrySources":{"insecureRegistries":["'${registry}'"]}}}' \
    || {
    echo "image.config.openshift.io/cluster patch failed."
    exit
    }    

    echo "-------------Configuring cluster pullsecret-------------"

    rm -rf ${ROOT_DIR}/.dockerconfigjson
    $kubernetesCLI extract secret/pull-secret -n openshift-config --to ${ROOT_DIR} --confirm

    DOCKER_AUTH=${user}:${pass}
    $kubernetesCLI registry login --registry ${registry} \
    --auth-basic=$DOCKER_AUTH \
    --to=${ROOT_DIR}/.dockerconfigjson

    $kubernetesCLI set data secret/pull-secret --from-file .dockerconfigjson=${ROOT_DIR}/.dockerconfigjson -n openshift-config

}

add_cluster() {

    echo "-------------Add Cluster to Argocd-------------"

    OCP_CLUSTER_NAME=$($kubernetesCLI config current-context)
    echo y | argocd cluster add ${OCP_CLUSTER_NAME} --name ocp-$(date +%s)

    echo "done"
}

launch_pipeline() {

    echo "-------------Launch Pipeline to mirror image-------------"

    $kubernetesCLI apply -f ${ROOT_DIR}/../tekton -R

    cat <<EOF | $kubernetesCLI apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: gitops-install-env-secret
type: Opaque
stringData:
  .env: |
    REGISTRY=${registry}
    REGISTRY_USERNAME=${user}                      
    REGISTRY_PASSWORD=${pass}
    CP_TOKEN=${cp_token}
    CASE_NAME=${aiops_case}
    CASE_VERSION=${aiops_case_versoin}
    GIT_REPO=${git_repo}
    GIT_USERNAME=${git_username}
    GIT_PASSWORD=${git_password}
    STORAGECLASS=${storage_class}
    STORAGECLASSBLOCK=${storage_class}
---
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: online-task
  generateName: online-task-
spec:
  serviceAccountName: tekton-pipeline
  pipelineRef:
    name: gitops-install-online-task
  timeouts:
    pipeline: 300m
  workspaces:
    - name: install-env
      secret:
        secretName: gitops-install-env-secret
EOF

    echo "done"

}

launch_boot_cluster() {

    echo "-------------Launch Boot Cluster-------------"

    ${ROOT_DIR}/install.sh up
    
    echo "done"

}

####################
# Main entrance
####################

if [[ -n ${DOCKER_USERNAME} && -n ${DOCKER_PASSWORD} ]]; then
  docker login docker.io -u ${DOCKER_USERNAME} -p ${DOCKER_PASSWORD} 2>/dev/null
fi

# Parse CLI parameters
while [ "${1-}" != "" ]; do
    case $1 in
    # Supported parameters for cloudctl & direct script invocation
    --launchRegistry | -l)
        launch_registry="true"
        ;;
    --registry | -r)
        shift
        registry="${1}"
        ;;
    --username | -u)
        shift
        user="${1}"
        ;;
    --password | -p)
        shift
        pass="${1}"
        ;;
    --cpToken | -t)
        shift
        cp_token="${1}"
        ;;
    --storageClass | -s)
        shift
        storage_class="${1}"
        ;;
    --addCluster)
        add_cluster="true"
        ;;
    --launchBootCluster)
        launch_boot_cluster="true"
        ;;
    --aiopsCase)
        shift
        aiops_case="${1}"
        ;;
    --aiopsCaseVersoin)
        shift
        aiops_case_versoin="${1}"
        ;;
    --gitRepo)
        shift
        git_repo="${1}"
        ;;
    --gitUsername)
        shift
        git_username="${1}"
        ;;
    --gitPassword)
        shift
        git_password="${1}"
        ;;
    --debug)
        set -x
        ;;
    *)
        echo "Invalid Option ${1}" >&2
        exit 1
        ;;
    esac
    shift
done

git_repo="https://gitlab.$(hostname):9043/root/cp4waiops-gitops.git"
git_username="root"
git_password=$($kubernetesCLI -n gitlab get secret gitlab-gitlab-initial-root-password -ojsonpath='{.data.password}' | base64 --decode ; echo)

if [[ $launch_registry == "true" ]]; then
    ${ROOT_DIR}/launch-registry.sh
    registry=$(hostname):5003
    user=admin
    pass=admin
fi

if [[ $launch_boot_cluster == "true" ]]; then
    launch_boot_cluster
fi

if [[ ! -z $aiops_case ]]; then
    launch_pipeline
fi

if [[ $add_cluster == "true" ]]; then
    airgap_cluster_pre
    add_cluster
fi
