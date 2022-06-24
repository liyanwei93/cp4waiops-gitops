# (C) Copyright IBM Corp. 2020  All Rights Reserved.
#
# This script implements/overrides the base functions defined in launch.sh
# This implementation is specific to this panamax operator

# panamax operator specific variables
inventory="ibmCommonServiceOperatorSetup"
caseName="ibm-cp-common-services"
cr_system_status="betterThanYesterday"
caseCatalogName="ibm-common-services-catalog"
catalogNamespace="openshift-marketplace"
channelName="v3"
catalogTag="latest"

# ----- INSTALL ACTIONS -----

# Installs the catalog source and operator group
install_catalog() {

    validate_install_catalog

    # Verify expected yaml files for install exit
    [[ ! -f "${casePath}"/inventory/"${inventory}"/files/op-olm/catalog_source.yaml ]] && { err_exit "Missing required catalog source yaml, exiting deployment."; }
    [[ ! -f "${casePath}"/inventory/"${inventory}"/files/op-olm/operator_group.yaml ]] && { err_exit "Missing required operator group yaml, exiting deployment."; }

    echo "-------------Create catalog source-------------"

    local catsrc_file="${casePath}/inventory/${inventory}/files/op-olm/catalog_source.yaml"

    # Verfy expected yaml files for install exit
    validate_file_exists "${catsrc_file}"

    # Apply yaml files manipulate variable input as required

    local catsrc_image_orig=$(grep "image:" "${catsrc_file}" | awk '{print$2}')

    # replace original registry with local registry
    local catsrc_image_mod="${registry}/$(echo "${catsrc_image_orig}" | sed -e "s/[^/]*\///")"
    if echo "${registry}" | grep -qE "quay.io|docker.io"; then
        catsrc_image_mod="${catsrc_image_orig}"
    fi

    # apply catalog source
    sed -e "s|${catsrc_image_orig}|${catsrc_image_mod}|g" "${catsrc_file}" | tee >($kubernetesCLI apply ${dryRun} -f -) | cat

    echo "check for any existing operator group in ${namespace} ..."
    if [[ $($kubernetesCLI get og -n "${namespace}" -o=go-template --template='{{len .items}}' ) -gt 0 ]]; then
        echo "found operator group"
        $kubernetesCLI get og -n "${namespace}" -o yaml
        return
    fi

    echo "no existing operator group found"

    if [[ "$namespace" != "openshift-operators" ]]; then
        echo "-------------Create operator group-------------"
        sed -e "s|REPLACE_NAMESPACE|${namespace}|g" "${casePath}"/inventory/"${inventory}"/files/op-olm/operator_group.yaml | $kubernetesCLI apply -n "${namespace}" -f -
    fi
}


# Install utilizing default OLM method
install_operator() {
#    echo "-------------skip-------------"
    wait=30

    # Proceed with install
    echo "-------------Installing common services via OLM-------------"
    # Verify expected yaml files for install exit
    [[ ! -f "${casePath}"/inventory/"${inventory}"/files/op-olm/subscription.yaml ]] && { err_exit "Missing required subscription yaml, exiting deployment."; }
    [[ ! -f "${casePath}"/inventory/"${inventory}"/files/op-olm/operand_request.yaml ]] && { err_exit "Missing required operand_request yaml, exiting deployment."; }

    echo "-------------Create common services operator subscription-------------"
    sed -e "s|REPLACE_NAMESPACE|${namespace}|g" "${casePath}"/inventory/"${inventory}"/files/op-olm/subscription.yaml | $kubernetesCLI apply -n "${namespace}" -f -

    # - check if common services operator subscription created
    while true; do
      $kubernetesCLI -n ${namespace} get sub ibm-common-service-operator &>/dev/null && break
      sleep $wait
    done

    # - check if operand registry cr created
    while true; do
      $kubernetesCLI get opreg -A &>/dev/null && break
      echo "wait for operand registry cr created ... "
      sleep $wait
    done

    if [[ -n ${size} ]]; then
        if [[ "${size}" == "starterset" ]] || [[ "${size}" == "small" ]] || [[ "${size}" == "medium" ]] || [[ "${size}" == "large" ]] || [[ "${size}" == "starter" ]] || [[ "${size}" == "production" ]]; then
            echo "-------------Create common service custom resource-------------"
            sed -e "s|starterset|${size}|g" "${casePath}"/inventory/"${inventory}"/files/op-olm/common_service.yaml | $kubernetesCLI apply -n ${namespace} -f -
            echo "wait for operand config is ready ... "
            sleep $wait
        else
            err_exit "Size ${size} is Invalid. You need set it from starterset/starter, small, medium, large/production"
        fi
    fi

    echo "-------------Create operand request-------------"
    ARCH=$(uname -m)
    if [[ "${ARCH}" == "s390x" ]]; then
        sed -e "/ibm-zen-operator/d" "${casePath}"/inventory/"${inventory}"/files/op-olm/operand_request.yaml | $kubernetesCLI -n ${namespace} apply -f -
    else
        $kubernetesCLI apply -n ${namespace} -f "${casePath}"/inventory/"${inventory}"/files/op-olm/operand_request.yaml
    fi

    echo "-------------Install complete-------------"
}

