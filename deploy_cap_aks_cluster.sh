#!/bin/bash

#  Tested with Azure AKS (Kubernetes v1.9.11) and CAP-1.3 (2.14.5)
#  * Tools kubectl (1.9.8+), helm (2.8.2+), azure-cli (2.0.51+) are expected, as well as jq.
#  The script is run on a machine with working az cli, it will use the current directory as working directory.
#  See https://www.suse.com/documentation/cloud-application-platform-1/book_cap_deployment/data/cha_cap_depl-azure.html
#  Script starts from "Create Resource Group and AKS Instance" on

set -o errexit

conffile="./example.conf"
mode=default

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

if [ -e $conffile ]; then
   . $conffile
   export AZ_SUB_DOMAIN
   export AZ_RG_NAME
   export AZ_AKS_NAME
   export AZ_REGION
   export CAP_PORTS
   export AZ_AKS_NODE_POOL_NAME
   export AZ_AKS_NODE_COUNT
   export AZ_AKS_NODE_VM_SIZE
   export AZ_SSH_KEY
   export AZ_ADMIN_USER
   export AZ_ADMIN_PSW
  else
   echo -e "Error: Can't find config file: \"$conffile\""
   exit 1
fi

case $AZ_LOAD_BALANCER in
  azure) mode=default;;
  kube)  mode=loadbalanced;;
  *) echo -e "Error: Set AZ_LOAD_BALANCER to \"azure\" or \"kube\""; exit 1;;
esac

deploymentid=CAP-AKS-`date +'%Y-%m-%d_%Hh%M'`_$(echo $conffile | cut -d "." -f1)
logfile=$deploymentid/deployment.log
mkdir $deploymentid
echo -e "Deployment log: $deploymentid \n\nValues from $conffile:\n" > $logfile
cat $conffile | sed -e 's/#.*$//' -e '/^$/d' >> $logfile

echo -e "\nStarting deployment \"$deploymentid\" with \"$conffile\"\nLogfile: $logfile" | tee -a $logfile

az group create --name $AZ_RG_NAME --location $AZ_REGION 2>&1>> $logfile
echo -e "Created resource group: $AZ_RG_NAME"

az aks create --resource-group $AZ_RG_NAME --name $AZ_AKS_NAME \
              --node-count $AZ_AKS_NODE_COUNT --admin-username $AZ_ADMIN_USER \
              --ssh-key-value $AZ_SSH_KEY --node-vm-size $AZ_AKS_NODE_VM_SIZE \
	      --kubernetes-version 1.13.7 \
              --node-osdisk-size=60 --nodepool-name $AZ_AKS_NODE_POOL_NAME 2>&1>> $logfile
export AZ_CLUSTER_FQDN=$(az aks list -g $AZ_RG_NAME|jq '.[].fqdn'|sed -e 's/"//g')
echo -e "Cluster FQDN: $AZ_CLUSTER_FQDN"
export AZ_MC_RG_NAME=$(az group list -o table | grep MC_"$AZ_RG_NAME"_ | awk '{print $1}')
echo -e "Created AKS cluster: $AZ_AKS_NAME in $AZ_MC_RG_NAME"

export KUBECONFIG=$deploymentid/kubeconfig
echo -e "Fetched kubeconfig"

while ! az aks get-credentials --admin --resource-group $AZ_RG_NAME --name $AZ_AKS_NAME --file $KUBECONFIG; do
  sleep 10
done

while [[ $node_readiness != "$AZ_AKS_NODE_COUNT True" ]]; do
  sleep 10
  node_readiness=$(
     kubectl get nodes -o json \
      | jq -r '.items[] | .status.conditions[] | select(.type == "Ready").status' \
      | uniq -c | grep -o '\S.*'
  )
done

export AZ_AKS_VMNODES=$(az vm list --resource-group $AZ_MC_RG_NAME -o json | jq -r '.[] | select (.tags.poolName | contains("'$AZ_AKS_NODE_POOL_NAME'")) | .name')
for i in $AZ_AKS_VMNODES; do
   az vm run-command invoke -g $AZ_MC_RG_NAME -n $i --command-id RunShellScript --scripts \
   "sudo sed -i -r 's|^(GRUB_CMDLINE_LINUX_DEFAULT=)\"(.*.)\"|\1\"\2 swapaccount=1\"|' \
   /etc/default/grub.d/50-cloudimg-settings.cfg && sudo update-grub" 2>&1>> $logfile
   az vm restart -g $AZ_MC_RG_NAME -n $i 2>&1>> $logfile
done
echo -e "Enabled swapaccount=1 on: $(echo $AZ_AKS_VMNODES | sed 's| |, |g')"

