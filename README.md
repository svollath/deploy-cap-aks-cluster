Scripts to deploy and manage CAP ready Azure AKS clusters (using azure-cli, az).
These scripts are for internal use, as they rely on some fixed presets.

* Handle configuration files for various test/demo clusters on AKS
* Deploy Azure AKS clusters
* Get preconfigured scf-config-values.yaml files
* Stop/start your clusters (VMs) by pointing to the config file
* Delete clusters by pointing to the config file
* Manage Azure DNS entries


# Prerequisites

The scripts are based on the steps from our official [Documentation](https://www.suse.com/documentation/cloud-application-platform-1/book_cap_guides/data/cha_cap_depl-azure.html).
Please follow and check the prerequisites there.

Tested with the following versions:
* CAP Deployment Guide - March 25, 2018
* CAP 1.3.1 (UAA/SCF 2.15.2, Stratos 2.3.0)
* Azure AKS (Kubernetes v1.11.8)
* kubectl (1.10.11+), helm (2.8.2+), azure-cli (2.0.60+) are expected, as well as jq


# Configuration files

The scripts take configuration files. "example.conf" is the default one, which is used if no configuration file is given.
You need to modify "example.conf" for your needs, while I recommend to just copy it to e.g. "myaks.conf" and modify that
```bash
$ <script> -c myaks.conf
```
This way you can save configurations and even manage various different test and demo clusters.

Note:
You can reuse your existing configuration files with 1.3.1 scripts, but I suggest to merge your values into a new configuration based on example.conf from 1.3.1.

# deploy_cap_aks_cluster.sh

"deploy_cap_aks_cluster.sh" executes steps from "Create Resource Group and AKS Instance" on (see Prerequisites).

In addition to deploy the AKS cluster, it does
* install Tiller to the AKS cluster

It also creates a directory (e.g. "CAP-AKS-2019-04-10_16h05_test3") for each deployment with
* a log file for that deployment
* the kubeconfig file for your AKS cluster
* a preconfigured scf-config-values.yaml for your CAP deployment

E.g. run
```bash
./deploy_cap_aks_cluster.sh -c test3.conf
```


## Deploy with Kuberbetes Service LoadBalanced

By default (from CAP-1.3.1 on), kubernetes LoadBalanced service will create public IPs automatically when you deploy CAP via helm later on.
You need to set a subdomain in the configuration file, that will be used for the "susecap.net" domain. E.g. "test3" will configure and suggest the domain "test3.susecap.net".
Later you will then use the e.g. `dns-setup-*.sh -c test3.conf` scripts after each "helm install" to automatically create or update DNS entries.

Depending on network conditions the script will run approx. 20-30 min.

Example output from `deploy_cap_aks_cluster.sh -c test3.conf`
```bash
Starting deployment "CAP-AKS-2019-04-10_16h05_test3" with "test3.conf"
Logfile: CAP-AKS-2019-04-10_16h05_test3/deployment.log
Created resource group: test3-cap-aks
Created AKS cluster: test3 in MC_test3-cap-aks_test3_westeurope
Orchestrator: Kubernetes 1.11.8
Azure VM type: Standard_DS4v2, Premium Storage: True
Fetched kubeconfig
Set swapaccount=1 on: aks-test3-37306405-0
Set swapaccount=1 on: aks-test3-37306405-1
Set swapaccount=1 on: aks-test3-37306405-2
Verified swapaccount enabled on: aks-test3-37306405-0
Verified swapaccount enabled on: aks-test3-37306405-1
Verified swapaccount enabled on: aks-test3-37306405-2
Initialized helm for AKS
Using Kubernetes LoadBalancer Service

Kubeconfig file is stored to: "CAP-AKS-2019-04-10_16h05_test3/kubeconfig"
Run e.g. "export KUBECONFIG=<path>/CAP-AKS-2019-04-10_16h05_test3/kubeconfig" to use it

Values file written to: CAP-AKS-2019-04-10_16h05_test3/scf-config-values.yaml

 Suggested DOMAIN for CAP: "test3.susecap.net"
 Configuration: "services.loadbalanced="true""
 Using storage class: "managed-premium"

You need to:
 1. Deploy UAA
 2. Run "./dns-setup-uaa.sh -c test3.conf"
 3. Deploy SCF
 4. Run "./dns-setup-scf.sh -c test3.conf"
 5. Optionally continue with Stratos UI, and "./dns-setup-console.sh -c test3.conf"
```


# Deploying CAP on top

deploy_cap_aks_cluster.sh leaves you with a rough guide on what to do next, in order to deploy CAP on the fresh AKS cluster.
The first thing you'll need to is to use the kubeconfig with your current shell, by e.g.
```bash
export KUBECONFIG=<path>/CAP-AKS-2019-04-10_16h05_test3/kubeconfig
```

and start with e.g.
```bash
helm install suse/uaa --name susecf-uaa --namespace uaa --values CAP-AKS-2019-04-10_16h05_test3/scf-config-values.yaml
```

For details see the documentation on how to [Deploy with Helm](https://www.suse.com/documentation/cloud-application-platform-1/book_cap_guides/data/sec_cap_cap-on-azure.html).


# Manage AKS clusters

Once everything is set up, you can use "manage_cap_aks_cluster.sh" to save time and costs.
The script will only make use of the AKS resource group name in your configuration, and find the related VMs for you.
So it's also possible to use the command for an existing resource group, by just providing a suitable config file.

`./manage_cap_aks_cluster.sh -c test3.conf [status|start|stop]`

"status" will list the current power state of the VMs, while you can "start" and "stop" them, too.


# Fetch kubeconfig of existing AKS cluster
Like mentioned above, by just providing a suitable config file containing the respective Azure resource group, it's possible
to get the kubeconfig file for an existing AKS cluster. This way you can manage it, or get access to Kubernetes as well.

`fetch_new_kubeconfig.sh -c anew.conf`

will create a directory and store the kubeconfig to it.


# Delete AKS clusters

Not much to say - this will delete the AKS resource group specified, e.g.
```bash
./delete_cap_aks_cluster.sh -c test3.conf
```
You'll have to confirm that request with "y", or cancel with "n".


# Manage Azure DNS

## dns-setup-*.sh

Follow the instructions after "Deploy with Kuberbetes Service LoadBalanced" and run the scripts accordingly.


## dns-cleanup-all.sh

This script cleans up the DNS records for your configuration, or even delete everything for your subdomain:

```bash
./dns-cleanup-all.sh -c test3.conf
```
... will remove/unset current IPs from your records.


```bash
./dns-cleanup-all.sh -c test3.conf rm
```
... will delete records related to your subdomain.


# Notes

## Unsupported "AZ_LOAD_BALANCER=azure" 

Configuring "AZ_LOAD_BALANCER=azure" will manually create a load balancer and network security group within Azure (with `az network lb create`, aso.).

In the end this will give you a public IP, e.g. "40.101.3.25", which will be used for any request on AKS.

The scripts then suggest and configure the domain e.g. "40.101.3.25.omg.howdoi.website" (similar to nip.io/xip.io).
You would then use e.g. "https://40.101.3.25.omg.howdoi.website:8443" to access the Stratos UI.

Depending on the number of ports you specified and network conditions the script will run approx. 35-45 min.
