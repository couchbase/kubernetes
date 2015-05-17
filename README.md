
Here are instructions on getting Couchbase Server running under Kubernetes on GKE (Google Container Engine).  Very much still in progress.

## Logical Architecture

```
                ┌────────────────────────────────────────────────────────────────────┐                                                  
                │                   Google Container Engine (GKE)                    │                                                  
                │                                                                    │                                                  
                │                                                                    │                                                  
                │                                                                    │                                                  
┌────────┐      │               ┌──────────────────────────────────────────────────┐ │                                                  
│  REST  ├───┐  │               │                Kubernetes Cluster                │ │                                                  
│ Client │   │  │               │                                                  │ │                                                  
└────────┘   │  │ ┌──────────┐  │  ┌─────────────┐     ┌─────────┐      ┌────────┐ │ │                                                  
             └──┼─▶ external │  │  │sync-gateway │     │couchbase│      │  etcd  │ │ │                                                  
                │ │   load ──┼──┼─▶│   service   ├────▶│ service ├─────▶│service │ │ │                                                  
┌────────┐   ┌──┼─▶ balancer │  │  │             │     │         │      │        │ │ │                                                  
│  REST  │   │  │ └──────────┘  │  └─────────────┘     └─────────┘      └────────┘ │ │                                                  
│ Client ├───┘  │               │                                                  │ │                                                  
└────────┘      │               └──────────────────────────────────────────────────┘ │                                                  
                │                                                                    │                                                  
                └────────────────────────────────────────────────────────────────────┘                                                  

```

* Only the Sync Gateway (application tier) service is exposed to the outside world.
* Sync Gateway uses the Couchbase Server service as it's data storage tier
* The Couchbase Server service is only accessible from within the Kubernetes cluster, and is not exposed to the outside world.
* The etcd service is used by "sidekicks" that run in the Couchbase Server pod to bootstrap the cluster.  Likewise, it is only accessible within the cluster.  (NOTE: currently an external etcd service is being used in this README, but hopefully that will change)

## Physical Architecture

```

┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                        Kubernetes Cluster                                                        │
│                                                                                                                                  │
│ ┌──────────────────────────────────────────────────────────────────────┐  ┌──────────────────────────────────────────────────┐   │
│ │                          Kubernetes Node 1                           │  │                Kubernetes Node 2                 │   │
│ │ ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   ┌ ─ ─ ─ ─ ─ ─ ─ ─  │  │ ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │   │
│ │          Couchbase ReplicaSet (count=2)        │   CB etcd service │ │  │          Couchbase ReplicaSet (count=2)        │ │   │
│ │ │ ┌──────────────────────────────────────────┐    │                  │  │ │ ┌──────────────────────────────────────────┐   │   │
│ │   │        couchbase-replicaset-pod-1        │ │    ┌────────────┐ │ │  │   │        couchbase-replicaset-pod-2        │ │ │   │
│ │ │ │ ┌─────────────────┐ ┌───────────────────┐│    │ │etcd pod    │   │  │ │ │ ┌─────────────────┐ ┌───────────────────┐│   │   │
│ │   │ │couchbase-server │ │couchbase-sidekick ││ │    │            │ │ │  │   │ │couchbase-server │ │couchbase-sidekick ││ │ │   │
│ │ │ │ │    container    │ │     container     ││    │ │ ┌────────┐ │   │  │ │ │ │    container    │ │     container     ││   │   │
│ │   │ └─────────────────┘ └───────────────────┘│ │    │ │etcd    │ │ │ │  │   │ └─────────────────┘ └───────────────────┘│ │ │   │
│ │ │ └──────────────────────────────────────────┘    │ │ │containe│ │   │  │ │ └──────────────────────────────────────────┘   │   │
│ │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘    │ │r       │ │ │ │  │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘ │   │
│ │ ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │ │ └────────┘ │   │  │ ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │   │
│ │        Sync Gateway ReplicaSet (count=2)       │    └────────────┘ │ │  │        Sync Gateway ReplicaSet (count=2)       │ │   │
│ │ │ ┌──────────────────────────────────────────┐    └ ─ ─ ─ ─ ─ ─ ─ ─  │  │ │ ┌──────────────────────────────────────────┐   │   │
│ │   │         sync-gw-replicaset-pod-1         │ │                     │  │   │         sync-gw-replicaset-pod-2         │ │ │   │
│ │ │ │ ┌──────────────────────────────────────┐ │                       │  │ │ │ ┌──────────────────────────────────────┐ │   │   │
│ │   │ │             sync gateway             │ │ │                     │  │   │ │             sync gateway             │ │ │ │   │
│ │ │ │ │              container               │ │                       │  │ │ │ │              container               │ │   │   │
│ │   │ └──────────────────────────────────────┘ │ │                     │  │   │ └──────────────────────────────────────┘ │ │ │   │
│ │ │ └──────────────────────────────────────────┘                       │  │ │ └──────────────────────────────────────────┘   │   │
│ │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘                     │  │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘ │   │
│ └──────────────────────────────────────────────────────────────────────┘  └──────────────────────────────────────────────────┘   │
│                                                                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Install cloud-sdk

**Via docker container**

I installed the cloud-sdk within a Docker container in order to avoid worrying about getting into PDH (Python Dependency Hell).

```
$ docker pull google/cloud-sdk
$ docker run -ti google/cloud-sdk /bin/bash
# gcloud auth login
Go to the following link in your browser:
... etc
```

**Standard method**

```
$ curl https://sdk.cloud.google.com | bash
```

## Setup cloud-sdk

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

## Automated couchbase cluster setup

On etcd.couchbasemobile.com:

* `etcdctl rm --recursive /couchbase.com/couchbase-node-state`
* `etcdctl set /couchbase.com/userpass "user:passw0rd"`

**Note: you will need to setup and run your own etcd service and use this instead of etcd.couchbasemobile.com.  This will hopefully get fixed soon**

Kick off the replication controller:

```
$ gcloud alpha container kubectl create -f replication-controllers/couchbase-server.yaml
```


## Setup interaction

Here is what is happening under the hood with the couchbase sidekicks to bootstrap the cluster:

```
┌─────────────┐              ┌─────────────┐                  ┌─────────────┐            ┌─────────────┐
│  Couchbase  │              │  OS / libc  │                  │  Couchbase  │            │  Couchbase  │
│  Sidekick   │              │             │                  │    Etcd     │            │   Server    │
└──────┬──────┘              └──────┬──────┘                  └──────┬──────┘            └──────┬──────┘
       │                            │                                │                          │       
       │                            │                                │                          │       
       │      Get IP of first       │                                │                          │       
       ├────non-loopback iface──────▶                                │                          │       
       │                            │                                │                          │       
       │         Pod's IP           │                                │                          │       
       ◀─────────address────────────┤                                │                          │       
       │                            │                                │                          │       
       │                            │             Create             │                          │       
       ├────────────────────────────┼──────/couchbase-node-state─────▶                          │       
       │                            │               dir              │                          │       
       │                            │                                │                          │       
       │                            │           Success OR           │                          │       
       ◀────────────────────────────┼──────────────Fail──────────────┤                          │       
       │                            │                                │                          │       
       │                            │                                │         Create OR        │       
       ├────────────────────────────┼────────────────────────────────┼────────────Join ─────────▶       
       │                            │                                │          Cluster         │       
       │                            │                                │                          │       
       │                            │                                │     Add my pod IP under  │       
       ├────────────────────────────┼────────────────────────────────┼───────cbs-node-state─────▶       
       │                            │                                │                          │       
       │                            │                                │                          │       
       ▼                            ▼                                ▼                          ▼