# Install utilizing default CLI method
install_operator_native() {
    echo "Please use OLM install/uninstall"
}

# install operand custom resources
apply_custom_resources() {
    echo "-------------No custom resources need to apply-------------"
}

# ----- UNINSTALL ACTIONS -----

function delete_sub_csv() {
  subs=$1
  ns=$2
  for sub in ${subs}; do
    csv=$(oc get sub ${sub} -n ${ns} -o=jsonpath='{.status.installedCSV}' --ignore-not-found)
    [[ "X${csv}" != "X" ]] && oc delete csv ${csv}  -n ${ns} --ignore-not-found
    oc delete sub ${sub} -n ${ns} --ignore-not-found
  done
}

# Get remaining resource with kinds
function get_remaining_resources() {
  local remaining=$1
  local ns="--all-namespaces"
  local new_remaining=
  [[ "X$2" != "X" ]] && ns="-n $2"
  for kind in ${remaining}; do
    if [[ "X$($kubernetesCLI get ${kind} --all-namespaces)" != "X" ]]; then
      new_remaining="${new_remaining} ${kind}"
    fi
  done
  echo $new_remaining
}

function wait_for_deleted() {
  local remaining=${1}
  retries=${2:-10}
  interval=${3:-30}
  index=0
  while true; do
    remaining=$(get_remaining_resources "$remaining")
    if [[ "X$remaining" != "X" ]]; then
      if [[ ${index} -eq ${retries} ]]; then
        echo "Timeout delete resources: $remaining"
        return 1
      fi
      sleep $interval
      ((index++))
      echo "DELETE - Waiting: resource ${remaining} delete complete [$(($retries - $index)) retries left]"
    else
      break
    fi
  done
}

function delete_operator() {
  local subs=$1
  local namespace=$2
  for sub in ${subs}; do
    csv=$($kubernetesCLI get sub ${sub} -n ${namespace} -o=jsonpath='{.status.installedCSV}' --ignore-not-found)
    if [[ "X${csv}" != "X" ]]; then
      echo "Delete operator ${sub} from namespace ${namespace}"
      $kubernetesCLI delete csv ${csv} -n ${namespace} --ignore-not-found
      $kubernetesCLI delete sub ${sub} -n ${namespace} --ignore-not-found
    fi
  done
}

function delete_operand() {
  local crds=$1
  for crd in ${crds}; do
    if $kubernetesCLI api-resources | grep $crd &>/dev/null; then
      for ns in $($kubernetesCLI get $crd --no-headers --all-namespaces --ignore-not-found | awk '{print $1}' | sort -n | uniq); do
        crs=$($kubernetesCLI get ${crd} --no-headers --ignore-not-found -n ${ns} 2>/dev/null | awk '{print $1}')
        if [[ "X${crs}" != "X" ]]; then
          echo "Deleting ${crd} from namespace ${ns}"
          $kubernetesCLI delete ${crd} --all -n ${ns} --ignore-not-found &
        fi
      done
    fi
  done
}

