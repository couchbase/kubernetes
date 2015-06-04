#!/bin/bash

PROJECT_ID=[your project id]
ZONE=us-central1-f
REGION=us-central1
CLUSTER=[your cluster name]

# config
gcloud components update alpha
gcloud config set project $PROJECT_ID
gcloud config set compute/zone $ZONE
gcloud config set compute/region $REGION

gcloud compute forwarding-rules delete --quiet k8s-$CLUSTER
gcloud compute firewall-rules delete --quiet cbs-8091
gcloud compute firewall-rules delete --quiet cbs2-8091
gcloud compute firewall-rules delete --quiet k8s-$CLUSTER-all
gcloud compute firewall-rules delete --quiet k8s-$CLUSTER-master-https
gcloud compute firewall-rules delete --quiet k8s-$CLUSTER-vms
gcloud compute target-pools delete --quiet k8s-$CLUSTER
gcloud alpha container clusters delete --quiet $CLUSTER
