
Here are instructions on getting Couchbase Server running under Kubernetes on GKE (Google Container Engine).  Very much still in progress, and I'm doing things against the grain on purpose so I can learn more about what's under the hood in Kubernetes.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────┐                                      
│                                 Kubernetes Cluster                                  │                                      
│                                                                                     │                                      
│ ┌─────────────────────────────────────────────────────────────────────────────────┐ │                                      
│ │                                Kubernetes Node 1                                │ │                                      
│ │ ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐  ┌ ─ ─ ─ ─ ─ ─ ─ ─   ┌ ─ ─ ─ ─ ─ ─ ─ ─  │ │                                      
│ │          Couchbase ReplicaSet             CB etcd service │   pod-reflector   │ │ │                                      
│ │ │ ┌─────────────────────────────────┐ │  │/ RS3              │HDLS SVC / RS1    │ │                                      
│ │   │         couchbase-pod-1         │      ┌────────────┐ │    ┌────────────┐ │ │ │                                      
│ │ │ │ ┌─────────────┐ ┌─────────────┐ │ │  │ │etcd pod    │    │ │pod-reflecto│   │ │                                      
│ │   │ │couchbase-con│ │couchbase-sid│ │      │            │ │    │r pod       │ │ │ │                                      
│ │ │ │ │tainer-1     │ │ekick-contain│ │ │  │ │ ┌────────┐ │    │ │ ┌────────┐ │   │ │                                      
│ │   │ │             │ │er-1         │ │      │ │etcd    │ │ │    │ │pod-refl│ │ │ │ │                                      
│ │ │ │ │             │ │             │ │ │  │ │ │containe│ │    │ │ │ector   │ │   │ │                                      
│ │   │ │             │ │             │ │      │ │r       │ │ │    │ │containe│ │ │ │ │                                      
│ │ │ │ └─────────────┘ └─────────────┘ │ │  │ │ └────────┘ │    │ │ └────────┘ │   │ │                                      
│ │   └─────────────────────────────────┘      └────────────┘ │    └────────────┘ │ │ │                                      
│ │ └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘  └ ─ ─ ─ ─ ─ ─ ─ ─   └ ─ ─ ─ ─ ─ ─ ─ ─  │ │                                      
│ └─────────────────────────────────────────────────────────────────────────────────┘ │                                      
│                                                                                     │                                      
│ ┌─────────────────────────────────────────────────────────────────────────────────┐ │                                      
│ │                                Kubernetes Node 2                                │ │                                      
│ │ ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐  ┌ ─ ─ ─ ─ ─ ─ ─ ─                      │ │                                      
│ │          Couchbase ReplicaSet             CB etcd service │                     │ │                                      
│ │ │ ┌─────────────────────────────────┐ │  │/ RS3                                 │ │                                      
│ │   │         couchbase-pod-2         │      ┌────────────┐ │                     │ │                                      
│ │ │ │ ┌─────────────┐ ┌─────────────┐ │ │  │ │etcd pod    │                       │ │                                      
│ │   │ │couchbase-con│ │couchbase-sid│ │      │ ┌────────┐ │ │                     │ │                                      
│ │ │ │ │tainer-2     │ │ekick-contain│ │ │  │ │ │etcd    │ │                       │ │                                      
│ │   │ │             │ │er-2         │ │      │ │containe│ │ │                     │ │                                      
│ │ │ │ │             │ │             │ │ │  │ │ │r       │ │                       │ │                                      
│ │   │ │             │ │             │ │      │ │        │ │ │                     │ │                                      
│ │ │ │ └─────────────┘ └─────────────┘ │ │  │ │ └────────┘ │                       │ │                                      
│ │   └─────────────────────────────────┘      └────────────┘ │                     │ │                                      
│ │ └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘  └ ─ ─ ─ ─ ─ ─ ─ ─                      │ │                                      
│ └─────────────────────────────────────────────────────────────────────────────────┘ │                                      
└─────────────────────────────────────────────────────────────────────────────────────┘                                      

