#!/bin/bash

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
   export AZ_DNS_SUB_DOMAIN
   export AZ_DNS_RESOURCE_GROUP
   export AZ_DNS_ZONE_NAME
  else
   echo -e "Error: Can't find config file: \"$conffile\""
   exit 1
fi

# Get current records
AZ_DNS_ZONE_RECORDS=$(az network dns record-set a list --resource-group $AZ_DNS_RESOURCE_GROUP --zone-name $AZ_DNS_ZONE_NAME | jq .[].name -r | paste -s -d " ")

# Gets the IP of the record $1.${AZ_DNS_ZONE_NAME}
get_ip() {
        record_name=$1

        az network dns record-set a show \
                --resource-group ${AZ_DNS_RESOURCE_GROUP} \
                --zone-name ${AZ_DNS_ZONE_NAME} \
                --name "${record_name}" \
                | jq .arecords[0].ipv4Address -r
}

# Clears the IP of the record $1.${AZ_DNS_ZONE_NAME}
clear_ip() {
        record_name=$1

        if [ $(echo $AZ_DNS_ZONE_RECORDS | grep -o " $(echo $record_name | sed -e 's/\*/\\\*/g') ") ]; then

           old_ip=$(get_ip "${record_name}")

           if [ "$old_ip" != "null" ]; then
             
              az network dns record-set a remove-record \
                      --resource-group ${AZ_DNS_RESOURCE_GROUP} \
                      --zone-name ${AZ_DNS_ZONE_NAME} \
                      --record-set-name "${record_name}" \
                      --keep-empty-record-set \
                      --ipv4-address "${old_ip}" 2>&1> /dev/null
              echo -e "Cleaned current setting for: $record_name"
             else
              echo -e "Clean. Nothing to do for: $record_name"
           fi
          else
           echo -e "There's no record "$record_name" for zone "$AZ_DNS_ZONE_NAME" - nothing changed"
        fi
}

clear_ip "console.${AZ_DNS_SUB_DOMAIN}"
clear_ip "ssh.${AZ_DNS_SUB_DOMAIN}"
clear_ip "tcp.${AZ_DNS_SUB_DOMAIN}"
clear_ip "${AZ_DNS_SUB_DOMAIN}"
clear_ip "*.${AZ_DNS_SUB_DOMAIN}"
clear_ip "uaa.${AZ_DNS_SUB_DOMAIN}"
clear_ip "*.uaa.${AZ_DNS_SUB_DOMAIN}"
