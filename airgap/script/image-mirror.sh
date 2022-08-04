#!/bin/bash

function msg() {
  printf '%b\n' "$1"
}

function title() {
  msg "\33[34m# ${1}\33[0m"
}

function info() {
  msg "[INFO] ${1}"
}

function image_mirror() {

  title "Mirror images..." 

  cd $LOCAL_WORKDIR
  echo -n "Waiting for image files copy... "
  tar -xf v2.tgz

  local_auth=$(echo -n "${REGISTRY_USERNAME}:${REGISTRY_PASSWORD}" | base64 | tr -d "\n")

  cat << EOF > auth.json
{
    "auths": {
    "${REGISTRY}": {
        "auth": "${local_auth}"
    }
    }
}
EOF

  echo "
  oc image mirror \
  -f images-mapping-from-filesystem.txt \
  -a auth.json \
  --from-dir=$LOCAL_WORKDIR \
  --filter-by-os '.*' \
  --insecure \
  --skip-multiple-scopes \
  --max-per-registry=1
  "

  sed -i 's|LOCALREGISTRY|'"${REGISTRY}"'|g' $LOCAL_WORKDIR/images-mapping-from-filesystem.txt

  oc image mirror \
  -f images-mapping-from-filesystem.txt \
  -a auth.json \
  --from-dir=$LOCAL_WORKDIR \
  --filter-by-os '.*' \
  --insecure \
  --skip-multiple-scopes \
  --max-per-registry=1

  info "Mirror image ... Done"

}

ROOT_DIR=$(cd -P $(dirname $0) >/dev/null 2>&1 && pwd)
LOCAL_WORKDIR=""

case $1 in
  "case")
    LOCAL_WORKDIR=${ROOT_DIR}/.image/case
    ;;
  "bootcluster")
    LOCAL_WORKDIR=${ROOT_DIR}/.image/bootcluster
    ;;
esac

REGISTRY=$2
REGISTRY_USERNAME=$3
REGISTRY_PASSWORD=$4
image_mirror