```

## Setup interaction

```
┌─────────────┐               ┌─────────────┐            ┌─────────────┐             ┌─────────────┐            ┌─────────────┐
│  Couchbase  │               │   K8s API   │            │Pod Reflector│             │  Couchbase  │            │Couchbase (in│
│  Sidekick   │               │             │            │  REST API   │             │    Etcd     │            │sidekick pod)│
└──────┬──────┘               └──────┬──────┘            └──────┬──────┘             └──────┬──────┘            └──────┬──────┘
       │         Get IP of           │                          │                           │                          │       
       │            Pod              │                          │                           │                          │       
       ├─────────Reflector ──────────▶                          │                           │                          │       
       │            pod              │                          │                           │                          │       
       │                             │                          │                           │                          │       
       ◀──────────PR IP──────────────┤                          │                           │                          │       
       │                             │                          │                           │                          │       
       │                             │        What's my         │                           │                          │       
       ├─────────────────────────────┼─────────pod IP?──────────▶                           │                          │       
       │                             │                          │                           │                          │       
       │                             │        Your pod          │                           │                          │       
       ◀─────────────────────────────┼───────────IP─────────────┤                           │                          │       
       │                             │                          │                           │                          │       
       │                             │                          │          Create           │                          │       
       ├─────────────────────────────┼──────────────────────────┼───/couchbase-node-state───▶                          │       
       │                             │                          │            dir            │                          │       
       │                             │                          │                           │                          │       
       │                             │                          │        Success OR         │                          │       
       ◀─────────────────────────────┼──────────────────────────┼───────────Fail────────────┤                          │       
       │                             │                          │                           │                          │       
       │                             │                          │                           │       Create OR          │       
       ├─────────────────────────────┼──────────────────────────┼───────────────────────────┼──────────Join ───────────▶       
       │                             │                          │                           │        Cluster           │       
       │                             │                          │    Add my pod IP under    │                          │       
       ├─────────────────────────────┼──────────────────────────┼───────cbs-node-state──────▶                          │       
       │                             │                          │                           │                          │       
       │                             │                          │                           │                          │       
       │                             │                          │                           │                          │       
       │                             │                          │                           │                          │       
       ▼                             ▼                          ▼                           ▼                          ▼       

```

## Install docker container with cloud-sdk

I recommend installing the cloud-sdk within a Docker container so you don't have to worry about getting into PDH (Python Dependency Hell) on your workstation.  However, if you already have it installed or are confident installing it on your workstation, skip this step.

```
$ docker pull google/cloud-sdk
$ docker run -ti google/cloud-sdk /bin/bash
# gcloud auth login
Go to the following link in your browser:
... etc
```

Now enable the alpha components:

```
$ gcloud components update alpha
```

And set the zone:

```
$ gcloud config set compute/zone us-central1-b
```

## Create a new project

Go to the [New Project](https://console.developers.google.com/project) page on Google Compute Engine and create a new project called `couchbase-container`.

```
$ gcloud config set project couchbase-container
```

Verify this worked by trying to list the instances (should be empty)

```
$ gcloud compute instances list
NAME ZONE MACHINE_TYPE INTERNAL_IP EXTERNAL_IP STATUS
```

## Create a cluster

```
$ gcloud alpha container clusters create couchbase-server \
    --num-nodes 2 \
    --machine-type g1-small
```

Set your default cluster:

```
$ gcloud config set container/cluster couchbase-server
```

## Clone couchbase-kubernetes

```
$ git clone https://github.com/tleyden/couchbase-kubernetes.git
$ cd couchbase-kubernetes
```

## Create an etcd pod/service

Not working yet, see [using etcd google groups post](https://groups.google.com/d/msg/google-containers/rFIFD6Y0_Ew/GeDa8ZuPWd8J)

```
$ gcloud alpha container kubectl create -f pods/etcd.yaml

