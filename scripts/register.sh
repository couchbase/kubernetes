#!/bin/bash

PROJECT_ID=[your project id]
ZONE=us-central1-f
REGION=us-central1
CLUSTER=[your cluster name]

CBUSER=user
CBPASSWORD=passw0rd

# config
gcloud components update alpha
gcloud config set project $PROJECT_ID
gcloud config set compute/zone $ZONE
gcloud config set compute/region $REGION

gcloud alpha container clusters create $CLUSTER \
    --num-nodes 2 \
    --quiet \
    --machine-type g1-small

kubectl config use-context gke_erudite-pride-94911_us-central1-f_$CLUSTER
gcloud config set container/cluster $CLUSTER


# pods
printf "\nCreating pods ...\n"
kubectl create -f pods/app-etcd.json

printf "\nWaiting for cluster to initialise ...\n"
sleep 200

# config file adjustments
printf "\nAdjusting config files ..."
PODIP=$(kubectl get -o json pod app-etcd | jsawk 'return this.status.podIP')
sleep 5
ETCDHOST=$(kubectl get -o json pod app-etcd | jsawk 'return this.spec.host')

sed -i'.bak' "s/etcd.pod.ip/$PODIP/" replication-controllers/couchbase.controller.json

gcloud --quiet compute ssh $ETCDHOST --command "curl --silent -L http://$PODIP:2379/v2/keys/couchbase.com/userpass -X PUT -d value='$CBUSER:$CBPASSWORD'"

NODE1=$(gcloud compute instances list --format json | ./nodes.js | awk 'NR==1{print $1}')
NODE2=$(gcloud compute instances list --format json | ./nodes.js | awk 'NR==2{print $1}')

# services
printf "\nCreating services ...\n"
kubectl create -f services/couchbase.service.json


# replication-controllers
printf "\nCreating replication-controllers ...\n"
kubectl create -f replication-controllers/couchbase.controller.json


# firewall and forwarding-rules
printf "\nCreating firewall and forwarding-rules ...\n"
gcloud compute instances add-tags $NODE1 --tags cb1
gcloud compute firewall-rules create cbs-8091 --allow tcp:8091 --target-tags cb1
gcloud compute instances add-tags $NODE2 --tags cb2
gcloud compute firewall-rules create cbs2-8091 --allow tcp:8091 --target-tags cb2

# reset config file for next run
printf "\nResetting config files for next run ...\n"
rm replication-controllers/couchbase.controller.json
mv replication-controllers/couchbase.controller.json.bak replication-controllers/couchbase.controller.json

# Done.
CBNODEIP=$(gcloud compute instances describe $NODE1 --format json | jsawk 'return this.networkInterfaces[0].accessConfigs[0].natIP')

printf "\nDone\n\n. Go to http://$CBNODEIP:8091\n\n".
