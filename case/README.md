### Download oc plugin tools

oc: https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/
oc plugin: https://github.ibm.com/CloudPakOpenContent/cloud-pak-airgap-plugin/releases

### Add self case repo

```
oc ibm-pak config repo "CP4WAIOps Gitops" --url https://github.com/liyanwei93/cp4waiops-gitops/raw/airgap/case
```

### Launch boot cluster

#### Download case bundle

```
oc ibm-pak get ibm-cp-waiops --skip-verify=true
```

#### Launch boot cluster

1. Launch a pure boot cluster, include kind cluster, argocd, tekton, kube dashboard, helm, gitlab

```
oc ibm-pak launch --case  /root/.ibm-pak/data/cases/ibm-cp-waiops/1.3.0/ibm-cp-waiops-1.3.0.tgz --action launch-boot-cluster --inventory cpwaiopsSetup
```

2. Launch a boot cluster and deploy argocd applicationset to install aiops.

```
oc ibm-pak launch --case  /root/.ibm-pak/data/cases/ibm-cp-waiops/1.3.0/ibm-cp-waiops-1.3.0.tgz --action launch-boot-cluster --inventory cpwaiopsSetup --args "--launchApplication --loadImage --registry ${LOCAL_REGISTRY} --user ${USERNAME} --pass {PASSWORD} --storage ${STORAGE_CALSS}"
```

3. Launch a boot cluster, launch a local docker registry, and deploy argocd applicationset to install aiops.

```
oc ibm-pak launch --case  /root/.ibm-pak/data/cases/ibm-cp-waiops/1.3.0/ibm-cp-waiops-1.3.0.tgz --action launch-boot-cluster --inventory cpwaiopsSetup --args "--launchRegistry --launchApplication --loadImage --storage ${STORAGE_CALSS}"
```

### mirror image

#### docker login

```
docker login cp.icr.io
docker login ${LOCAL_REGISTRY} -u ${USERNAME} -p {PASSWORD}
```

#### image mirror

```
oc ibm-pak generate mirror-manifests ibm-cp-waiops ${LOCAL_REGISTRY}
oc image mirror -f ~/.ibm-pak/data/mirror/ibm-cp-waiops/1.3.0/images-mapping.txt --filter-by-os=.* --insecure --skip-multiple-scopes --max-per-registry=1
```

### Add cluster to argocd

```
oc login

oc ibm-pak launch --case  /root/.ibm-pak/data/cases/ibm-cp-waiops/1.3.0/ibm-cp-waiops-1.3.0.tgz --action install-gitops-application --inventory cpwaiopsSetup --namespace cp4waiops --args "--registry ${LOCAL_REGISTRY} --user ${USERNAME} --pass {PASSWORD}"
```
