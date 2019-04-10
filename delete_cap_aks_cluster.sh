#!/bin/bash

#  Tested with Azure AKS (Kubernetes v1.11.8) and CAP-1.3.1 (2.15.2)
#  * Tools kubectl (1.10.11+), helm (2.8.2+), azure-cli (2.0.60+) are expected, as well as jq.
#  The script is run on a machine with working az cli, it will use the current directory as working directory.

set -o errexit

conffile="./example.conf"
compatfile="./.compatibility.conf"

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
   . $compatfile
   export AZ_RG_NAME
   export AZ_DNS_SUB_DOMAIN
  else
   echo -e "Error: Can't find config file: \"$conffile\""
   exit 1
fi

az group delete --name $AZ_RG_NAME
echo -e "Deleted resource group \"$AZ_RG_NAME\"\n"

case $AZ_LOAD_BALANCER in
  kube)  echo -e "You might want to cleanup DNS records for \"$AZ_DNS_SUB_DOMAIN\"\n \
run \"./dns-cleanup-all.sh -c $conffile\"\n\n";;
esac
