#!/bin/bash

set -o errexit

conffile="./example.conf"
cmd=$(echo $@ | sed -r 's/(-c )[^ ]+ //' | grep -m1 -o -e start -e stop | head -n 1)

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

case $cmd in
  start) mode=start;;
  stop)  mode=stop;;
  *)     mode=status;;
esac

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
      az vm $mode -g $AZ_MC_RG_NAME -n $i 2>&1> /dev/null
   done
fi

for i in $AZ_AKS_VMNODES; do
    echo "$i: $(az vm show -d -g $AZ_MC_RG_NAME -n $i | jq -r '.powerState')"
done
