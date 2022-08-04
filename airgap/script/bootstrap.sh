storage_class="rook-cephfs"
kubernetesCLI="kubectl"

launch_registry=

aiops_case="ibm-cp-waiops"
aiops_case_versoin="1.3.1"

DOCKER_USERNAME=
DOCKER_PASSWORD=

ROOT_DIR=$(cd -P $(dirname $0) >/dev/null 2>&1 && pwd)
DEPLOY_LOCAL_WORKDIR=${ROOT_DIR}/.work
TOOLS_HOST_DIR=${ROOT_DIR}/.cache/tools/${HOST_PLATFORM}

function wait-task {
  local object=$1
  local ns=$2
  echo -n "Waiting for image mirror $object done "
  retries=600
  until [[ $retries == 0 ]]; do
    echo -n "."
    local result=$($kubernetesCLI get pod $object -n $ns -o=jsonpath='{.status.phase}' 2>/dev/null)
    if [[ $result == "Succeeded" ]]; then
      echo " Done"
      break
    fi
    sleep 10
    retries=$((retries - 1))
  done
  [[ $retries == 0 ]] && echo
}

function wait-pod-running {
  local object=$1
  local ns=$2
  retries=200
  until [[ $retries == 0 ]]; do
    echo -n "."
    local result=$($kubernetesCLI get pod $object -n $ns -o=jsonpath='{.status.phase}' 2>/dev/null)
    if [[ $result == "Running" ]]; then
      echo " Done"
      break
    fi
    sleep 1
    retries=$((retries - 1))
  done
  [[ $retries == 0 ]] && echo
}

#######################
# Aiops Install Prepare
#######################

airgap_cluster_pre() {

    kubernetesCLI="oc"
    boot_cluster_env
    
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
    --skip-check \
    --to=${ROOT_DIR}/.dockerconfigjson

    $kubernetesCLI set data secret/pull-secret --from-file .dockerconfigjson=${ROOT_DIR}/.dockerconfigjson -n openshift-config

}

add_cluster() {

    echo "-------------Add Cluster to Argocd-------------"

    if [[ ! -z $argocd_url ]]; then
      echo y | argocd login ${argocd_url} --username ${argocd_username} --password ${argocd_password}
    fi

    OCP_CLUSTER_NAME=$($kubernetesCLI config current-context)
    echo y | argocd cluster add ${OCP_CLUSTER_NAME} --name ocp-$(date +%s)

    echo "done"
}

#######################
# Launch Pipeline
#######################

launch_pipeline() {

    echo "-------------Launch Tekton Pipeline-------------"

    cat <<EOF | $kubernetesCLI apply -f -
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-workspace
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
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
    ARGOCD_URL=${argocd_url}
    ARGOCD_USERNAME=${argocd_username}
    ARGOCD_PASSWORD=${argocd_password}
    STORAGECLASS=${storage_class}
    STORAGECLASSBLOCK=${storage_class}
EOF

    $kubernetesCLI apply -f ${ROOT_DIR}/../tekton -R
    
    echo "done"

}

