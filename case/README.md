### Launch boot cluster

```
oc ibm-pak get ibm-cp-waiops --skip-verify=true
```

```
oc ibm-pak launch --case  /root/.ibm-pak/data/cases/ibm-cp-waiops/1.3.0/ibm-cp-waiops-1.3.0.tgz --action launch-boot-cluster --inventory cpwaiopsSetup --args "--storage ceph --registry dormer1.fyre.ibm.com:5003 --user admin --pass admin"
```

### mirror image

#### docker login
```
docker login cp.icr.io
docker login dormer1.fyre.ibm.com:5003 -u admin -p admin
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
