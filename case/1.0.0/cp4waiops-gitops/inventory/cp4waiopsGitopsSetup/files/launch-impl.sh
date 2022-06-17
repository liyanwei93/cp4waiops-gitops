# (C) Copyright IBM Corp. 2020  All Rights Reserved.
#
# This script implements/overrides the base functions defined in launch.sh

# CPWAIOps operator specific variables
caseName="cp4waiops-gitops"
inventory="cp4waiopsGitopsSetup"
caseCatalogName=""
# List of CASE dependencies for recursive catalog source install and uninstall
case_depedencies=""
recursive_action=0

# returns name of the inventory containing setup code, given a CASE name
# this is used during the install of catalog of dependent CASE
# this list must be updated as additional items are added to case_dependencies
# the dependent CASE items must support `install-catalog` and `uninstall-catalog`
# the echo value must be the name of the CASE inventory for the catalog actions
dependent_inventory_item() {
    local case_name=$1
    case $case_name in
    ibm-cp-automation-foundation)
        echo "iafOperatorSetup"
        return 0
        ;;
    *)
        echo "unknown case: $case_name"
        return 1
        ;;
    esac
}

# returns a case tgz given a dependency name
dependent_case_tgz() {
    local case_name=$1
    local input_dir=$2

    # if there are multiple versions of the case is downloaded ( this happens when same dependency
    # is requested by a different case but with a different version)
    # use the latest version
    # the below command finds files that start with dependent case name, sorts by semver field
    # note that this sort flag is only available on GNU sort ( linux versions)
    case_tgz=$(find "${input_dir}" -name "${case_name}*.tgz" | sort --reverse --version-sort --field-separator="-" | head -n1)

    if [[ -z ${case_tgz} ]]; then
        err_exit "failed to find case tgz for dependent case: ${case_name}"
    fi

    echo "${case_tgz}"
}

# ----- INSTALL ACTIONS -----

# Installs the catalog source including dependent catalogs
install_dependent_catalogs() {

    local dep_case=""

    for dep in $case_depedencies; do
        local dep_case="$(dependent_case_tgz "${dep}" "${inputcasedir}")"

        echo "-------------Installing dependent catalog source: ${dep_case}-------------"

        validate_file_exists "${dep_case}"
        local inventory=""
        inventory=$(dependent_inventory_item "${dep}")

        cloudctl case launch \
            --case "${dep_case}" \
            --namespace "${namespace}" \
            --inventory "${inventory}" \
            --action install-catalog \
            --args "--registry ${registry} --inputDir ${inputcasedir} --recursive ${dryRun:+--dryRun }" \
            --tolerance "${tolerance_val}"

        if [[ $? -ne 0 ]]; then
            err_exit "installing dependent catalog for '${dep_case}' failed"
        fi
    done
}

# Installs the catalog source including dependent catalogs
install_catalog() {

    validate_install_catalog

    # install all catalogs of subcases first
    if [[ ${recursive_action} -eq 1 ]]; then
        install_dependent_catalogs
    fi

    echo "-------------Installing catalog source-------------"

    local catsrc_file="${casePath}/inventory/${inventory}/files/catalog_source.yaml"

    # Verfy expected yaml files for install exit
    validate_file_exists "${catsrc_file}"

    # Apply yaml files manipulate variable input as required
    if [[ -z $registry ]]; then
        # If an additional arg named registry is NOT passed in, then just apply
        tee >($kubernetesCLI apply ${dryRun} -f -) < "${catsrc_file}"
    else
        # If an additional arg named registry is passed in, then adjust the name of the image and apply
        local catsrc_image_orig=$(grep "image:" "${catsrc_file}" | awk '{print$2}')

        # replace original registry with local registry
        local catsrc_image_mod="${registry}/$(echo "${catsrc_image_orig}" | sed -e "s/[^/]*\///")"

        # apply catalog source
        sed -e "s|${catsrc_image_orig}|${catsrc_image_mod}|g" "${catsrc_file}" | tee >($kubernetesCLI apply ${dryRun} -f -) | cat
    fi

    echo "done"

}

# Installs the catalog source including dependent catalogs
install_gitops() {

    echo "-------------Installing Gitops-------------"

    local catsrc_file="${casePath}/inventory/${inventory}/files/subscription.yaml"

    # Verfy expected yaml files for install exit
    validate_file_exists "${catsrc_file}"

    # Apply yaml files manipulate variable input as required
    if [[ -z $registry ]]; then
        # If an additional arg named registry is NOT passed in, then just apply
        tee >($kubernetesCLI apply ${dryRun} -f -) < "${catsrc_file}"
    else
        # If an additional arg named registry is passed in, then adjust the name of the image and apply
        local catsrc_image_orig=$(grep "image:" "${catsrc_file}" | awk '{print$2}')

        # replace original registry with local registry
        local catsrc_image_mod="${registry}/$(echo "${catsrc_image_orig}" | sed -e "s/[^/]*\///")"

        # apply catalog source
        sed -e "s|${catsrc_image_orig}|${catsrc_image_mod}|g" "${catsrc_file}" | tee >($kubernetesCLI apply ${dryRun} -f -) | cat
    fi

    echo "done"

}

# ----- UNINSTALL ACTIONS -----

uninstall_dependent_catalogs() {

    local dep_case=""

    for dep in $case_depedencies; do
        local dep_case="$(dependent_case_tgz "${dep}" "${inputcasedir}")"
        echo "-------------Uninstalling dependent catalog source: ${dep_case}-------------"

        validate_file_exists "${dep_case}"
        local inventory=""
        inventory=$(dependent_inventory_item "${dep}")

        cloudctl case launch \
            --case "${dep_case}" \
            --namespace "${namespace}" \
            --inventory "${inventory}" \
            --action uninstall-catalog \
            --args "--recursive --inputDir ${inputcasedir} ${dryRun:+--dryRun }" \
            --tolerance "${tolerance_val}"

        if [[ $? -ne 0 ]]; then
            err_exit "Uninstalling dependent catalog source: ${dep_case} failed"
        fi

    done
}

# deletes the catalog source and operator group
uninstall_catalog() {

    validate_install_catalog "uninstall"

    # uninstall all catalogs of subcases first
    if [[ ${recursive_action} -eq 1 ]]; then
        uninstall_dependent_catalogs
    fi

    local catsrc_file="${casePath}/inventory/${inventory}/files/catalog_source.yaml"

    echo "-------------Uninstalling catalog source-------------"
    $kubernetesCLI delete -f "${catsrc_file}" --ignore-not-found=true ${dryRun}
}