#!/bin/bash

REGISTRY=
USERNAME=
PASSWORD=

function msg() {
  printf '%b\n' "$1"
}

function title() {
  msg "\33[34m# ${1}\33[0m"
}

function info() {
  msg "[INFO] ${1}"
}

function main() {
  start=$(date +%s)
  info "Push images to local container registry ..."
  msg "-----------------------------------------------------------------------"

  local num=0
  for image in ${imagelist[@]}; do

    num=$((num + 1 ))

    docker pull ${image}

    src_image="${image}"
    dest_image="${REGISTRY}/${src_image#*/}"

    title "[${num}] ${src_image} ➞ ${dest_image}"
    msg "-----------------------------------------------------------------------"

    docker tag ${image} ${dest_image}
    docker push ${dest_image}

  done

  msg "-----------------------------------------------------------------------"
  info "Pushed ${num} images to local container registry in $((($(date +%s)-${start})/60)) minutes."
}

function parse_arguments() {

   if [[ "$#" == 0 ]]; then
      exit 1
   fi

   while [[ "$1" != "" ]]; do
      case "$1" in
      -u | --username) 
         shift
         USERNAME=$1
         ;;
      -p | --password)
         shift
         PASSWORD=$1
         ;;
      -r | --registry)
         shift
         REGISTRY=$1
         ;;
      *) 
         exit 1
         ;;
      esac
      shift
   done

}

parse_arguments "$@"
imagelist=(
quay.io/openshift/origin-cli:latest
docker.io/kindest/node:v1.21.2
quay.io/jetstack/cert-manager-controller:v1.5.4
)
main
