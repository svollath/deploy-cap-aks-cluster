#!/bin/bash
export AKSDEPLOYID="$PWD/"CAP-AKS-2019-08-07_20h13_jmlcluster20""
export REGION=westeurope
export KUBECONFIG="$AKSDEPLOYID/kubeconfig"
export CF_HOME="$AKSDEPLOYID/cfconfig"
export PS1="\u:\w:$AKSDEPLOYID>\[$(tput sgr0)\]"

export PS1="\w:>\[$(tput sgr0)\]"

CFEP=$(awk '/Public IP:/{print "https://api." $NF ".xip.io"}' $AKSDEPLOYID/deployment.log)
cf api --skip-ssl-validation $CFEP
