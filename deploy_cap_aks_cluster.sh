#!/bin/bash

#  Tested with Azure AKS (Kubernetes v1.11.8) and CAP-1.3.1 (2.15.2)
#  * Tools kubectl (1.10.11+), helm (2.8.2+), azure-cli (2.0.60+) are expected, as well as jq.
#  The script is run on a machine with working az cli, it will use the current directory as working directory.
#  See https://www.suse.com/documentation/cloud-application-platform-1/book_cap_guides/data/cha_cap_depl-azure.html
#  Script starts from "Create Resource Group and AKS Instance" on

set -o errexit

conffile="./example.conf"
compatfile="./.compatibility.conf"
mode=loadbalanced

usage() {
  echo -e  "\n $0 [-c <config>] Default config is \"$conffile\" \n"
}

while getopts ":c:h" Option
 do
  case $Option in
    c)  conffile=$OPTARG;;
    h)  usage && exit 0;;
    \?) echo -e "Error: Invalid option: -$OPTARG \n" >&2; exit 1;;
    :)  echo -e "Error: Option -$OPTARG requires an argument.\n" >&2; exit 1;;
  esac
done

# Load config file, compatibility file tries to support config files for former versions
if [ -e $conffile ]; then
   . $conffile
   . $compatfile
   export AZ_RG_NAME
   export AZ_AKS_NAME
   export AZ_REGION
   export AZ_KUBE_VERSION
   export AZ_AKS_NODE_POOL_NAME
   export AZ_AKS_NODE_COUNT
   export AZ_AKS_NODE_VM_SIZE
   export AZ_SSH_KEY
   export AZ_ADMIN_USER
   export AZ_DNS_SUB_DOMAIN
   export AZ_DNS_RESOURCE_GROUP
   export AZ_DNS_ZONE_NAME
   export CAP_PASSWORD
   export CAP_AKS_STORAGECLASS
   export AZ_LOAD_BALANCER
   export AZ_CAP_PORTS
  else
   echo -e "Error: Can't find config file: \"$conffile\""
   exit 1
fi

case $AZ_LOAD_BALANCER in
  azure) mode=manual;;
  kube)  mode=loadbalanced;;
  *) echo -e "Error: Set AZ_LOAD_BALANCER to \"azure\" or \"kube\""; exit 1;;
esac

# Check if requested Kubernetes version is available for AKS
KUBE_VERSIONS=$(az aks get-versions --location $AZ_REGION --output table | awk '/^[0-9]/{print$1}' | paste -s -d " " | sed -e 's/ /, /g')
if [ "$(echo $KUBE_VERSIONS | grep -o $AZ_KUBE_VERSION)" != "$AZ_KUBE_VERSION" ]; then
   echo -e "Error: The specified kubernetes version does not exist.\nAvailable versions: $KUBE_VERSIONS\n\n"
   exit 1
fi

# Check if VM type supports Premium Storage
AZ_PREMIUMIO=$(az vm list-skus --location $AZ_REGION --query "[?name=='$AZ_AKS_NODE_VM_SIZE'].[capabilities[?name=='PremiumIO'].value[] | [0]]" -o tsv)
if [ "$CAP_AKS_STORAGECLASS" = "managed-premium" ]; then
   if [ "$AZ_PREMIUMIO" = "False" ]; then
      echo -e "Error: VM type $AZ_AKS_NODE_VM_SIZE does not support Premium Storage"
      exit 1
   fi
fi

deploymentid=CAP-AKS-`date +'%Y-%m-%d_%Hh%M'`_$(echo $conffile | cut -d "." -f1)
logfile=$deploymentid/deployment.log
mkdir $deploymentid
echo -e "Deployment log: $deploymentid \n\nValues from $conffile:\n" > $logfile
cat $conffile | sed -e 's/#.*$//' -e '/^$/d' >> $logfile

echo -e "\nStarting deployment \"$deploymentid\" with \"$conffile\"\nLogfile: $logfile" | tee -a $logfile

az group create --name $AZ_RG_NAME --location $AZ_REGION &>> $logfile
echo -e "Created resource group: $AZ_RG_NAME"

az aks create --resource-group $AZ_RG_NAME --name $AZ_AKS_NAME \
              --node-count $AZ_AKS_NODE_COUNT --admin-username $AZ_ADMIN_USER \
              --ssh-key-value $AZ_SSH_KEY --node-vm-size $AZ_AKS_NODE_VM_SIZE \
              --node-osdisk-size=60 --nodepool-name $AZ_AKS_NODE_POOL_NAME \
              --kubernetes-version $AZ_KUBE_VERSION >&1>> $logfile

