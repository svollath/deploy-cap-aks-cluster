#!/bin/bash

#  Tested with Azure AKS (Kubernetes v1.11.8) and CAP-1.3.1 (2.15.2)
#  * Tools kubectl (1.10.11+), helm (2.8.2+), azure-cli (2.0.60+) are expected, as well as jq.
#  The script is run on a machine with working az cli, it will use the current directory as working directory.

set -o errexit

conffile="./example.conf"

#Parse arguments the ugly way
cmd=$(echo $@ | sed -r 's/(-c )[^ ]+ //' | grep -m1 -o -e start -e stop | head -n 1)
if echo $@ | grep -e 'start.*.-' -e 'stop.*.-' &>/dev/null; then
   OPTIND=2
fi
case $cmd in
  start) mode=start;;
  stop)  mode=stop;;
  *)     mode=status;;
esac

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

if [ "$mode" != "status" ]; then
   for i in $AZ_AKS_VMNODES; do
      az vm $mode -g $AZ_MC_RG_NAME -n $i &> /dev/null
   done
fi

for i in $AZ_AKS_VMNODES; do
    echo "$i: $(az vm show -d -g $AZ_MC_RG_NAME -n $i | jq -r '.powerState')"
done
