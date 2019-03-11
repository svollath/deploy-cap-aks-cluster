#!/bin/bash

#  Tested with Azure AKS (Kubernetes v1.9.11) and CAP-1.3 (2.14.5)
#  * Tools kubectl (1.9.8+), helm (2.8.2+), azure-cli (2.0.51+) are expected, as well as jq.
#  The script is run on a machine with working az cli, it will use the current directory as working directory.
#  See https://www.suse.com/documentation/cloud-application-platform-1/book_cap_deployment/data/cha_cap_depl-azure.html
#  Script starts from "Create Resource Group and AKS Instance" on

set -o errexit

conffile="./example.conf"

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
   export AZ_RG_NAME
   export AZ_AKS_NAME
  else
   echo -e "Error: Can't find config file: \"$conffile\""
   exit 1
fi

deploymentid=CAP-AKS-`date +'%Y-%m-%d_%Hh%M'`_$(echo $conffile | cut -d "." -f1)
logfile=$deploymentid/deployment.log
mkdir $deploymentid
echo -e "Deployment log: $deploymentid \n\nValues from $conffile:\n" > $logfile
cat $conffile | sed -e 's/#.*$//' -e '/^$/d' >> $logfile


export AZ_MC_RG_NAME=$(az group list -o table | grep MC_"$AZ_RG_NAME"_ | awk '{print $1}')
export KUBECONFIG=$deploymentid/kubeconfig

while ! az aks get-credentials --admin --resource-group $AZ_RG_NAME --name $AZ_AKS_NAME --file $KUBECONFIG 2>&1>> $logfile; do
  sleep 10
done

echo -e "\nFetched kubeconfig\n\
Use it by executing e.g. \"export KUBECONFIG=$deploymentid/kubeconfig\""
