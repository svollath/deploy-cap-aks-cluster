#!/bin/bash

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
   export AZ_RG_NAME
   export AZ_AKS_NODE_POOL_NAME
  else
   echo -e "Error: Can't find config file: \"$conffile\""
   exit 1
fi

export AZ_MC_RG_NAME=$(az group list -o table | grep MC_"$AZ_RG_NAME"_ | awk '{print $1}')
export AZ_AKS_VMNODES=$(az vm list --resource-group $AZ_MC_RG_NAME -o json | jq -r '.[] | select (.tags.poolName | contains("'$AZ_AKS_NODE_POOL_NAME'")) | .name')
for i in $AZ_AKS_VMNODES; do
   az vm start -g $AZ_MC_RG_NAME -n $i 2>&1> /dev/null
done

echo -e "\n Started VMs: $AZ_AKS_VMNODES \n"
