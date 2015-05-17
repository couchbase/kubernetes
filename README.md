
Here are instructions on getting Couchbase Server running under Kubernetes on GKE (Google Container Engine).  Very much still in progress.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐                          
│                            Kubernetes Cluster                            │                          
│                                                                          │                          
│ ┌──────────────────────────────────────────────────────────────────────┐ │                          
│ │                          Kubernetes Node 1                           │ │                          
│ │ ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   ┌ ─ ─ ─ ─ ─ ─ ─ ─  │ │                          
│ │          Couchbase ReplicaSet (count=2)        │   CB etcd service │ │ │                          
│ │ │ ┌──────────────────────────────────────────┐    │/ RS3             │ │                          
│ │   │        couchbase-replicaset-pod-1        │ │    ┌────────────┐ │ │ │                          
│ │ │ │ ┌─────────────────┐ ┌───────────────────┐│    │ │etcd pod    │   │ │                          
│ │   │ │couchbase-server │ │couchbase-sidekick ││ │    │            │ │ │ │                          
│ │ │ │ │    container    │ │     container     ││    │ │ ┌────────┐ │   │ │                          
│ │   │ │                 │ │                   ││ │    │ │etcd    │ │ │ │ │                          
│ │ │ │ │                 │ │                   ││    │ │ │containe│ │   │ │                          
│ │   │ │                 │ │                   ││ │    │ │r       │ │ │ │ │                          
│ │ │ │ └─────────────────┘ └───────────────────┘│    │ │ └────────┘ │   │ │                          
│ │   └──────────────────────────────────────────┘ │    └────────────┘ │ │ │                          
│ │ └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   └ ─ ─ ─ ─ ─ ─ ─ ─  │ │                          
│ └──────────────────────────────────────────────────────────────────────┘ │                          
│                                                                          │                          
│ ┌──────────────────────────────────────────────────────────────────────┐ │                          
│ │                          Kubernetes Node 2                           │ │                          
│ │ ┌ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   ┌ ─ ─ ─ ─ ─ ─ ─ ─  │ │                          
│ │          Couchbase ReplicaSet (count=2)        │   CB etcd service │ │ │                          
│ │ │ ┌──────────────────────────────────────────┐    │/ RS3             │ │                          
│ │   │        couchbase-replicaset-pod-2        │ │    ┌────────────┐ │ │ │                          
│ │ │ │ ┌─────────────────┐ ┌──────────────────┐ │    │ │etcd pod    │   │ │                          
│ │   │ │couchbase-server │ │couchbase-sidekick│ │ │    │ ┌────────┐ │ │ │ │                          
│ │ │ │ │    container    │ │    container     │ │    │ │ │etcd    │ │   │ │                          
│ │   │ │                 │ │                  │ │ │    │ │containe│ │ │ │ │                          
│ │ │ │ │                 │ │                  │ │    │ │ │r       │ │   │ │                          
│ │   │ │                 │ │                  │ │ │    │ │        │ │ │ │ │                          
│ │ │ │ └─────────────────┘ └──────────────────┘ │    │ │ └────────┘ │   │ │                          
│ │   └──────────────────────────────────────────┘ │    └────────────┘ │ │ │                          
│ │ └ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   └ ─ ─ ─ ─ ─ ─ ─ ─  │ │                          
│ └──────────────────────────────────────────────────────────────────────┘ │                          
└──────────────────────────────────────────────────────────────────────────┘                          
```

## Setup interaction

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

## Create an etcd pod/service

Not working yet, see [using etcd google groups post](https://groups.google.com/d/msg/google-containers/rFIFD6Y0_Ew/GeDa8ZuPWd8J)

```
$ gcloud alpha container kubectl create -f pods/etcd.yaml

```


## Todo

* Setup EXTERNAL sync gateway service and expose it
* Use local etcd rather than external etcd
* Look into host mounted volumes


## References

* [Couchbase Docker image on Dockerhub](https://hub.docker.com/u/couchbase/server)

* [Google cloud sdk](https://registry.hub.docker.com/u/google/cloud-sdk/)

* https://cloud.google.com/container-engine/docs/hello-wordpress

* https://cloud.google.com/container-engine/docs/guestbook
