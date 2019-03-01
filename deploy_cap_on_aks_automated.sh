#!/bin/bash
#Check if AKSDEPLOYID envvar exist
if [[ -z "${AKSDEPLOYID}" ]]; then
  echo "This script expects AKSDEPLOYID envvar to be provided"; exit
else
  [ -f  "$AKSDEPLOYID/.envvar.sh" ]; source $AKSDEPLOYID/.envvar.sh;
fi
kubectl get nodes
export SUBSCRIPTION_ID=$(az account show | jq -r '.id')
echo "export SUBSCRIPTION_ID=$SUBSCRIPTION_ID" >> $AKSDEPLOYID/.envvar.sh;
export KUBECONFIG="$AKSDEPLOYID/kubeconfig"
echo "export KUBECONFIG=$KUBECONFIG" >>$AKSDEPLOYID/.envvar.sh;
PS3='Please enter your choice: '
set -e
options=("Quit" "Review scfConfig" "Deploy APP All Steps")
select opt in "${options[@]}"
do
    case $opt in
        "Quit")
            break
            ;;
        "Review scfConfig")
             vim $AKSDEPLOYID/scf-config-values.yaml
	     ;;
	"Deploy CAP All Steps")
	echo  "Deploying UAA"
             helm install suse/uaa --name susecf-uaa --namespace uaa --values $AKSDEPLOYID/scf-config-values.yaml
        echo "Wait for UAA pods to be ready"
        PODSTATUS="1" ; NS="uaa" ;
        while [ $PODSTATUS -ne "0" ]; do     
          sleep 20 ;
          PODSTATUS=$(kubectl get pod -n $NS|awk 'BEGIN{cnt=0}!/Completed/{if(substr($2,1,1)<substr($2,3,1))cnt=cnt+1;}END{print cnt} '); 
  	  echo "Til $PODSTATUS pods to wait for in $NS";
        done

        echo "Deploying SCF"
	     SECRET=$(kubectl get pods --namespace uaa -o jsonpath='{.items[?(.metadata.name=="uaa-0")].spec.containers[?(.name=="uaa")].env[?(.name=="INTERNAL_CA_CERT")].valueFrom.secretKeyRef.name}');
	     CA_CERT="$(kubectl get secret $SECRET --namespace uaa -o jsonpath="{.data['internal-ca-cert']}" | base64 --decode -)";
	     echo "CA_CERT=$CA_CERT";
	     helm install suse/cf --name susecf-scf --namespace scf --values $AKSDEPLOYID/scf-config-values.yaml --set "secrets.UAA_CA_CERT=${CA_CERT}"
        echo "Wait for SCF pods to be ready"
        PODSTATUS="1" ; NS="scf" ;
        while [ $PODSTATUS -ne "0" ]; do     
          sleep 20 ;
          PODSTATUS=$(kubectl get pod -n $NS|awk 'BEGIN{cnt=0}!/Completed/{if(substr($2,1,1)<substr($2,3,1))cnt=cnt+1;}END{print cnt} '); 
          echo "Til $PODSTATUS pods to wait for in $NS";
        done

        echo "Deploy CATALOG"
             helm repo add svc-cat https://svc-catalog-charts.storage.googleapis.com ;
	helm repo update;
	helm install svc-cat/catalog --name catalog --namespace catalog --set apiserver.storage.etcd.persistence.enabled=true \
	--set apiserver.healthcheck.enabled=false --set controllerManager.healthcheck.enabled=false --set apiserver.verbosity=2 \
	--set controllerManager.verbosity=2
       echo "Wait for CATALOG pods to be ready"
        PODSTATUS="1" ; NS="catalog" ;
        while [ $PODSTATUS -ne "0" ]; do     
          sleep 20 ;
          PODSTATUS=$(kubectl get pod -n $NS|awk 'BEGIN{cnt=0}!/Completed/{if(substr($2,1,1)<substr($2,3,1))cnt=cnt+1;}END{print cnt} '); 
          echo "Til $PODSTATUS pods to wait for in $NS";
        done
       echo "Create Azure SB"
	export SUBSCRIPTION_ID=$(az account show | jq -r '.id')
	export REGION=eastus
	export SBRGNAME=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 8)-service-broker
	az group create --name ${SBRGNAME} --location ${REGION}
	echo SBRGNAME=${SBRGNAME}
	export SERVICE_PRINCIPAL_INFO="$(az ad sp create-for-rbac --name ${SBRGNAME})"
	echo "export SBRGNAME=$SBRGNAME" >>$AKSDEPLOYID/.envvar.sh
	echo "export REGION=$REGION" >>$AKSDEPLOYID/.envvar.sh
	echo "export SERVICE_PRINCIPAL_INFO='$SERVICE_PRINCIPAL_INFO'" >>$AKSDEPLOYID/.envvar.sh
       echo "Deploy OSBA"
	     helm repo add azure https://kubernetescharts.blob.core.windows.net/azure;
 	     helm repo update;
	TENANT_ID=$(echo ${SERVICE_PRINCIPAL_INFO} | jq -r '.tenant')
	CLIENT_ID=$(echo ${SERVICE_PRINCIPAL_INFO} | jq -r '.appId')
	CLIENT_SECRET=$(echo ${SERVICE_PRINCIPAL_INFO} | jq -r '.password')
	echo REGION=${REGION};
	echo SUBSCRIPTION_ID=${SUBSCRIPTION_ID} \; TENANT_ID=${TENANT_ID}\; CLIENT_ID=${CLIENT_ID}\; CLIENT_SECRET=${CLIENT_SECRET}
	helm install azure/open-service-broker-azure --name osba --namespace osba \
	--set azure.subscriptionId=${SUBSCRIPTION_ID} \
	--set azure.tenantId=${TENANT_ID} \
	--set azure.clientId=${CLIENT_ID} \
	--set azure.clientSecret=${CLIENT_SECRET} \
	--set azure.defaultLocation=${REGION} \
	--set redis.persistence.storageClass=default \
	--set basicAuth.username=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 16) \
	--set basicAuth.password=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 16) \
	--set tls.enabled=false
       echo "Wait for OSBA pods to be ready"
        PODSTATUS="1" ; NS="osba" ;
        while [ $PODSTATUS -ne "0" ]; do     
          sleep 20 ;
          PODSTATUS=$(kubectl get pod -n $NS|awk 'BEGIN{cnt=0}!/Completed/{if(substr($2,1,1)<substr($2,3,1))cnt=cnt+1;}END{print cnt} '); 
          echo "Til $PODSTATUS pods to wait for in $NS";
        done
       echo "CF API set"
	     CFEP=$(awk '/Public IP:/{print "https://api." $NF ".xip.io"}' $AKSDEPLOYID/deployment.log)
	     echo "CF Endpoint : $CFEP"
	     cf api --skip-ssl-validation $CFEP
	     ADMINPSW=$(awk '/CLUSTER_ADMIN_PASSWORD:/{print $NF}' $AKSDEPLOYID/scf-config-values.yaml)
	     cf login -u admin -p $ADMINPSW 
        echo "CF Add SB"
	cf create-service-broker azure $(kubectl get deployment osba-open-service-broker-azure \
	--namespace osba -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name == "BASIC_AUTH_USERNAME")].value}') $(kubectl get secret --namespace osba osba-open-service-broker-azure -o jsonpath='{.data.basic-auth-password}' | base64 -d) http://osba-open-service-broker-azure.osba
	cf service-access -b azure | awk '($2 ~ /basic/)||($1 ~ /mongo/) { system("cf enable-service-access " $1 " -p " $2)}'
	echo "CF Create Org and Space"
	cf create-org testorg;
	cf create-space scftest -o testorg;
	cf target -o "testorg" -s "scftest";
	echo "CF 1st Service"
	    cf create-service azure-mysql-5-7 basic scf-rails-example-db -c "{ \"location\": \"${REGION}\", \"resourceGroup\": \"${SBRGNAME}\", \"firewallRules\": [{\"name\": \"AllowAll\", \"startIPAddress\":\"0.0.0.0\",\"endIPAddress\":\"255.255.255.255\"}]}";
	echo "Wait for SCF 1st Service to be ready"
	    watch -n10 cf service scf-rails-example-db ;
        PODSTATUS="progress" ;
        while [ $PODSTATUS -ne "succeeded" ]; do
          sleep 20 ;
          PODSTATUS=$(cf services|awk '/scf-rails/{print $NF}');
          echo "Status $PODSTATUS for db service";
        done

