Scripts to deploy and manage CAP ready Azure AKS clusters (using azure-cli, az).
These scripts are for internal use, as they rely on some fixed presets.

* Handle configuration files for various test/demo clusters on AKS
* Deploy Azure AKS clusters with Azure or Kubernetes LoadBalancer
* Get preconfigured scf-config-values.yaml files
* Stop/start your clusters (VMs) by pointing to the config file
* Delete clusters by pointing to the config file
* > additions JML 280219 : 
* >use the aks-cluster-config.conf file for your deployment (allows versioning of AZ objects while testing)
* >Deploy CAP + OSBA & components & 1st mysql/rail Application through a menu driven approach.
```bash
1) Quit				   9) Create Azure SB		    17) AZ List Mysql DBs to Disable
2) Review scfConfig		  10) Deploy OSBA		    18) AZ Disable SSL Mysql DBs
3) Deploy UAA			  11) Pods OSBA			    19) Deploy 1st Rails Appl
4) Pods UAA			  12) CF API set		    20) Deploy Stratos SCF Console
5) Deploy SCF			  13) CF Add SB			    21) Pods Stratos
6) Pods SCF			  14) CF CreateOrgSpace		    22) Deploy Metrics
7) Deploy CATALOG		  15) CF 1st Service		    23) Pods Metrics
8) Pods CATALOG			  16) CF 1st Service Status
```
* Added the full automated for unattended install of CAP/AKS new script `deploy_cap_on_aks_automated.sh` instead of the full menu
```bash
1) Quit
2) Review scfConfig
3) Deploy CAP All Steps
```
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
You may use the aks-cluster-config.conf as well if you have multiple attempts/versions in parallel.
```bash
$ <script> -c aks-cluster-config.conf
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
* a preconfigured `scf-config-values.yaml` for your CAP deployment

E.g. run
```bash
./deploy-cap-aks-cluster.sh -c aks-cluster-config.conf
```


# Deploying CAP on top

The cluster is ready and now the procedure to deploy the CAP 1.3 on it is following :
* Copy the `init_aks_env.sh` example file containing the definition of ENVVARS required during the CAP deployment script.
```bash
cp init_aks_env.sh init_aks_env_my1.sh
vim init_aks_env_my1.sh
```
* Edit the `AKSDEPLOYID` value to match your deployment above.
```bash
export AKSDEPLOYID="$PWD/"CAP-AKS-2019-08-07_20h13_jmlcluster20""  <- ENVVAR pointing toyour config area for this cluster deployment
export REGION=westeurope                            <- Your azure region where the ServiceBroker will be deployed
export KUBECONFIG="$AKSDEPLOYID/kubeconfig"         <- This is the result of the AKS cluster creation already
export CF_HOME="$AKSDEPLOYID/cfconfig"              <- Your Cloudfoundry config will be stored there
export PS1="\u:\w:$AKSDEPLOYID>\[$(tput sgr0)\]"
CFEP=$(awk '/Public IP:/{print "https://api." $NF ".xip.io"}' $AKSDEPLOYID/deployment.log) <- Extract the public IP from the deployment
cf api --skip-ssl-validation $CFEP
```
* Save your file
* initialise your ENVVARs by 
```bash
source init_aks_env_my1.sh
```
* you may review/edit/modify the `scf-config-values.yaml` file that is generated in the `$AKSDEPLOYID/scf-config-values.yaml` 

> **__The project CAPnMore contains an updated way to make this, compatible with this AKS deployment__**
> https://github.com/jmlambert78/CAPnMore
> ** This version supports both AKS and any K8S cluster compatible with CAP.

** AN UPDATE CHAPTER WILL BE INCLUDED SOON **

OPTION1: Now you may launch the menu driven steps for deploying CAP on the cluster just deployed.
```bash
./deploy_cap_on_aks_by_step.sh
```
* You will get the menu, then go step by step and check that the pods are running prior to engage the next step.(Automation will come soon)
```bash
1) Quit                            9) Create Azure SB               17) AZ List Mysql DBs to Disable
2) Review scfConfig               10) Deploy OSBA                   18) AZ Disable SSL Mysql DBs
3) Deploy UAA                     11) Pods OSBA                     19) Deploy 1st Rails Appl
4) Pods UAA                       12) CF API set                    20) Deploy Stratos SCF Console
5) Deploy SCF                     13) CF Add SB                     21) Pods Stratos
6) Pods SCF                       14) CF CreateOrgSpace             22) Deploy Metrics
7) Deploy CATALOG                 15) CF 1st Service                23) Pods Metrics
8) Pods CATALOG                   16) CF 1st Service Status
```
NOTE : If you QUIT and come back, the script recovers the ENVVARs that are required from all previous steps (Useful!!).

* 2 Review SCFConfig let you edit the `scf-config-values.yaml` again
* Deploy for each elements is in the right order as there are some dependancies.
* Pods XX will just let you watch the completion of pods deployements
* The CF API is the config of your Cloudfoundry endpoint.
* The Catalog/Azure ServiceBroker/OSBA are required to make dynamic provisionning of Azure Services (eg: DBs)
* Point 17/18 are required to modify the SSL option of the deployed db.
* 19 will deploy your 1st application from github, and make a Curl to check it.
* 20 will deploy the CF dashboard (Stratos)
* 21 will deploy the metrics (monitoring) that you will connect then to the stratos GUI.

OPTION2 : Now you may launch all steps in an unattended with with the following :
```bash
./deploy_cap_on_aks_automated.sh
```
* You will get the menu :
```bash
1) Quit
2) Review scfConfig
3) Deploy APP All Steps
```
* 2 Review SCFConfig let you edit the `scf-config-values.yaml` again
* 3 Deploy all steps one after one in the right order.(unattended deployment).
*

ALLCASES: 
when you are there, you have done a great story, and you can start to play efficiently with SCF.
* To Connect the Kubernetes API & the metrics API, go to the Stratos GUI, and in EndPoint, select the one.
* for Kubernetes 
* Endpoint : `https://jml-cap-aks-5-rg-xxxxx-yyyyyy.hcp.eastus.azmk8s.io:443` that you may find in the `$AKSDEPLOYID/deployment.log`
* CertAuth : provide your `kubeconfig` file (that resides in the same $AKSDEPLOYID subdir at `connect` time

* For metrics :
* Endpoint: `https://10.240.0.5:7443`
* Username/Password : as provided in the `scf-config-values.yaml` 

NB: If you have issues on the OSBA you may use the `svcat` tool to see if the service catalog & osba are well configured on the kubernetes side. 

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
