#!/bin/bash

#  Tested with Azure AKS (Kubernetes v1.11.9) and CAP-1.4.0 (2.16.4)
#  * Tools kubectl (1.10.11+), helm (2.8.2+), azure-cli (2.0.65+) are expected, as well as jq.
#  The script is run on a machine with working az cli, it will use the current directory as working directory.

conffile="./example.conf"
compatfile="./.compatibility.conf"

CONSOLE_NAMESPACE=stratos
CONSOLE_SERVICE_IP=console-ui
CONSOLE_SERVICES="$(echo $CONSOLE_SERVICE_IP)"

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

wait_for_lb() {
  svc_name=$1-ext
  
  count=0
  result=0


  # This can fail if the jsonpath isn't available, or be empty when it's not ready yet
  status=$(kubectl --namespace $CONSOLE_NAMESPACE get svc "${svc_name}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2> /dev/null)

  echo -e "Waiting for service: ${svc_name}"  

  while [ -z "${status}" ]
  do
    sleep 30
    count=$((count + 1))

    if [ ${count} -gt 10 ]
    then
      result=1
      echo "Failed to get load balancer IP for ${svc_name}" >&2
      break
    fi

    set +e
    status=$(kubectl --namespace $CONSOLE_NAMESPACE get svc "${svc_name}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2> /dev/null)
    set -e
  done

  return ${result}
}

# Get current records
AZ_DNS_ZONE_RECORDS=$(az network dns record-set a list --resource-group $AZ_DNS_RESOURCE_GROUP --zone-name $AZ_DNS_ZONE_NAME | jq .[].name -r | paste -s -d " ")

get_lb() {
  svc_name=$1-ext
  kubectl --namespace $CONSOLE_NAMESPACE \
	  get svc "${svc_name}" \
	  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' \
	  2> /dev/null
}

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
		   --ipv4-address "${old_ip}" &> /dev/null
           fi
        fi
}

# Sets the IP of the record $1.${AZ_DNS_ZONE_NAME}
set_ip() {	
  record_name=$1
  new_ip=$2

  az network dns record-set a add-record \
	  --resource-group ${AZ_DNS_RESOURCE_GROUP} \
	  --zone-name ${AZ_DNS_ZONE_NAME} \
	  --record-set-name "${record_name}" \
	  --ipv4-address "${new_ip}" &> /dev/null

  echo -e "Setting DNS entry for: $record_name to ${new_ip} \n"
}

for service in $(echo $CONSOLE_SERVICES); do
    wait_for_lb $service
done

clear_ip "console.${AZ_DNS_SUB_DOMAIN}"

CONSOLE_IP="$(get_lb $CONSOLE_SERVICE_IP)"

set_ip "console.${AZ_DNS_SUB_DOMAIN}" "${CONSOLE_IP}"
