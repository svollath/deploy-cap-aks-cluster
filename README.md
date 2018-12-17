Scripts to deploy and manage CAP ready Azure AKS clusters (using azure-cli, az).
These scripts are for internal use, as they rely on some fixed presets.

* Handle configuration files for various test/demo clusters on AKS
* Deploy Azure AKS clusters with Azure or Kubernetes LoadBalancer
* Get preconfigured scf-config-values.yaml files
* Stop/start your clusters (VMs) by pointing to the config file
* Delete clusters by pointing to the config file


# Prerequisites

The scripts are based on the steps from our official [Documentation](https://www.suse.com/documentation/cloud-application-platform-1/book_cap_deployment/data/cha_cap_depl-azure.html).
Please follow and check the prerequisites there.

Tested with the following versions:
* CAP Deployment Guide - December 07, 2018
* CAP 1.3 (UAA/SCF 2.14.5, Stratos 2.2.0)
* Azure AKS (Kubernetes v1.9.11)
* kubectl (1.9.8+), helm (2.8.2+), azure-cli (2.0.51+) are expected, as well as jq


# Configuration files

The scripts take configuration files. "example.conf" is the default one, which is used if no configuration file is given.
You need to modify "example.conf" for your needs, while I recommend to just copy it to e.g. "myaks.conf" and modify that
```bash
$ <script> -c myaks.conf
```
This way you can save configurations and even manage various different test and demo clusters.


# deploy-cap-aks-cluster.sh

"deploy-cap-aks-cluster.sh" executes steps from "Create Resource Group and AKS Instance" on (see Prerequisites).

In addition to deploy the AKS cluster, it does
* install Tiller to the AKS cluster
* create podsecuritypolicy "suse.cap.psp"
* create clusterrole "suse:cap:psp" and clusterrolebinding "cap:clusterrole"

It also creates a directory (e.g. "CAP-AKS-2018-12-14_10h00_test1") for each deployment with
* a log file for that deployment
* the kubeconfig file for your AKS cluster
* a preconfigured scf-config-values.yaml for your CAP deployment

E.g. run
```bash
./deploy-cap-aks-cluster.sh -c test1.conf
```


# Deploying CAP on top

deploy-cap-aks-cluster.sh leaves you with a rough guide on what to do next, in order to deploy CAP on the fresh AKS cluster.
The first thing you'll need to is to use the kubeconfig with your current shell, by e.g.
```bash
export KUBECONFIG=./CAP-AKS-2018-12-14_10h48_test1/kubeconfig
```

and start with e.g.
```bash
helm install suse/uaa --name susecf-uaa --namespace uaa --values CAP-AKS-2018-12-14_10h00_test1/scf-config-values.yaml
```

For details see the documentation on how to [Deploy with Helm](https://www.suse.com/documentation/cloud-application-platform-1/book_cap_deployment/data/sec_cap_helm-deploy-prod.html).


# Manage AKS clusters

Once everything is set up, you can use "manage_cap_aks_cluster.sh" to save time and costs.
The script will only make use of the AKS resource group name in your configuration, and find the related VMs for you.
So it's also possible to use the command for an existing resource group, by just providing a suitable config file.

`./manage_cap_aks_cluster.sh -c test1.conf [status|start|stop]`

"status" will list the current power state of the VMs, while you can "start" and "stop" them, too.

# Fetch kubeconfig of existing AKS cluster
Like mentioned above, by just providing a suitable config file containing the respective Azure resource group, it's possible
to get the kubeconfig file for an existing AKS cluster. This way you can manage it, or get access to Kubernetes as well.

`fetch_new_kubeconfig.sh -c anew.conf`

will create a directory and store the kubeconfig to it.


# Delete AKS clusters

Not much to say - this will delete the AKS resource group specified, e.g.
```bash
./delete_cap_aks_cluster.sh -c test1.conf
```
You'll have to confirm that request with "y", or cancel with "n".


# Supported LoadBalancers

## Azure

By default the configuration suggests option "azure". This will create and configure a load balancer within Azure (`az network lb create`).

In the end this will give you a public IP, e.g. "40.101.3.25", which will be used for any request on AKS.

The scripts then suggest and configure the domain e.g. "40.101.3.25.omg.howdoi.website" (similar to nip.io/xip.io).
You would then use e.g. "https://40.101.3.25.omg.howdoi.website:8443" to access the Stratos UI.

Depending on the number of ports you specified and network conditions the script will run approx. 35-45 min.

Example output from `deploy-cap-aks-cluster.sh -c test1.conf`
```bash
Starting deployment "CAP-AKS-2018-12-14_10h00_test1" with "test1.conf"
Logfile: CAP-AKS-2018-12-14_10h00_test1/deployment.log
Created resource group: sebi-cap-aks
Created AKS cluster: sebi in MC_sebi-cap-aks_sebi_westeurope
Fetched kubeconfig
Merged "sebi-admin" as current context in CAP-AKS-2018-12-14_10h00_test1/kubeconfig
Enabled swapaccount=1 on: aks-sebiaks-10282526-0, aks-sebiaks-10282526-1, aks-sebiaks-10282526-2
Created LoadBalancer (azure)
Created LoadBalancer rules for ports: 80, 443, 4443, 2222, 2793
Created network security group
Initialized helm for AKS
Applied PodSecurityPolicy: suse-cap-psp

Kubeconfig file is stored to: "CAP-AKS-2018-12-14_10h00_test1/kubeconfig"

 Public IP:                             40.101.3.25
 Private IPs (external_ips for CAP):    ["10.240.0.4", "10.240.0.5", "10.240.0.6"]
 Suggested DOMAIN for CAP:              "40.101.3.25.omg.howdoi.website"

 Values file written to: CAP-AKS-2018-12-14_10h00_test1/scf-config-values.yaml 

 You need to:
 Deploy UAA, SCF and Stratos (optionally)
```

## Kubernetes

When configuring "kube", a kubernetes load balancer will assign various public IPs to specific roles. You need to set a subdomain in the configuration file,
that will be used for the "susecap.net" domain. E.g. "test2" will configure and suggest the domain "test2.susecap.net".

You will then use the e.g. `setup-*-dns.sh -c test1.conf` scripts to automatically create or update DNS entries for susecap.net based on the extracted IPs.

Depending on network conditions the script will run approx. 20-30 min.

Example output from `deploy-cap-aks-cluster.sh -c test2.conf`
```bash
Starting deployment "CAP-AKS-2018-12-14_14h22_test2" with "test2.conf"
Logfile: CAP-AKS-2018-12-14_14h22_test2/deployment.log
Created resource group: sebi-cap-aks
Created AKS cluster: sebi in MC_sebi-cap-aks_sebi_westeurope
Fetched kubeconfig
Merged "sebi-admin" as current context in CAP-AKS-2018-12-14_14h22_test2/kubeconfig
Enabled swapaccount=1 on: aks-sebiaks-10282526-0, aks-sebiaks-10282526-1, aks-sebiaks-10282526-2
Created network security group
Initialized helm for AKS
Applied PodSecurityPolicy: suse-cap-psp

Kubeconfig file is stored to: "CAP-AKS-2018-12-14_14h22_test2/kubeconfig"

 Suggested DOMAIN for CAP: "test2.susecap.net"
 Additional configuration: "services.loadbalanced="true""

 Values file written to: CAP-AKS-2018-12-14_14h22_test2/scf-config-values.yaml 

 You need to:
 1. Deploy UAA
 2. Run "setup-uaa-dns.sh -c test2.conf"
 3. Deploy SCF
 4. Run "setup-scf-dns.sh -c test2.conf"
 5. Optionally continue with Stratos UI, and "setup-console-dns.sh -c test2.conf"
```