export AZ_MC_RG_NAME=$(az group list -o table | grep MC_"$AZ_RG_NAME"_ | awk '{print $1}')
echo -e "Created AKS cluster: $AZ_AKS_NAME in $AZ_MC_RG_NAME" | tee -a $logfile
echo -e "Orchestrator: Kubernetes $AZ_KUBE_VERSION" | tee -a $logfile
echo -e "Azure VM type: $AZ_AKS_NODE_VM_SIZE, Premium Storage: $AZ_PREMIUMIO" | tee -a $logfile

# Fetch kubeconfig
export KUBECONFIG=$deploymentid/kubeconfig
while ! az aks get-credentials --admin --resource-group $AZ_RG_NAME --name $AZ_AKS_NAME --file $KUBECONFIG &>> $logfile; do
  sleep 10
done
echo -e "Fetched kubeconfig"

# Wait until cluster is up
while [[ $node_readiness != "$AZ_AKS_NODE_COUNT True" ]]; do
  sleep 5
  node_readiness=$(
     kubectl get nodes -o json \
      | jq -r '.items[] | .status.conditions[] | select(.type == "Ready").status' \
      | uniq -c | grep -o '\S.*'
  )
done

# Enable swapaccount for each VM
export AZ_AKS_VMNODES=$(az vm list --resource-group $AZ_MC_RG_NAME -o json | jq -r '.[] | select (.tags.poolName | contains("'$AZ_AKS_NODE_POOL_NAME'")) | .name')
for i in $AZ_AKS_VMNODES; do
   az vm run-command invoke -g $AZ_MC_RG_NAME -n $i --command-id RunShellScript --scripts \
   "sudo sed -i -r 's|^(GRUB_CMDLINE_LINUX_DEFAULT=)\"(.*.)\"|\1\"\2 swapaccount=1\"|' \
   /etc/default/grub.d/50-cloudimg-settings.cfg && sudo update-grub" &>> $logfile
   az vm restart -g $AZ_MC_RG_NAME -n $i &>> $logfile
   echo -e "Set swapaccount=1 on: $i"
done

# Wait until cluster is back up again
while [[ $node_readiness != "$AZ_AKS_NODE_COUNT True" ]]; do
  sleep 5
  node_readiness=$(
     kubectl get nodes -o json \
      | jq -r '.items[] | .status.conditions[] | select(.type == "Ready").status' \
      | uniq -c | grep -o '\S.*'
  )
done

# Verify swapaccount is enabled on all VMs
for i in $AZ_AKS_VMNODES; do
   SWAPACCOUNT=$(az vm run-command invoke -g $AZ_MC_RG_NAME -n $i --command-id RunShellScript --scripts \
   "sudo cat /proc/cmdline" | grep -o swapaccount)
   if [ "$SWAPACCOUNT" = "swapaccount" ]; then
      echo -e "Verified swapaccount enabled on: $i" | tee -a $logfile
     else
      echo -e "Error: Swapaccount was not enabled on: $i - aborting" | tee -a $logfile
      exit 1
   fi
done

# Create service account and update tiller
kubectl create serviceaccount tiller --namespace kube-system &>> $logfile
kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller &>> $logfile
helm init --upgrade --service-account tiller &>> $logfile
echo -e "Initialized helm for AKS"

if [ "$mode" = "loadbalanced" ]; then
   echo -e "Using Kubernetes LoadBalancer Service"
fi