function delete_operand_finalizer() {
  local crds=$1
  local ns=$2
  for crd in ${crds}; do
    crs=$($kubernetesCLI get ${crd} --no-headers --ignore-not-found -n ${ns} 2>/dev/null | awk '{print $1}')
    for cr in ${crs}; do
      echo "Removing the finalizers for resource: ${crd}/${cr}"
      $kubernetesCLI patch ${crd} ${cr} -n ${ns} --type="json" -p '[{"op": "remove", "path":"/metadata/finalizers"}]' 2>/dev/null
    done
  done
}

# deletes the catalog source and operator group
uninstall_catalog() {

    validate_install_catalog "uninstall"

    echo "-------------Deleting catalog source-------------"
    $kubernetesCLI delete CatalogSource opencloud-operators -n openshift-marketplace --ignore-not-found=true

    echo "-------------Deleting operatorGroup-------------"
    $kubernetesCLI delete OperatorGroup common-service -n "${namespace}" --ignore-not-found=true

}

# Uninstall operator installed via OLM
uninstall_operator() {
    echo "-------------Uninstalling common services-------------"

    echo "-------------Deleting common services operand from all namespaces-------------"
    delete_operand "OperandRequest" && wait_for_deleted "OperandRequest" 30 40
    delete_operand "CommonService OperandRegistry OperandConfig"
    delete_operand "NamespaceScope" && wait_for_deleted "NamespaceScope"

    echo "-------------Deleting common service operator-------------"
    for sub in $($kubernetesCLI get sub --all-namespaces --ignore-not-found | awk '{if ($3 =="ibm-common-service-operator") print $1"/"$2}'); do
        namespace=$(echo $sub | awk -F'/' '{print $1}')
        name=$(echo $sub | awk -F'/' '{print $2}')
        delete_operator "$name" "$namespace"
    done

    echo "-------------Deleting ODLM-------------"
    for sub in $($kubernetesCLI get sub --all-namespaces --ignore-not-found | awk '{if ($3 =="ibm-odlm") print $1"/"$2}'); do
        namespace=$(echo $sub | awk -F'/' '{print $1}')
        name=$(echo $sub | awk -F'/' '{print $2}')
        delete_operator "$name" "$namespace"
        cs_ns="$namespace"
    done
    cs_ns=${cs_ns:-ibm-common-services}

    echo "-------------Deleting RBAC resource-------------"
    $kubernetesCLI delete ClusterRole ibm-common-service-webhook --ignore-not-found
    $kubernetesCLI delete ClusterRoleBinding ibm-common-service-webhook --ignore-not-found
    $kubernetesCLI delete RoleBinding ibmcloud-cluster-info -n kube-public --ignore-not-found
    $kubernetesCLI delete Role ibmcloud-cluster-info -n kube-public --ignore-not-found

    $kubernetesCLI delete RoleBinding ibmcloud-cluster-ca-cert -n kube-public --ignore-not-found
    $kubernetesCLI delete Role ibmcloud-cluster-ca-cert -n kube-public --ignore-not-found

    $kubernetesCLI delete ClusterRole nginx-ingress-clusterrole --ignore-not-found
    cluster_role_binding=$(oc get ClusterRoleBinding | grep nginx-ingress-clusterrole | awk '{print $1}')
    if [[ ! -z $cluster_role_binding ]]
    then
      $kubernetesCLI delete ClusterRoleBinding $cluster_role_binding --ignore-not-found
    fi
    $kubernetesCLI delete scc nginx-ingress-scc --ignore-not-found

    subs=$(oc get sub --no-headers -n ${cs_ns} 2>/dev/null | awk '{print $1}')
    delete_sub_csv "${subs}" "${cs_ns}"

    echo "-------------Deleting webhook-------------"
    $kubernetesCLI delete ValidatingWebhookConfiguration cert-manager-webhook ibm-cs-ns-mapping-webhook-configuration --ignore-not-found
    $kubernetesCLI delete MutatingWebhookConfiguration cert-manager-webhook ibm-common-service-webhook-configuration namespace-admission-config ibm-operandrequest-webhook-configuration --ignore-not-found
  
    echo "-------------Deleting configmap-------------"
    $kubernetesCLI -n kube-public delete cm ibm-common-services-status --ignore-not-found

    echo "-------------Deleting API-------------"
    $kubernetesCLI delete apiservice v1.metering.ibm.com --ignore-not-found
    $kubernetesCLI delete apiservice v1beta1.webhook.certmanager.k8s.io --ignore-not-found

    echo "-------------Deleting catalog source-------------"
    $kubernetesCLI delete CatalogSource opencloud-operators -n openshift-marketplace --ignore-not-found

    echo "-------------Deleting namespace-------------"
    $kubernetesCLI delete namespace ${cs_ns} --ignore-not-found &
    if wait_for_namespace_deleted ${cs_ns}; then
      echo "-------------Uninstall successful-------------"
    fi

    echo "-------------Force delete remaining resources-------------"
    delete_unavailable_apiservice
    force_delete "${cs_ns}"
    if [[ ($? -ne 0)]]; then
      err_exit "Failed to forced uninstall the common services, please re-try the uninstallation again."
    fi
    echo "-------------Uninstall successful-------------"
}

