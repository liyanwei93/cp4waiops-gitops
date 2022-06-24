# Name

IBM Cloud Pak&reg; for Watson AIOps AI Manager v3.3.2

# Introduction

## Details

IBM Cloud Pak&reg; for Watson AIOps is an AIOps platform that deploys advanced, explainable AI across the IT Operations (ITOps) toolchain so that you can confidently assess, diagnose, and resolve incidents across mission-critical workloads.

Built on IBM Automation foundation, IBM Cloud Pak for Watson AIOps eases the path to adopting advanced AI for ITOps to decrease your operational costs. With this Cloud Pak, you can increase your customer satisfaction by proactively avoiding incidents and accelerating your time to resolution.

The scale of IT systems and their complexity is continually increasing over the last few years because of digital transformation, containerization, and hybrid cloud adoption. IT teams are being inundated with routine maintenance activities and expanding cloud services, leaving them little or no time to contribute toward innovation. To accelerate business automation, reduce complexity, save costs, and automate regular tasks, companies must use the power of AI.

IBM Cloud Pak for Watson AIOps powers automation by using diverse data sets from an entire range of hybrid environments from cloud to on-premises, and bringing the information together across ITOps. With this Cloud Pak, you can tap into shared automation services to get insight into how your processes run. You can also visualize hotspots and bottlenecks, and pinpoint what to fix with event detection to prioritize which issues to address first.

IBM Cloud Pak for Watson AIOps helps you uncover hidden insights from multiple sources of data, such as logs, metrics, and events. The Cloud Pak delivers those insights directly into the tools that your teams already use, such as Slack or Microsoft Teams, in near real-time. Included AI management tools provides you with unprecedented visibility into your organization's infrastructure so that you can predict failures and facilitate problem resolution.

The IBM Automation foundation that IBM Cloud Pak for Watson AIOps is installed upon is a common foundation of AI and automation that delivers a secure and consistent experience for multiple IBM Cloud Paks. For example, the foundation provides a standard dashboard with a customizable card-based layout that shows key data. It also provides fine-grained role-based access control on menu items and displayed information; and guided tours and tutorials to help users get started.

## Features
IBM Cloud Pak for Watson AIOps is composed of the following key features:

- Guided tours
- AI management
- ChatOps
- AI models and training
- Data ingestion
- Application management
- Infrastructure automation

These capabilities are supported by an ecosystem of connectors and capabilities that manage all facets of the AIOps lifecycle from model training to execution.