bootcluster_online_pipeline() {

    echo "-------------Launch Bootcluster Online Pipeline-------------"

    $kubernetesCLI delete pipelinerun bc-online

    cat <<EOF | $kubernetesCLI apply -f -
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: bc-online
  generateName: bc-online-
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

bootcluster_airgap_pipeline() {

    echo "-------------Bootcluster Image Mirror-------------"

    $kubernetesCLI delete pipelinerun bc-airgap

    cat <<EOF | $kubernetesCLI apply -f -
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: bc-airgap
  generateName: bc-airgap-
spec:
  serviceAccountName: tekton-pipeline
  pipelineRef:
    name: bootcluster-mirror-image-filesystem
  timeouts:
    pipeline: 300m
  workspaces:
    - name: install-workspace
      persistentVolumeClaim:
        claimName: my-workspace
EOF

    echo "done"

}

aiops_online_pipeline() {

    echo "-------------Case ${aiops_case} ${aiops_case_versoin} Image Mirror - Bastion-------------"

    $kubernetesCLI delete pipelinerun ai-online

    cat <<EOF | $kubernetesCLI apply -f -
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: ai-online
  generateName: ai-online-
spec:
  serviceAccountName: tekton-pipeline
  pipelineRef:
    name: aiops-mirror-image
  timeouts:
    pipeline: 300m
  workspaces:
    - name: install-env
      secret:
        secretName: gitops-install-env-secret
EOF

    echo "done"

}

aiops_airgap_pipeline() {

    echo "-------------Case ${aiops_case} ${aiops_case_versoin} Image Mirror - filesystem-------------"

    $kubernetesCLI delete pipelinerun ai-airgap

    cat <<EOF | $kubernetesCLI apply -f -
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: ai-airgap
  generateName: ai-airgap-
spec:
  serviceAccountName: tekton-pipeline
  pipelineRef:
    name: aiops-mirror-image-filesystem
  timeouts:
    pipeline: 300m
  workspaces:
    - name: install-env
      secret:
        secretName: gitops-install-env-secret
    - name: install-workspace
      persistentVolumeClaim:
        claimName: my-workspace
EOF

    echo "done"

}

####################
# Aiops Install
####################

image_mirror_bastion() {

  launch_pipeline
  aiops_online_pipeline

}

image_mirror_filesystem() {

    echo "-------------Prepare Airgap Launch Boot Cluster-------------"

    launch_pipeline
    aiops_airgap_pipeline
    wait-task ai-airgap-aiops-mirror-image-filesystem-pod default
    wait-pod-running ai-airgap-aiops-wait-image-copy-pod default
    mkdir -p ${ROOT_DIR}/.image/case
    $kubernetesCLI cp ai-airgap-aiops-wait-image-copy-pod:/workspace/install-image ${ROOT_DIR}/.image/case

    echo "done"

}

airgap_launch_case() {

    echo "-------------Prepare Airgap Launch Boot Cluster-------------"

    boot_cluster_env
    ${ROOT_DIR}/image-mirror.sh "case" ${registry} ${user} ${pass}
    sed -i 's|REGISTRY|'"${registry}"'|g' ${ROOT_DIR}/application.yaml
    sed -i 's|USERNAME|'"${user}"'|g' ${ROOT_DIR}/application.yaml
    sed -i 's|PASSWORD|'"${pass}"'|g' ${ROOT_DIR}/application.yaml
    sed -i 's|GIT_REPO|'"${git_repo}"'|g' ${ROOT_DIR}/application.yaml
    sed -i 's|STORAGECLASS|'"${storage_class}"'|g' ${ROOT_DIR}/application.yaml
    $kubernetesCLI apply -f ${ROOT_DIR}/application.yaml

    echo "done"

}

####################
# Launch Boot Cluster
####################

launch_boot_cluster() {

    echo "-------------Launch Boot Cluster-------------"

    ${ROOT_DIR}/install.sh up
    boot_cluster_env
    echo y | argocd login ${argocd_url} --username ${argocd_username} --password ${argocd_password}
    launch_pipeline
    bootcluster_online_pipeline
    echo "done"

}

pre_launch_boot_cluster() {

    echo "-------------Prepare Airgap Launch Boot Cluster-------------"

    ${ROOT_DIR}/install.sh pre-airgap
    launch_pipeline
    bootcluster_airgap_pipeline
    
    wait-task bc-airgap-bootcluster-mirror-image-filesystem-pod default
    wait-pod-running bc-airgap-bootcluster-wait-image-copy-pod default  
    mkdir -p ${ROOT_DIR}/.image/bootcluster
    $kubernetesCLI cp bc-airgap-bootcluster-wait-image-copy-pod:/workspace/install-image ${ROOT_DIR}/.image/bootcluster

    echo "done"

    docker save -o ${ROOT_DIR}/.image/bootcluster/registry-image.tar docker.io/library/registry:2

}

airgap_launch_boot_cluster() {

    echo "-------------Airgap Launch Boot Cluster-------------"

    ${ROOT_DIR}/image-mirror.sh "bootcluster" ${registry} ${user} ${pass}
    grep -rl 'LOCALREGISTRY' ${ROOT_DIR}/../boot-cluster/ | xargs sed -i 's|LOCALREGISTRY|'"${registry}"'|g'
    sed -i 's|LOCALREGISTRY|'"${registry}"'|g' ${ROOT_DIR}/portable-storage-device-install.sh
    ${ROOT_DIR}/portable-storage-device-install.sh up

    echo "done"

}

boot_cluster_env() {

    if [[ -z $git_repo ]]; then
      git_repo="https://gitlab.$(hostname):9043/root/cp4waiops-gitops.git"
      git_username="root"
      git_password=$($kubernetesCLI -n gitlab get secret gitlab-gitlab-initial-root-password -ojsonpath='{.data.password}' | base64 --decode ; echo)
    fi

    if [[ -z $argocd_url ]]; then
      argocd_url=$(hostname):9443
      argocd_username="admin"
      argocd_password="$($kubernetesCLI -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
    fi
    
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
    --launchBootCluster)
        launch_boot_cluster="true"
        ;;
    --preLaunchBootCluster)
        prepare_launch_boot_cluster="true"
        ;;
    --airgapLaunchBootCluster)
        airgap_launch_boot_cluster="true"
        ;;
    --caseImageMirrorBastion)
        case_image_mirror_bastion="true"
        ;;
    --caseImageMirrorFilesystem)
        case_image_mirror_filesystem="true"
        ;;
    --caseAirgapLaunch)
        airgap_launch_case="true"
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
    --caseName)
        shift
        aiops_case="${1}"
        ;;
    --caseVersoin)
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
    --argocdUrl)
        shift
        argocd_url="${1}"
        ;;
    --argocdUsername)
        shift
        argocd_username="${1}"
        ;;
    --argocdPassword)
        shift
        argocd_password="${1}"
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

if [[ $launch_registry == "true" ]]; then
  if [[ $airgap_launch_boot_cluster == "true" ]]; then
    docker load -i ${ROOT_DIR}/.image/bootcluster/registry-image.tar
  fi
  ${ROOT_DIR}/launch-registry.sh
fi 

if [[ -z $registry ]]; then
  registry=$(hostname):5003
  user=admin
  pass=admin
fi

if [[ $launch_boot_cluster == "true" ]]; then
    launch_boot_cluster
fi

if [[ $prepare_launch_boot_cluster == "true" ]]; then
    pre_launch_boot_cluster
fi

if [[ $airgap_launch_boot_cluster == "true" ]]; then
    airgap_launch_boot_cluster
fi

if [[ $case_image_mirror_bastion == "true" ]]; then
    image_mirror_bastion
fi

if [[ $case_image_mirror_filesystem == "true" ]]; then
    image_mirror_filesystem
fi

if [[ $airgap_launch_case == "true" ]]; then
    airgap_launch_case
fi

if [[ $add_cluster == "true" ]]; then
    airgap_cluster_pre
    add_cluster
fi
