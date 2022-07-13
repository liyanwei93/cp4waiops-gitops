### Launch boot cluster

```
oc ibm-pak get ibm-cp-waiops --skip-verify=true
```

```
oc ibm-pak launch --case  /root/.ibm-pak/data/cases/ibm-cp-waiops/1.3.0/ibm-cp-waiops-1.3.0.tgz --action launch-boot-cluster --inventory cpwaiopsSetup --args "--storage ceph --registry dormer1.fyre.ibm.com:5003 --user admin --pass admin"
```

### mirror image

#### start a local docker registry

```
mkdir -p /opt/registry/{auth,certs,data}
cd /opt/registry/certs
openssl req -newkey rsa:4096 -nodes -sha256 -keyout domain.key -x509 -days 365 -out domain.crt
docker run --name mirror-registry -p 5003:5000 \
     -v /opt/registry/data:/var/lib/registry:z \
     -v /opt/registry/auth:/auth:z \
     -v /opt/registry/certs:/certs:z \
     -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
     -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
     -e REGISTRY_COMPATIBILITY_SCHEMA1_ENABLED=true \
     -d docker.io/library/registry:2
```

#### docker login
```
docker login cp.icr.io
docker login dormer1.fyre.ibm.com:5003
```

#### image mirror

```
oc ibm-pak generate mirror-manifests ibm-cp-waiops dormer1.fyre.ibm.com:5003
oc image mirror -f ~/.ibm-pak/data/mirror/ibm-cp-waiops/1.3.0/images-mapping.txt --filter-by-os=.* --insecure --skip-multiple-scopes --max-per-registry=1
```

```
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: ibm-cp-waiops
spec:
  repositoryDigestMirrors:
  - mirrors:
    - dormer1.fyre.ibm.com:5003/cp
    source: cp.icr.io/cp
  - mirrors:
    - dormer1.fyre.ibm.com:5003/ibmcom
    source: docker.io/ibmcom
  - mirrors:
    - dormer1.fyre.ibm.com:5003/cpopen
    source: icr.io/cpopen
  - mirrors:
    - dormer1.fyre.ibm.com:5003/opencloudio
    source: quay.io/opencloudio
  - mirrors:
    - dormer1.fyre.ibm.com:5003/openshift
    source: quay.io/openshift
```

### Add cluster to argocd
```
oc login

oc ibm-pak launch --case  /root/.ibm-pak/data/cases/ibm-cp-waiops/1.3.0/ibm-cp-waiops-1.3.0.tgz --action install-gitops-application --inventory cpwaiopsSetup --namespace openshift-gitops
```