```

## Create couchbase server replication controller

```
$ gcloud alpha container kubectl create -f replication-controllers/couchbase-server.yaml
```

## Expose port 8091 to public IP

**First couchbase server node**

```
$ gcloud compute instances add-tags k8s-couchbase-server-node-1 --tags cb1
$ gcloud compute firewall-rules create cbs-8091 --allow tcp:8091 --target-tags cb1
```

**Second couchbase server node**

```
$ gcloud compute instances add-tags k8s-couchbase-server-node-2 --tags cb2
$ gcloud compute firewall-rules create cbs2-8091 --allow tcp:8091 --target-tags cb2
```

## Create a service

```
$ wget https://raw.githubusercontent.com/tleyden/couchbase-kubernetes/master/services/cbs-service-1.yaml
$ gcloud alpha container kubectl create -f cbs-service-1.yaml
```


## Find internal routable IP addresses of pods

```
$ gcloud alpha container kubectl get pods
POD                                                   IP           CONTAINER(S)              IMAGE(S)                                                                            HOST                                        LABELS                                                              STATUS    CREATED
couchbase-server                                      10.248.1.3   couchbase-server          couchbase/server                                                                    k8s-couchbase-server-node-1/104.197.79.56   <none>                                                              Running   22 minutes
couchbase-server2                                     10.248.2.4   couchbase-server2         couchbase/server                                                                    k8s-couchbase-server-node-2/146.148.85.81   <none>                                                              Running   20 minutes
```

So 10.248.1.3 and 10.248.2.4 are the routable IP addresses of the two pods.

## Ssh into one of the GCE instances

First get the instance name via:

```
$ gcloud compute instances list
```

Then ssh:

```
$ gcloud compute ssh k8s-couchbase-server-node-1
```

## Setup Couchbase server cluster

```
root@k8s:~$ container_1_private_ip=10.248.1.3; container_2_private_ip=10.248.2.4
root@k8s:~$ docker run --entrypoint=/opt/couchbase/bin/couchbase-cli couchbase/server \
cluster-init -c $container_1_private_ip \
--cluster-init-username=Administrator \
--cluster-init-password=password \
--cluster-init-ramsize=600 \
-u admin -p password
```

**Create a bucket**

```
root@k8s:~$ docker run --entrypoint=/opt/couchbase/bin/couchbase-cli couchbase/server \
bucket-create -c $container_1_private_ip:8091 \
--bucket=default \
--bucket-type=couchbase \
--bucket-port=11211 \
--bucket-ramsize=600 \
--bucket-replica=1 \
-u Administrator -p password
```

**Add second Couchbase server node + rebalance**

```
root@k8s:~$ docker run --entrypoint=/opt/couchbase/bin/couchbase-cli couchbase/server \
rebalance -c $container_1_private_ip \
-u Administrator -p password \
--server-add $container_2_private_ip \
--server-add-username Administrator \
--server-add-password password
```

## Automated couchbase cluster setup (in progress)

See https://github.com/GoogleCloudPlatform/kubernetes/blob/master/examples/rethinkdb/image/run.sh example

* Start a headless service called couchbase-cluster
* Sidekick
    * Spins up docker image with couchcbase-cluster-go installed
    * Start script gets hostname via MYHOST=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
    * Start script calls couchbase-cluster-go binary and passes hostname argument, and etcd server list as ec2-54-204-147-145.compute-1.amazonaws.com:4001

Tried this, but there was a problem.  The host in MYHOST was not the same as the pod ip.  Got error:

2015/05/11 01:43:20 Got error Get http://10.248.1.11:8091/pools: dial tcp 10.248.1.11:8091: connection refused trying to fetch details.  Assume that the cluster is not up yet, sleeping and will retry



## Todo

* How can I use DNS hostnames instead of hardcoded private IPs for couchbase server nodes to see eachother?
    * Looks like these already get predefined
            * k8s-couchbase-server-node-1
	      * k8s-couchbase-server-node-2
	      * Is it possible to expose Couchbase Server as a "service" to Sync Gateway?
	      * Replace individual pods with a Replication Controller

## Sidekick steps


Kick off sidekick:

```
docker run --name couchbase-sidekick --net=host tleyden5iwx/couchbase-cluster-go update-wrapper couchbase-cluster start-couchbase-sidekick --discover-local-ip
```

## References

* [Google cloud sdk](https://registry.hub.docker.com/u/google/cloud-sdk/)

* https://cloud.google.com/container-engine/docs/hello-wordpress

* https://cloud.google.com/container-engine/docs/guestbook
