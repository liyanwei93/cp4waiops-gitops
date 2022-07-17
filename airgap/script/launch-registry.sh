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

function launch_registry() {
   if [[ -z ${REGISTRY} ]]; then
      local is_running="$(docker inspect -f '{{.State.Running}}' "mirror-registry" 2>/dev/null || true)"
      if [ "${is_running}" != 'true' ]; then
         info "Launch local container registry ..."
         msg "-----------------------------------------------------------------------"
         mkdir -p ~/.ibm-pak/data/registry/{auth,certs,data}
         local REGISTRY_DIR=~/.ibm-pak/data/registry
         cd ${REGISTRY_DIR}/certs
         HOSTNAME=$(hostname)
         REGISTRY_TLS_CA_SUBJECT="/C=US/ST=New York/L=Armonk/O=IBM Cloud Pak/CN=IBM Cloud Pak Root CA"
         REGISTRY_TLS_CERT_SUBJECT="/C=US/ST=New York/L=Armonk/O=IBM Cloud Pak"
         REGISTRY_TLS_CERT_SUBJECT_ALT_NAME="subjectAltName=IP:127.0.0.1,DNS:localhost,DNS:${HOSTNAME}"

         openssl genrsa -out "${REGISTRY_DIR}/certs/ca.key" 4096
         openssl req -new -x509 -days 365 -sha256 -subj "${REGISTRY_TLS_CA_SUBJECT}" -key "${REGISTRY_DIR}/certs/ca.key" -out "${REGISTRY_DIR}/certs/ca.crt"
         openssl req -newkey rsa:4096 -nodes -subj "${REGISTRY_TLS_CERT_SUBJECT}" -keyout "${REGISTRY_DIR}/certs/server.key" -out "${REGISTRY_DIR}/certs/server.csr"
         openssl x509 -req -days 365 -sha256 -extfile <(printf "${REGISTRY_TLS_CERT_SUBJECT_ALT_NAME}") \
            -CAcreateserial -CA "${REGISTRY_DIR}/certs/ca.crt" -CAkey "${REGISTRY_DIR}/certs/ca.key" \
            -in "${REGISTRY_DIR}/certs/server.csr"   -out "${REGISTRY_DIR}/certs/server.crt"

         mkdir -p /etc/docker/certs.d/${HOSTNAME}:5003
         cp server.crt /etc/docker/certs.d/${HOSTNAME}:5003/

         docker run --name mirror-registry -p 5003:5000 \
         -v ${REGISTRY_DIR}/data:/var/lib/registry:z \
         -v ${REGISTRY_DIR}/auth:/auth:z \
         -v ${REGISTRY_DIR}/certs:/certs:z \
         -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/server.crt \
         -e REGISTRY_HTTP_TLS_KEY=/certs/server.key \
         -d docker.io/library/registry:2

         cd -  
         info "Launch local container registry ${HOSTNAME}:5003..."
         info "Copy image data in ~/.ibm-pak/data/registry/data"
      fi
   fi
}

launch_registry
