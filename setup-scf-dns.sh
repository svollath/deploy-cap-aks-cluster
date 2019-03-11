#!/bin/bash

conffile="./example.conf"
compatfile="./.compatibility.conf"

SCF_NAMESPACE=scf
SCF_SERVICE_IP=router-gorouter
SCF_SERVICE_SSH=diego-ssh-ssh-proxy
SCF_SERVICE_TCP=tcp-router-tcp-router
SCF_SERVICES="$(echo $SCF_SERVICE_IP $SCF_SERVICE_SSH $SCF_SERVICE_TCP)"

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

wait_for_lb() {
  svc_name=$1-public
  
  count=0
  result=0


  # This can fail if the jsonpath isn't available, or be empty when it's not ready yet
  status=$(kubectl --namespace $SCF_NAMESPACE get svc "${svc_name}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2> /dev/null)

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
    status=$(kubectl --namespace $SCF_NAMESPACE get svc "${svc_name}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2> /dev/null)
    set -e
  done

  return ${result}
}

get_lb() {
  svc_name=$1-public
  kubectl --namespace $SCF_NAMESPACE \
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
		   --ipv4-address "${old_ip}" 2>&1> /dev/null
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
	  --ipv4-address "${new_ip}" 2>&1> /dev/null

  echo -e "Setting DNS entry for: $record_name to ${new_ip}"
}

for service in $(echo $SCF_SERVICES); do
    wait_for_lb $service
done

clear_ip "ssh.${AZ_DNS_SUB_DOMAIN}"
clear_ip "tcp.${AZ_DNS_SUB_DOMAIN}"
clear_ip "${AZ_DNS_SUB_DOMAIN}"
clear_ip "*.${AZ_DNS_SUB_DOMAIN}"

SSH_IP="$(get_lb $SCF_SERVICE_SSH)"
SCF_IP="$(get_lb $SCF_SERVICE_IP)"
TCP_IP="$(get_lb $SCF_SERVICE_TCP)"

set_ip "ssh.${AZ_DNS_SUB_DOMAIN}" "${SSH_IP}"
set_ip "tcp.${AZ_DNS_SUB_DOMAIN}" "${TCP_IP}"
set_ip "${AZ_DNS_SUB_DOMAIN}" "${SCF_IP}"
set_ip "*.${AZ_DNS_SUB_DOMAIN}" "${SCF_IP}"
