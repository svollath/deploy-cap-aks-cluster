export AKSDEPLOYID=CAP-AKS-2019-02-28_12h22_jmlcluster5
export KUBECONFIG="$AKSDEPLOYID/kubeconfig"
CFEP=$(awk '/Public IP:/{print "https://api." $NF ".xip.io"}' $AKSDEPLOYID/deployment.log)
cf api --skip-ssl-validation $CFEP
