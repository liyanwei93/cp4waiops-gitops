### Launch boot cluster (online)

1. Launch a pure boot cluster, include kind cluster, argocd, tekton, kube dashboard, helm, gitlab, then create a tekton task to mirror image

```
./script/bootstrap.sh --launchBootCluster --aiopsCase --registry ${LOCAL_REGISTRY} --username ${USERNAME} --password {PASSWORD}
```

2. Launch a boot cluster and deploy argocd applicationset to install aiops.

```
./script/bootstrap.sh --launchBootCluster --loadImage --launchApplication --registry ${LOCAL_REGISTRY} --username ${USERNAME} --password {PASSWORD} --storageClass ${STORAGE_CALSS} --aiopsCase
```

3. Launch a boot cluster, launch a local docker registry, and deploy argocd applicationset to install aiops.

```
./script/bootstrap.sh --launchBootCluster --launchRegistry --loadImage --launchApplication --storageClass ${STORAGE_CALSS} --aiopsCase
```

### Add cluster to argocd (airgap)

```
oc login

./script/bootstrap.sh --addCluster --registry ${LOCAL_REGISTRY} --username ${USERNAME} --password {PASSWORD}
```