# Manually add an Azure Load Balancer and rules (if set to AzureLB)
if [ "$mode" = "manual" ]; then
   az network public-ip create \
     --resource-group $AZ_MC_RG_NAME \
     --name $AZ_AKS_NAME-public-ip \
     --allocation-method Static &>> $logfile

   az network lb create \
     --resource-group $AZ_MC_RG_NAME \
     --name $AZ_AKS_NAME-lb \
     --public-ip-address $AZ_AKS_NAME-public-ip \
     --frontend-ip-name $AZ_AKS_NAME-lb-front \
     --backend-pool-name $AZ_AKS_NAME-lb-back &>> $logfile

   export AZ_NIC_NAMES=$(az network nic list --resource-group $AZ_MC_RG_NAME | jq -r '.[].name')
   for i in $AZ_NIC_NAMES; do
     az network nic ip-config address-pool add \
       --resource-group $AZ_MC_RG_NAME \
       --nic-name $i \
       --ip-config-name ipconfig1 \
       --lb-name $AZ_AKS_NAME-lb \
       --address-pool $AZ_AKS_NAME-lb-back &>> $logfile
   done
   echo -e "Created LoadBalancer (azure)"

   for i in $CAP_PORTS; do
     az network lb probe create \
       --resource-group $AZ_MC_RG_NAME \
       --lb-name $AZ_AKS_NAME-lb \
       --name probe-$i \
       --protocol tcp \
       --port $i &>> $logfile
    
     az network lb rule create \
       --resource-group $AZ_MC_RG_NAME \
       --lb-name $AZ_AKS_NAME-lb \
       --name rule-$i \
       --protocol Tcp \
       --frontend-ip-name $AZ_AKS_NAME-lb-front \
       --backend-pool-name $AZ_AKS_NAME-lb-back \
       --frontend-port $i \
       --backend-port $i \
       --probe probe-$i &>> $logfile
   done
   echo -e "Created LoadBalancer rules for ports: $(echo $CAP_PORTS | sed 's| |, |g')"

   # Manually create Network Security Group and rules (if set to AzureLB)
   export AZ_NSG=$(az network nsg list --resource-group=$AZ_MC_RG_NAME | jq -r '.[].name')
   export AZ_NSG_PRI=200

   for i in $CAP_PORTS; do
     az network nsg rule create \
       --resource-group $AZ_MC_RG_NAME \
       --priority $AZ_NSG_PRI \
       --nsg-name $AZ_NSG \
       --name $AZ_AKS_NAME-$i \
       --direction Inbound \
       --destination-port-ranges $i \
       --access Allow &>> $logfile
     export AZ_NSG_PRI=$(expr $AZ_NSG_PRI + 1)
   done
   echo -e "Created network security group"
fi

# Compute random password for CAP and set it if none is given (for scf-config-values.yaml)
if [ -z $CAP_PASSWORD ]; then
   CAP_PASSWORD=$(mktemp -u XXXXXXXX)
fi

echo -e "\nKubeconfig file is stored to: \"$KUBECONFIG\"" | tee -a $logfile
echo -e "Run e.g. \"export KUBECONFIG=$PWD/$deploymentid/kubeconfig\" to use it\n"

if [ "$mode" = "manual" ]; then
   internal_ips=($(az network nic list --resource-group $AZ_MC_RG_NAME | jq -r '.[].ipConfigurations[].privateIpAddress'))
   extip=\[\"$(echo "${internal_ips[*]}" | sed -e 's/ /", "/g')\"\]
   public_ip=$(az network public-ip show --resource-group $AZ_MC_RG_NAME --name $AZ_AKS_NAME-public-ip --query ipAddress --output tsv)
   domain=${public_ip}.omg.howdoi.website
   cat ./.scf-config-values.template | sed \
      -e '/^# This/d' \
      -e 's/<domain>/'$domain'/g' \
      -e 's/uaapassword/'$CAP_PASSWORD'/g' \
      -e 's/<extip>/'"$extip"'/g' \
      -e '/^services:/d' \
      -e '/loadbalanced/d' \
      -e 's/capakssc/'$CAP_AKS_STORAGECLASS'/g' > $deploymentid/scf-config-values.yaml
   echo -e "Values file written to: $deploymentid/scf-config-values.yaml\n\n \
Public IP:\t\t\t\t${public_ip}\n \
Private IPs (external_ips for CAP):\t$extip\n \
Suggested DOMAIN for CAP: \t\t\"$domain\"\n \
Using storage class: \"$CAP_AKS_STORAGECLASS\"\n\n\
You need to:\n \
Deploy UAA, SCF and Stratos (optionally)\n" | tee -a $logfile
fi

if [ "$mode" = "loadbalanced" ]; then
   domain=$(echo "$AZ_DNS_SUB_DOMAIN.$AZ_DNS_ZONE_NAME")
   cat ./.scf-config-values.template | sed \
      -e '/^# This/d' \
      -e 's/<domain>/'$domain'/g' \
      -e 's/uaapassword/'$CAP_PASSWORD'/g' \
      -e '/private IP/d' \
      -e '/<extip>/d' \
      -e 's/capakssc/'$CAP_AKS_STORAGECLASS'/g' > $deploymentid/scf-config-values.yaml
   echo -e "Values file written to: $deploymentid/scf-config-values.yaml\n\n \
Suggested DOMAIN for CAP: \"$domain\"\n \
Configuration: \"services.loadbalanced=\"true\"\"\n \
Using storage class: \"$CAP_AKS_STORAGECLASS\"\n\n\
You need to:\n \
1. Deploy UAA\n \
2. Run \"./dns-setup-uaa.sh -c $conffile\"\n \
3. Deploy SCF\n \
4. Run \"./dns-setup-scf.sh -c $conffile\"\n \
5. Optionally continue with Stratos UI, and \"./dns-setup-console.sh -c $conffile\"\n" | tee -a $logfile
fi
