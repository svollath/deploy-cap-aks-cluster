#!/bin/bash

#  Tested with Azure AKS (Kubernetes v1.11.8) and CAP-1.3.1 (2.15.2)
#  * Tools kubectl (1.10.11+), helm (2.8.2+), azure-cli (2.0.60+) are expected, as well as jq.
#  The script is run on a machine with working az cli, it will use the current directory as working directory.

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

while ! az aks get-credentials --admin --resource-group $AZ_RG_NAME --name $AZ_AKS_NAME --file $KUBECONFIG &>> $logfile; do
  sleep 10
done

echo -e "\nFetched kubeconfig\n\
Use it by executing e.g. \"export KUBECONFIG=$PWD/$deploymentid/kubeconfig\""
