#!/bin/bash

# Adds couchbase to an existing cluster on GCE
#
# Assumes you have a running kubernetes cluster
# created with `export KUBERNETES_PROVIDER=aws; export MASTER_SIZE=t2.medium; MINION_SIZE=t2.medium; echo curl -sS https://get.k8s.io | bash`
# or a local Kubernetes source folder where
# kubernetes/cluster/kube-up.sh was run


CBUSER=user
CBPASSWORD=passw0rd

SKYDNS_DOMAIN=default.svc.cluster.local
AWS_SSH_KEY=${AWS_SSH_KEY:-$HOME/.ssh/kube_aws_rsa}

SSH_USER=ubuntu
AWS_CMD="aws --output json ec2"

function get_instanceid_from_name {
  local tagName=$1
  $AWS_CMD --output text describe-instances \
    --filters Name=tag:Name,Values=${tagName} \
              Name=instance-state-name,Values=running \
    --query Reservations[].Instances[].InstanceId
}

function get_instance_public_ip {
  local instance_id=$1
  $AWS_CMD --output text describe-instances \
    --instance-ids ${instance_id} \
    --query Reservations[].Instances[].NetworkInterfaces[0].Association.PublicIp
}

MASTER_NAME=kubernetes-master
if [[ -z "${KUBE_MASTER_ID-}" ]]; then
  KUBE_MASTER_ID=$(get_instanceid_from_name ${MASTER_NAME})
fi
if [[ -z "${KUBE_MASTER_ID-}" ]]; then
  echo "Could not detect Kubernetes master node.  Make sure you've launched a cluster with 'kube-up.sh'"
  exit 1
fi
if [[ -z "${KUBE_MASTER_IP-}" ]]; then
  KUBE_MASTER_IP=$(get_instance_public_ip ${KUBE_MASTER_ID})
fi


# pods
printf "\nCreating pods ...\n"
kubernetes/cluster/kubectl.sh create -f pods/app-etcd.yaml

printf "\nWaiting for etcd cluster to initialise ...\n"
sleep 20
kubernetes/cluster/kubectl.sh create -f services/app-etcd.yaml

# config file adjustments
printf "\nAdjusting config files ..."

# gcloud compute ssh kubernetes-master --command "curl --silent -L http://localhost:8080/api/v1/proxy/namespaces/default/pods/app-etcd:2379/v2/keys/couchbase.com/userpass -X PUT -d value='$CBUSER:$CBPASSWORD'"

ssh -oStrictHostKeyChecking=no -i "${AWS_SSH_KEY}" ${SSH_USER}@${KUBE_MASTER_IP} "curl --silent -L http://localhost:8080/api/v1/proxy/namespaces/default/pods/app-etcd:2379/v2/keys/couchbase.com/userpass -X PUT -d value='$CBUSER:$CBPASSWORD'"

# Best practice to create pods/RC's before services
# replication-controllers
printf "\nCreating replication-controllers ...\n"
kubernetes/cluster/kubectl.sh create -f replication-controllers/couchbase-server.yaml
kubernetes/cluster/kubectl.sh create -f replication-controllers/couchbase-admin-server.yaml

# services
printf "\nCreating services ...\n"
kubernetes/cluster/kubectl.sh create -f services/couchbase-service.yaml
kubernetes/cluster/kubectl.sh create -f services/couchbase-admin-service.yaml

# firewall and forwarding-rules
# printf "\nCreating firewall and forwarding-rules ...\n"

# Done.
CBADMINIP=$(kubernetes/cluster/kubectl.sh get -o json service couchbase-admin-service | jsawk 'return this.status.loadBalancer.ingress[0].hostname')

# Can goto any k8s minion and get there, or go through the master
printf "\nDone.\n\n Go to http://$CBADMINIP:8091\n or \n http://<k8smaster>:8080/api/v1/proxy/namespaces/default/services/couchbase-admin-service:8091/".