See the [IBM Documentation: Overview of IBM Cloud Pak for Watson AIOps](https://www.ibm.com/docs/en/SSJGDOB_3.3.2/overview/overview.html) for more information.

IBM Watson AIOps consists of the following core components.

# Details

## Prerequisites

The following prerequisites are required for a successful installation.

- A Red Hat OpenShift Container Platform cluster with persistent storage support. For more information on the cluster requirements, see [IBM Documentation: Planning System Requirements](https://www.ibm.com/docs/en/SSJGDOB_3.3.2/planning/requirements_system.html).
- Openshift command line interface (`oc`) installed and able to communicate with the cluster. Cluster administrator access is required.

For more information on prerequisites, see IBM Documentation for [online](https://www.ibm.com/docs/en/SSJGDOB_3.3.2/installing/prerequisites.html) and [airgap](https://www.ibm.com/docs/en/SSJGDOB_3.3.2/installing/prerequisites_airgap.html) deployments.

### Resources Required
See [IBM Documentation: Hardware requirements](https://www.ibm.com/docs/en/SSJGDOB_3.3.2/planning/requirements_hware_both.html) for detailed information.

> - You cannot change your selected size after deployment.
> - Multi-region and multi-zone clusters are not supported.

The minimum cluster requirements for a trial deployment are:
- Worker node count: 3
- vCPU: 48
- Memory (GB): 132
- CoreOS root disk (GB): 360
- Persistent storage (Gi): 671

# Installing (Guidance)

Ensure that you understand and have met the requirements explained under the [Prerequisites](#Prerequisites) topic.

Refer to the IBM Documentation for guidance on [IBM Documentation: Installing IBM Cloud Pak for Watson AIOps](https://www.ibm.com/docs/en/SSJGDOB_3.3.2/installing/installing_aimgr.html).

## Configuration

### Ingress Controller Config

Your OpenShift environment may need to be updated to allow network policies to function correctly. To determine if your OpenShift environment is affected, view the default ingresscontroller and locate the property `endpointPublishingStrategy.type`. If it is set to `HostNetwork`, the network policy will not work against routes unless the default namespace contains the selector label.

```
kubectl get ingresscontroller default -n openshift-ingress-operator -o yaml

  endpointPublishingStrategy:
    type: HostNetwork
```
To set the label via a patch of the default namespace run:

```
kubectl patch namespace default --type=json -p '[{"op":"add","path":"/metadata/labels","value":{"network.openshift.io/policy-group":"ingress"}}]'
```

### Network Policy for traffic between the Operator Lifecycle Manager and the CatalogSource service

To install IBM Cloud Pak for Watson AIOps, the OpenShift Operator Lifecycle Manager (OLM) must be able to communicate with the IBM Cloud Pak for Watson AIOps CatalogSource service. If your OpenShift cluster has network policies that restrict communication, you must create a network policy to allow communication between the OLM and the IBM Cloud Pak for Watson AIOps CatalogSource service.

The following network policy when applied will allows traffic between the IBM Cloud Pak for Watson AIOps installation namespace and all other namespaces.
Replace <namespace> with the IBM Cloud Pak for Watson AIOps installation namespace.

```
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all-egress-and-ingress
  namespace: <namespace>
spec:
  egress:
  - {}
  ingress:
  - {}
  podSelector: {}
  policyTypes:
  - Egress
  - Ingress
```

If you require a more restrictive network policy, then you can create a network policy that only allows traffic between the OLM namespace and the IBM Cloud Pak for Watson AIOps installation namespace. For more information see [Red Hat OpenShift Documentation: About Network Policy](https://docs.openshift.com/container-platform/4.8/networking/network_policy/about-network-policy.html).

## Storage

You must create persistent storage prior to your installation of IBM Cloud Pak for Watson AIOps on OpenShift.

For more information on storage requirements and the steps required to set up your storage, see [IBM Documentation: Storage considerations](https://www.ibm.com/docs/en/SSJGDOB_3.3.2/planning/considerations_storage.html).


## SecurityContextConstraints Requirements

This chart requires a SecurityContextConstraints(SCC) to be bound to the target service account groups prior to installation. All associated pods will have access to use this SCC. A SCC constrains the actions a pod can perform.  

The IBM Cloud Pak for Watson AIOps will utilize the Openshift Restricted SCC available out of the box. In addition, the following Custom SCCs are used.

#### Custom SecurityContextConstraints definitions

```
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: ibm-noi-scc
allowHostDirVolumePlugin: false
allowHostIPC: true
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegeEscalation: true
allowPrivilegedContainer: false
defaultAddCapabilities: []
allowedCapabilities:
- SETPCAP
- AUDIT_WRITE
- CHOWN
- NET_RAW
- DAC_OVERRIDE
- FOWNER
- FSETID
- KILL
- SETUID
- SETGID
- NET_BIND_SERVICE
- SYS_CHROOT
- SETFCAP
- IPC_OWNER
- IPC_LOCK
- SYS_NICE
- DAC_OVERRIDE
priority: 11
fsGroup:
  type: RunAsAny
readOnlyRootFilesystem: false
requiredDropCapabilities:
- MKNOD
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: RunAsAny
supplementalGroups:
  type: RunAsAny
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
---
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: aiops-restricted
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegedContainer: false
allowPrivilegeEscalation: false
allowedCapabilities: null
allowedFlexVolumes: null
allowedUnsafeSysctls: null
defaultAddCapabilities: null
defaultAllowPrivilegeEscalation: false
forbiddenSysctls:
  - "*"
fsGroup:
  type: MustRunAs
  ranges:
  - max: 65535
    min: 1
readOnlyRootFilesystem: false
requiredDropCapabilities:
- ALL
runAsUser:
  type: MustRunAsNonRoot
seccompProfiles:
- docker/default
seLinuxContext:
  type: RunAsAny
supplementalGroups:
  type: MustRunAs
  ranges:
  - max: 65535
    min: 1
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
```

## Limitations

* Platform limited, only supports `amd64` worker nodes.
* For an overview of known issues see the IBM Documentation topic for [IBM Documentation: Known issues and limitations](https://www.ibm.com/docs/en/SSJGDOB_3.3.2/about/known_issues.html).

## Documentation

* [IBM Documentation: IBM Cloud Pak for Watson AIOps v3.3.2](https://www.ibm.com/docs/en/SSJGDOB_3.3.2).
