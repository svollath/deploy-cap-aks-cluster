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
options=("Quit" "Review scfConfig" "Deploy UAA" "Pods UAA" \
 "Deploy SCF" "Pods SCF" "Deploy CATALOG" "Pods CATALOG" \
"Create Azure SB" "Deploy OSBA" "Pods OSBA" "CF API set" \
"CF Add SB" "CF CreateOrgSpace" "CF 1st Service" \
"CF 1st Service Status" "AZ List Mysql DBs to Disable" "AZ Disable SSL Mysql DBs" "Deploy 1st Rails Appl" \
"Deploy Stratos SCF Console" "Pods Stratos" "Deploy Metrics" "Pods Metrics" \
"CF 1st mongoDB Service" "CF 1st mongoDB Service Status" "Deploy 2nd App Nodejs")
select opt in "${options[@]}"
do
    case $opt in
        "Quit")
            break
            ;;
        "Review scfConfig")
             vim $AKSDEPLOYID/scf-config-values.yaml
	     ;;
        "Deploy UAA")
             helm install suse/uaa --name susecf-uaa --namespace uaa --values $AKSDEPLOYID/scf-config-values.yaml
            ;;
        "Pods UAA")
 	     watch kubectl get pods -n uaa
            ;;
	"Deploy SCF")
	     SECRET=$(kubectl get pods --namespace uaa -o jsonpath='{.items[?(.metadata.name=="uaa-0")].spec.containers[?(.name=="uaa")].env[?(.name=="INTERNAL_CA_CERT")].valueFrom.secretKeyRef.name}');
	     CA_CERT="$(kubectl get secret $SECRET --namespace uaa -o jsonpath="{.data['internal-ca-cert']}" | base64 --decode -)";
	     echo "CA_CERT=$CA_CERT";
	     helm install suse/cf --name susecf-scf --namespace scf --values $AKSDEPLOYID/scf-config-values.yaml --set "secrets.UAA_CA_CERT=${CA_CERT}"
	     ;;
        "Pods SCF")
	     watch kubectl get pods -n scf
            ;;
        "Deploy CATALOG")
             helm repo add svc-cat https://svc-catalog-charts.storage.googleapis.com ;
	helm repo update;
	helm install svc-cat/catalog --name catalog --namespace catalog --set apiserver.storage.etcd.persistence.enabled=true \
	--set apiserver.healthcheck.enabled=false --set controllerManager.healthcheck.enabled=false --set apiserver.verbosity=2 \
	--set controllerManager.verbosity=2
            ;;
       "Pods CATALOG")
             watch kubectl get pods -n catalog
            ;;
       "Create Azure SB")
	export SUBSCRIPTION_ID=$(az account show | jq -r '.id')
	export REGION=eastus
	export SBRGNAME=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 8)-service-broker
	az group create --name ${SBRGNAME} --location ${REGION}
	echo SBRGNAME=${SBRGNAME}
	export SERVICE_PRINCIPAL_INFO="$(az ad sp create-for-rbac --name ${SBRGNAME})"
	echo "export SBRGNAME=$SBRGNAME" >>$AKSDEPLOYID/.envvar.sh
	echo "export REGION=$REGION" >>$AKSDEPLOYID/.envvar.sh
	echo "export SERVICE_PRINCIPAL_INFO='$SERVICE_PRINCIPAL_INFO'" >>$AKSDEPLOYID/.envvar.sh
	    ;;
       "Deploy OSBA")
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
	    ;;
       "Pods OSBA")
	     watch kubectl get pods -n osba
            ;;
       "CF API set")
	     CFEP=$(awk '/Public IP:/{print "https://api." $NF ".xip.io"}' $AKSDEPLOYID/deployment.log)
	     echo "CF Endpoint : $CFEP"
	     cf api --skip-ssl-validation $CFEP
	     ADMINPSW=$(awk '/CLUSTER_ADMIN_PASSWORD:/{print $NF}' $AKSDEPLOYID/scf-config-values.yaml)
	     cf login -u admin -p $ADMINPSW 
            ;;
        "CF Add SB")
	cf create-service-broker azure $(kubectl get deployment osba-open-service-broker-azure \
	--namespace osba -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name == "BASIC_AUTH_USERNAME")].value}') $(kubectl get secret --namespace osba osba-open-service-broker-azure -o jsonpath='{.data.basic-auth-password}' | base64 -d) http://osba-open-service-broker-azure.osba
	cf service-access -b azure | awk '($2 ~ /basic/)||($1 ~ /mongo/) { system("cf enable-service-access " $1 " -p " $2)}'
	    ;;
	"CF CreateOrgSpace")
	cf create-org testorg;
	cf create-space scftest -o testorg;
	cf target -o "testorg" -s "scftest";
	    ;;
	"CF 1st Service")
	    cf create-service azure-mysql-5-7 basic scf-rails-example-db -c "{ \"location\": \"${REGION}\", \"resourceGroup\": \"${SBRGNAME}\", \"firewallRules\": [{\"name\": \"AllowAll\", \"startIPAddress\":\"0.0.0.0\",\"endIPAddress\":\"255.255.255.255\"}]}";
	    ;;
	"CF 1st Service Status")
	    watch -n10 cf service scf-rails-example-db ;


	    ;;
       "AZ List Mysql DBs to Disable")
	az mysql server list --resource-group $SBRGNAME|jq '.[] |select(.sslEnforcement=="Enabled")' |awk '/name.*-/{print "az mysql server update --resource-group $SBRGNAME --name " substr($2,2,length($2)-3) " --ssl-enforcement Disabled"}'
            ;;
       "AZ Disable SSL Mysql DBs")
        az mysql server list --resource-group $SBRGNAME|jq '.[] |select(.sslEnforcement=="Enabled")' |awk '/name.*-/{print "az mysql server update --resource-group $SBRGNAME --name " substr($2,2,length($2)-3) " --ssl-enforcement Disabled"}'|sh
            ;;
        "Deploy 1st Rails Appl")
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
	    ;;
        "Deploy Stratos SCF Console")
	    helm install suse/console --name susecf-console --namespace stratos --values $AKSDEPLOYID/scf-config-values.yaml --set services.loadbalanced=true --set metrics.enabled=true
	    ;;
	"Pods Stratos")
	    watch kubectl get pods -n stratos
	    ;;
	"Deploy Metrics")
            helm install stratos/metrics --name=scf-metrics --devel --namespace=metrics -f $AKSDEPLOYID/scf-config-values.yaml
	    ;;
	"Pods Metrics")
	    watch kubectl get pods -n metrics
	    ;;
        "CF 1st mongoDB Service")
	    cf create-service azure-cosmosdb-mongo-account account scf-mongo-db -c "{ \"location\": \"${REGION}\", \"resourceGroup\": \"${SBRGNAME}\"}"
            ;;
        "CF 1st mongoDB Service Status")
            watch -n10 cf service scf-mongo-db ;
	    ;;
        "Deploy 2nd App Nodejs")
            echo "Clone the nodejs application to consume mongodb db"
            git clone https://github.com/jmlambert78/node-backbone-mongo $AKSDEPLOYID/nodejs-example
            cd $AKSDEPLOYID/nodejs-example
            echo "Push the application to SCF"
            cf push
	    cf bind-service node-backbone-mongo scf-mongo-db
	    cf restage node-backbone-mongo
            cd ../..
            cf apps
            cf services
            echo "Test the app"
            cf apps|awk '/node-backbone-mongo/{print "curl " $NF }'|sh
            ;;
 
        *) echo "invalid option $REPLY";;
    esac
done