if [ "$mode" = "default" ]; then
   az network public-ip create \
     --resource-group $AZ_MC_RG_NAME \
     --name $AZ_AKS_NAME-public-ip \
     --allocation-method Static 2>&1>> $logfile

   az network lb create \
     --resource-group $AZ_MC_RG_NAME \
     --name $AZ_AKS_NAME-lb \
     --public-ip-address $AZ_AKS_NAME-public-ip \
     --frontend-ip-name $AZ_AKS_NAME-lb-front \
     --backend-pool-name $AZ_AKS_NAME-lb-back 2>&1>> $logfile

   export AZ_NIC_NAMES=$(az network nic list --resource-group $AZ_MC_RG_NAME | jq -r '.[].name')
   for i in $AZ_NIC_NAMES; do
     az network nic ip-config address-pool add \
       --resource-group $AZ_MC_RG_NAME \
       --nic-name $i \
       --ip-config-name ipconfig1 \
       --lb-name $AZ_AKS_NAME-lb \
       --address-pool $AZ_AKS_NAME-lb-back 2>&1>> $logfile
   done
   echo -e "Created LoadBalancer (azure)"

   for i in $CAP_PORTS; do
     az network lb probe create \
       --resource-group $AZ_MC_RG_NAME \
       --lb-name $AZ_AKS_NAME-lb \
       --name probe-$i \
       --protocol tcp \
       --port $i 2>&1>> $logfile

     az network lb rule create \
       --resource-group $AZ_MC_RG_NAME \
       --lb-name $AZ_AKS_NAME-lb \
       --name rule-$i \
       --protocol Tcp \
       --frontend-ip-name $AZ_AKS_NAME-lb-front \
       --backend-pool-name $AZ_AKS_NAME-lb-back \
       --frontend-port $i \
       --backend-port $i \
       --probe probe-$i 2>&1>> $logfile
   done
   echo -e "Created LoadBalancer rules for ports: $(echo $CAP_PORTS | sed 's| |, |g')"
fi

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
    --access Allow 2>&1>> $logfile
  export AZ_NSG_PRI=$(expr $AZ_NSG_PRI + 1)
done
echo -e "Created network security group"

# Apply PSP and update tiller
kubectl create -f rbac-config.yaml 2>&1>> $logfile
helm init --service-account tiller 2>&1>> $logfile
echo -e "Initialized helm for AKS"

#kubectl create -f suse-cap-psp.yaml 2>&1>> $logfile
#echo -e "Applied PodSecurityPolicy: suse-cap-psp"

echo -e "\nKubeconfig file is stored to: \"$KUBECONFIG\"\n" | tee -a $logfile

if [ "$mode" = "default" ]; then
   internal_ips=($(az network nic list --resource-group $AZ_MC_RG_NAME | jq -r '.[].ipConfigurations[].privateIpAddress'))
   extip=\[\"$(echo "${internal_ips[*]}" | sed -e 's/ /", "/g')\"\]
   public_ip=$(az network public-ip show --resource-group $AZ_MC_RG_NAME --name $AZ_AKS_NAME-public-ip --query ipAddress --output tsv)
   domain=${public_ip}.xip.io
   cat ./.scf-config-values.template | sed -e '/^# This/d' -e 's/<domain>/'$domain'/g' -e 's/<extip>/'"$extip"'/g' -e '/^services:/d' -e 's/<fqdn>/'"$AZ_CLUSTER_FQDN"'/g' -e 's/<password>/'"$AZ_ADMIN_PSW"'/g' -e '/loadbalanced/d' > $deploymentid/scf-config-values.yaml
   echo -e " Public IP:\t\t\t\t${public_ip}\n \
Private IPs (external_ips for CAP):\t$extip\n \
Suggested DOMAIN for CAP: \t\t\"$domain\"\n\n \
Values file written to: $deploymentid/scf-config-values.yaml \n\n \
You need to:\n \
Deploy UAA, SCF and Stratos (optionally)\n" | tee -a $logfile
fi

if [ "$mode" = "loadbalanced" ]; then
   domain=$(echo $AZ_SUB_DOMAIN).susecap.net
   cat ./.scf-config-values.template | sed -e '/^# This/d' -e 's/<domain>/'$domain'/g' -e '/private IP/d' -e '/<extip>/d' > $deploymentid/scf-config-values.yaml
   echo -e " Suggested DOMAIN for CAP: \"$domain\"\n \
Additional configuration: \"services.loadbalanced=\"true\"\"\n\n \
Values file written to: $deploymentid/scf-config-values.yaml \n\n \
You need to:\n \
1. Deploy UAA\n \
2. Run \"setup-uaa-dns.sh -c $conffile\"\n \
3. Deploy SCF\n \
4. Run \"setup-scf-dns.sh -c $conffile\"\n \
5. Optionally continue with Stratos UI, and \"setup-console-dns.sh -c $conffile\"\n" | tee -a $logfile
fi
