#!/bin/bash

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
run \"./cleanup-all-dns.sh -c $conffile\"\n\n";;
esac
