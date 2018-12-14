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

wait_for_uaa_lb() {
  count=0
  result=0

  # This can fail if the jsonpath isn't available, or be empty when it's not ready yet
  set +e
  status=$(kubectl --namespace uaa get svc uaa-uaa-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2> /dev/null)
  set -e
  
  while [ -z "${status}" ]
  do
    sleep 30
    count=$((count + 1))

    if [ ${count} -gt 10 ]
    then
      result=1
      echo "Failed to get load balancer IP" >&2
      break
    fi
    
    set +e
    status=$(kubectl --namespace uaa get svc uaa-uaa-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2> /dev/null)
    set -e
  done

  return ${result}
}

get_uaa_lb() {
  kubectl --namespace uaa get svc uaa-uaa-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2> /dev/null
}

wait_for_uaa_lb

NEW_UAA_IP=$(get_uaa_lb)
OLD_UAA_IP=$(az network dns record-set a show --resource-group susecap-domain --zone-name susecap.net --name uaa.${SUBDOMAIN} | jq .arecords[0].ipv4Address -r)

echo -e "Replacing current setting: ${OLD_UAA_IP} \n"

set +e
az network dns record-set a remove-record \
	--resource-group ${DNS_RESOURCE_GROUP} \
	--zone-name ${ZONE_NAME} \
	--record-set-name uaa.${SUBDOMAIN} \
	--keep-empty-record-set \
	--ipv4-address "${OLD_UAA_IP}" 2>&1> /dev/null

az network dns record-set a remove-record \
	--resource-group ${DNS_RESOURCE_GROUP} \
	--zone-name ${ZONE_NAME} \
	--record-set-name "*.uaa.${SUBDOMAIN}" \
	--keep-empty-record-set \
	--ipv4-address "${OLD_UAA_IP}" 2>&1> /dev/null
set -e
az network dns record-set a add-record \
	--resource-group ${DNS_RESOURCE_GROUP} \
	--zone-name ${ZONE_NAME} \
	--record-set-name uaa.${SUBDOMAIN} \
	--ipv4-address "${NEW_UAA_IP}" 2>&1> /dev/null

az network dns record-set a add-record \
	--resource-group ${DNS_RESOURCE_GROUP} \
	--zone-name ${ZONE_NAME} \
	--record-set-name "*.uaa.${SUBDOMAIN}" \
	--ipv4-address "${NEW_UAA_IP}" 2>&1> /dev/null

echo -e "Set UAA related DNS entries to: ${NEW_UAA_IP} \n"