function wait_for_namespace_deleted() {
  local namespace=$1
  retries=30
  interval=5
  index=0
  while true; do
    if $kubernetesCLI get namespace ${namespace} &>/dev/null; then
      if [[ ${index} -eq ${retries} ]]; then
        echo "Timeout delete namespace: $namespace"
        return 1
      fi
      sleep $interval
      ((index++))
      echo "DELETE - Waiting: namespace ${namespace} delete complete [$(($retries - $index)) retries left]"
    else
      break
    fi
  done
  return 0
}

function delete_unavailable_apiservice() {
  rc=0
  apis=$($kubernetesCLI get apiservice | grep False | awk '{print $1}')
  if [ "X${apis}" != "X" ]; then
    echo "Found some unavailable apiservices, deleting ..."
    for api in ${apis}; do
      echo "$kubernetesCLI delete apiservice ${api}"
      $kubernetesCLI delete apiservice ${api}
      if [[ "$?" != "0" ]]; then
        echo "Delete apiservcie ${api} failed"
        rc=$((rc + 1))
        continue
      fi
    done
  fi
  return $rc
}

# Sometime delete namespace stuck due to some reousces remaining, use this method to get these
# remaining resources to force delete them.
function get_remaining_resources_from_namespace() {
  local namespace=$1
  local remaining=
  if $kubernetesCLI get namespace ${namespace} &>/dev/null; then
    message=$($kubernetesCLI get namespace ${namespace} -o=jsonpath='{.status.conditions[?(@.type=="NamespaceContentRemaining")].message}' | awk -F': ' '{print $2}')
    [[ "X$message" == "X" ]] && return 0
    remaining=$(echo $message | awk '{len=split($0, a, ", ");for(i=1;i<=len;i++)print a[i]" "}' | while read res; do
      [[ "$res" =~ "pod" ]] && continue
      echo ${res} | awk '{print $1}'
    done)
  fi
  echo $remaining
}

function force_delete() {
  local namespace=$1
  local remaining=$(get_remaining_resources_from_namespace "$namespace")
  if [[ "X$remaining" != "X" ]]; then
    echo "Some resources are remaining: $remaining"
    echo "Deleting finalizer for these resources ..."
    delete_operand_finalizer "${remaining}" "$namespace"
    wait_for_deleted "${remaining}" 5 10
  fi
}

# parse additional dynamic args
parse_custom_dynamic_args() {
    key=$1
    val=$2
    case $key in
    --size)
        size=$val
        ;;
    esac
}
