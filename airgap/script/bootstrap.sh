storage_class=
registry=
user=
pass=
kubernetesCLI="oc"

launch_registry=
load_image=
launch_application=

aiops_case=
aiops_case_versoin="1.3.0"

DOCKER_USERNAME=
DOCKER_PASSWORD=

ROOT_DIR=$(cd -P $(dirname $0) >/dev/null 2>&1 && pwd)
DEPLOY_LOCAL_WORKDIR=${ROOT_DIR}/.work
TOOLS_HOST_DIR=${ROOT_DIR}/.cache/tools/${HOST_PLATFORM}

install_gitops_applicationset() {

    echo "-------------Install Gitops ApplicationSet-------------"

    HOSTNAME=$(hostname)
    if [[ -z $storage_class ]]; then
        echo "Default storageclass is rook-cephfs"
        local storageclass=rook-cephfs
        local storageclassblock=rook-cephfs
    else
        echo "Storageclass is $storage_class"
        local storageclass=$storage_class
        local storageclassblock=$storage_class
    fi

    sed -i 's|HOSTNAME|'"${HOSTNAME}"'|g' ${ROOT_DIR}/application.yaml
    sed -i 's|STORAGECLASSBLOCK|'"${storageclassblock}"'|g' ${ROOT_DIR}/application.yaml
    sed -i 's|STORAGECLASS|'"${storageclass}"'|g' ${ROOT_DIR}/application.yaml
    sed -i 's|REGISTRY|'"${registry}"'|g' ${ROOT_DIR}/application.yaml
    sed -i 's|USERNAME|'"${user}"'|g' ${ROOT_DIR}/application.yaml
    sed -i 's|PASSWORD|'"${pass}"'|g' ${ROOT_DIR}/application.yaml
    $kubernetesCLI apply -f ${ROOT_DIR}/application.yaml

}

install_gitops_application() {

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

    echo "-------------Add Cluster to Argocd-------------"

    OCP_CLUSTER_NAME=$($kubernetesCLI config current-context)
    echo y | argocd cluster add ${OCP_CLUSTER_NAME} --name ocp-$(date +%s)

    echo "done"

}

launch_pipeline() {

    echo "-------------Launch Pipeline to mirror image-------------"

    $kubernetesCLI apply -f ${ROOT_DIR}/../tekton/task/mirror-image.yaml

    cat <<EOF | $kubernetesCLI apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: registry-install-env-secret
type: Opaque
stringData:
  .env: |
    REGISTRY=${registry}
    USERNAME=${user}                      
    PASSWORD=${pass}
    CP_TOKEN=${cp_token}
    CASE_NAME=${aiops_case}
    CASE_VERSION=${aiops_case_versoin}
---
apiVersion: tekton.dev/v1beta1
kind: TaskRun
metadata:
  name: mirror-image
  generateName: mirror-image-
spec:
  taskRef:
    kind: Task
    name: mirror-image
  timeout: 3h0m0s
  workspaces:
    - name: install-env
      secret:
        secretName: registry-install-env-secret
EOF

    echo "done"

}

launch_boot_cluster() {

    echo "-------------Launch Boot Cluster-------------"

    if [[ $launch_registry == "true" ]]; then
        ${ROOT_DIR}/launch-registry.sh
        registry=$(hostname):5003
        user=admin
        pass=admin
    fi

    if [[ $load_image == "true" ]]; then
        ${ROOT_DIR}/load-image.sh -r ${registry} -u ${user} -p ${pass}
    fi

    ${ROOT_DIR}/install.sh up

    if [[ $launch_application == "true" ]]; then
        install_gitops_applicationset
    fi
    
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
    --loadImage | -i)
        load_image="true"
        ;;
    --launchApplication | -a)
        launch_application="true"
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


if [[ $launch_boot_cluster == "true" ]]; then
    launch_boot_cluster
fi

if [[ ! -z $aiops_case ]]; then
    launch_pipeline
fi

if [[ $add_cluster == "true" ]]; then
    install_gitops_application
fi
