#!/bin/sh

set -e
set -u

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
   export AZ_SUB_DOMAIN
  else
   echo -e "Error: Can't find config file: \"$conffile\""
   exit 1
fi

ZONE_NAME=susecap.net
DNS_RESOURCE_GROUP=susecap-domain

SUBDOMAIN=$AZ_SUB_DOMAIN

wait_for_lb() {
  svc_name=$1-ext
  
  count=0
  result=0


  # This can fail if the jsonpath isn't available, or be empty when it's not ready yet
  set +e
  status=$(kubectl --namespace stratos get svc "${svc_name}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2> /dev/null)
  set -e
  
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
    status=$(kubectl --namespace stratos get svc "${svc_name}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2> /dev/null)
    set -e
  done

  return ${result}
}

get_lb() {
  svc_name=$1-ext
  kubectl --namespace stratos \
	  get svc "${svc_name}" \
	  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' \
	  2> /dev/null
}

# Gets the IP of the record $1.${ZONE_NAME}
get_ip() {
	record_name=$1

	az network dns record-set a show \
		--resource-group ${DNS_RESOURCE_GROUP} \
		--zone-name ${ZONE_NAME} \
		--name "${record_name}" \
		| jq .arecords[0].ipv4Address -r 2>&1> /dev/null
}

# Clears the IP of the record $1.${ZONE_NAME}
clear_ip() {
	record_name=$1

	echo -e "Cleaning current setting for: $record_name \n"

	old_ip=$(get_ip "${record_name}")

	az network dns record-set a remove-record \
		--resource-group ${DNS_RESOURCE_GROUP} \
		--zone-name ${ZONE_NAME} \
		--record-set-name "${record_name}" \
		--keep-empty-record-set \
		--ipv4-address "${old_ip}" 2>&1> /dev/null
}

# Sets the IP of the record $1.${ZONE_NAME}
set_ip() {	
  record_name=$1
  new_ip=$2

  echo -e "Setting DNS entry for: $record_name \n"

  az network dns record-set a add-record \
	  --resource-group ${DNS_RESOURCE_GROUP} \
	  --zone-name ${ZONE_NAME} \
	  --record-set-name "${record_name}" \
	  --ipv4-address "${new_ip}" 2>&1> /dev/null
}

wait_for_lb console-ui

set +e
clear_ip "console.${SUBDOMAIN}"
set -e

CONSOLE_IP="$(get_lb console-ui)"

set_ip "console.${SUBDOMAIN}" "${CONSOLE_IP}"
