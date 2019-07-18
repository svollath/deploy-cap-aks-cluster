export AKSDEPLOYID=CAP-AKS-2019-07-17_15h23_jmlcluster13
export REGION=westeurope
export KUBECONFIG="$AKSDEPLOYID/kubeconfig"
CFEP=$(awk '/Public IP:/{print "https://api." $NF ".xip.io"}' $AKSDEPLOYID/deployment.log)
cf api --skip-ssl-validation $CFEP