```


## View container logs

First find the pod names that the replication controller spawned:

```
$ gcloud alpha container kubectl get pods
```

Under the POD column in the resulting table formatted output, you should see:

```
couchbase-controller-ho6ta
couchbase-controller-j7yzf
```

Now, to view the logs on all of the containers, run:

```
$ gcloud alpha container kubectl log couchbase-controller-ho6ta couchbase-server
$ gcloud alpha container kubectl log couchbase-controller-ho6ta couchbase-sidekick
$ gcloud alpha container kubectl log couchbase-controller-j7yzf couchbase-server
$ gcloud alpha container kubectl log couchbase-controller-j7yzf couchbase-sidekick
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

## Create a service for couchbase-server

```
$ gcloud alpha container kubectl create -f services/couchbase-service.yaml
```

## Create a Sync Gateway replication set

Sync Gateway is a server-side component for Couchbase Mobile which provides a REST API in front of Couchbase Server, which Couchbase Lite enabled mobile apps connect to in order to sync their data.

It provides a good example of setting up an application tier on top of Couchbase Server.

By default, it will use the sync gateway config in [`config/sync-gateway.config`](https://github.com/tleyden/couchbase-kubernetes/blob/master/config/sync-gateway.config) -- note that for the IP address of Couchbase Server, it uses the **service** address: `http://couchbase-service:8091`

To kick off a Sync Gateway replica set, run:

```
$ gcloud alpha container kubectl create -f replication-controllers/sync-gateway.yaml
```

## Create a publicly exposed Sync Gateway service

```
$ gcloud alpha container kubectl create -f services/sync-gateway.yaml
```

To find the IP address, run:

```
$ gcloud compute forwarding-rules list
```

and you should see:

```
NAME      REGION      IP_ADDRESS    IP_PROTOCOL TARGET
aa94f7752 us-central1 104.197.15.37 TCP         us-central1/targetPools/aa94f7752
```

where `104.197.15.37` is a publicly accessible IP.  To verify, from your local workstation or any machine connected to the internet, run:

```
$ curl 104.197.15.37:4984
```

and you should see:

```
{"couchdb":"Welcome","vendor":{"name":"Couchbase Sync Gateway","version":1},"version":"Couchbase Sync Gateway/HEAD(nobranch)(04138fd)"}
```

## Create an etcd pod/service


```
$ ssh into node
$ HostIP=`hostname -i`
$ docker run -d -p 2380:2380 -p 2379:2379  --name etcd quay.io/coreos/etcd:v2.0.8 -name etcd0 -listen-client-urls http://0.0.0.0:2379 -advertise-client-urls http://${HostIP}:2379
```

Not working yet, see [using etcd google groups post](https://groups.google.com/d/msg/google-containers/rFIFD6Y0_Ew/GeDa8ZuPWd8J)

```
$ gcloud alpha container kubectl create -f pods/etcd.yaml

```


## Todo

* Use local etcd rather than external etcd
* Improve story with pod termination -- add a shutdown hook
* What happens if you terminate a couchbase server pod?
    * New pod comes up with different ip
    * Rebalance fails because there are now 3 couchbase server nodes, one which is unreachable
    * To manually fix: fail over downed cb node, kick off rebalance
* Look into host mounted volumes


## References

* [Couchbase Docker image on Dockerhub](https://hub.docker.com/u/couchbase/server)

* [Google cloud sdk](https://registry.hub.docker.com/u/google/cloud-sdk/)

* https://cloud.google.com/container-engine/docs/hello-wordpress

* https://cloud.google.com/container-engine/docs/guestbook