#       echo "AZ List Mysql DBs to Disable"
#	az mysql server list --resource-group $SBRGNAME|jq '.[] |select(.sslEnforcement=="Enabled")' |awk '/name.*-/{print "az mysql server update --resource-group $SBRGNAME --name " substr($2,2,length($2)-3) " --ssl-enforcement Disabled"}'
       echo "AZ Disable SSL Mysql DBs"
        az mysql server list --resource-group $SBRGNAME|jq '.[] |select(.sslEnforcement=="Enabled")' |awk '/name.*-/{print "az mysql server update --resource-group $SBRGNAME --name " substr($2,2,length($2)-3) " --ssl-enforcement Disabled"}'|sh
        echo "Deploy 1st Rails Appl"
	    echo "Clone the rails application to consume the mySQL db"
	    git clone https://github.com/scf-samples/rails-example $AKSDEPLOYID/rails-example
	    cd $AKSDEPLOYID/rails-example
	    echo "Push the application to SCF"
	    cf push
	    echo "Populate the DB with sample data" 
	    cf ssh scf-rails-example -c "export PATH=/home/vcap/deps/0/bin:/usr/local/bin:/usr/bin:/bin && \
		export BUNDLE_PATH=/home/vcap/deps/0/vendor_bundle/ruby/2.5.0 && \
		export BUNDLE_GEMFILE=/home/vcap/app/Gemfile && cd app && bundle exec rake db:seed"
            cd ../..
	    cf apps
	    cf services
            echo "Test the app"
	    cf apps|awk '/xip/{print "curl " $NF }'|sh
        echo "Deploy Stratos SCF Console"
	    helm install suse/console --name susecf-console --namespace stratos --values $AKSDEPLOYID/scf-config-values.yaml --set services.loadbalanced=true --set metrics.enabled=true
	echo "Wait for STRATOS pods to be ready"
        PODSTATUS="1" ; NS="stratos" ;
        while [ $PODSTATUS -ne "0" ]; do     
          sleep 20 ;
          PODSTATUS=$(kubectl get pod -n $NS|awk 'BEGIN{cnt=0}!/Completed/{if(substr($2,1,1)<substr($2,3,1))cnt=cnt+1;}END{print cnt} '); 
          echo "Til $PODSTATUS pods to wait for in $NS";
        done
	echo "Deploy Metrics"
            helm install stratos/metrics --name=scf-metrics --devel --namespace=metrics -f $AKSDEPLOYID/scf-config-values.yaml
	echo "Wait for METRICS pods to be ready"
        PODSTATUS="1" ; NS="metrics" ;
        while [ $PODSTATUS -ne "0" ]; do     
          sleep 20 ;
          PODSTATUS=$(kubectl get pod -n $NS|awk 'BEGIN{cnt=0}!/Completed/{if(substr($2,1,1)<substr($2,3,1))cnt=cnt+1;}END{print cnt} '); 
          echo "Til $PODSTATUS pods to wait for in $NS";
        done
	;;
        *) echo "invalid option $REPLY";;
    esac
done
