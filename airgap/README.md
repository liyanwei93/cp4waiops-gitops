### Launch boot cluster (online)

Launch a boot cluster, include `kind cluster`, `argocd`, `tekton`, `gitlab`

```
./script/bootstrap.sh --launchBootCluster
```

Usage help:

```
--launchBootCluster                         # Launch a pure boot cluster, include `kind`, `argocd`, `tekton`, `gitlab`
--launchRegistry                            # Launch a local docker registry if you don't have one
--registry ${LOCAL_REGISTRY}                # Local docker registry, provide this if you have a local docker registry
--username ${USERNAME}                      # Local docker registry username, provide this if you have a local docker registry
--password ${PASSWORD}                      # Local docker registry password, provide this if you have a local docker registry
--cpToken ${CPTOKEN}                        # cp.icr.io registry token
--storageClass ${STORAGE_CALSS}             # storage class of your target OCP cluster
--aiopsCase ${aiopsCase}                    # Case bundle name
--aiopsCaseVersoin ${aiopsCaseVersoin}      # Case bundle version

Optional:
--gitRepo ${GITREPO}                        # Git repo name, provide this if you want to use your own git server
--gitUsername ${GITUSERNAME}                # Git repo username, provide this if you want to use your own git server
--gitPassword ${GITPASSWORD}                # Git repo password, provide this if you want to use your own git server
--argocdUrl ${ARGOCD_URL}                   # ArgoCD server, provide this if you want to use your own argocd server
--argocdUsername ${ARGOCD_USERNAME}         # ArgoCD login username, provide this if you want to use your own argocd server
--argocdPassword ${ARGOCD_PASSWORD}         # ArgoCD login password, provide this if you want to use your own argocd server
```

### Add cluster to argocd (airgap)

```
oc login

./script/bootstrap.sh --addCluster --registry ${LOCAL_REGISTRY} --username ${USERNAME} --password {PASSWORD}
```
