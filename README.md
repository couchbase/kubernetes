
Here are instructions on getting Couchbase Server and Couchbase Sync Gateway running under Kubernetes on GKE (Google Container Engine).  

# Logical Architecture

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
* The etcd service is used by "sidekicks" that run in the Couchbase Server pod to bootstrap the cluster.  Likewise, it is only accessible within the cluster.

# Physical Architecture

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

# Google Container Engine / Kubernetes setup

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

# Couchbase Server + Sync Gateway 

## Clone couchbase-kubernetes

```
$ git clone https://github.com/tleyden/couchbase-kubernetes.git
$ cd couchbase-kubernetes
```

## Start etcd Pod

Although Kubernetes runs its own etcd, this is not accessible to applications running within Kubernetes.  The Couchbase sidekick containers require etcd to discover Couchbase Server Nodes and bootstrap the cluster.

The current recommended approach is to either:

1. Run your own etcd cluster *outside* the Kubernetes cluster, and setup secure networking between the two (you don't want to expose your etcd cluster publicly)
1. Start up a single node etcd within the Kubernetes cluster.

Running your own separate etcd cluster is outside the scope of this document, so we'll ignore that option for now and focus on the other option.

The downside with running a single etcd node within Kubernetes has the major disadvantage of being a single point of failure, nor will it handle pod restarts of the etcd pod -- if that pod is restarted and gets a new ip address, then future couchbase nodes that are started won't be able to find etcd and auto-join the cluster.

Having said that, here's how to start the app-etcd Pod:

```
$ gcloud alpha container kubectl create -f pods/app-etcd.yaml
```

Get the pod ip:

```
$ gcloud alpha container kubectl get pod app-etcd
```

you should see:

```
POD        IP            CONTAINER(S)   IMAGE(S)                     HOST                  ...
app-etcd   10.248.1.30   app-etcd       tleyden5iwx/etcd-discovery   k8s.../104.197.79.56  ...
```

Make a note of the Pod IP (10.248.1.30 in above example).  Side note -- app-etcd *should* be wrapped up a in a service, but that is still in progress.  See this [google groups post](https://groups.google.com/d/msg/google-containers/rFIFD6Y0_Ew/GeDa8ZuPWd8J).

## Modify Couchbase Server Replication Controller

Modify your couchbase-server replication controller to have the etcd Pod IP:

```
$ sed -i .bak 's/etcd.pod.ip/10.248.1.30/' replication-controllers/couchbase-server.yaml
```

Replacing `10.248.1.30` with your actual Pod IP found in the previous step.

## Add Couchbase Server Admin credentials in etcd

First, you will need to ssh into a node on your kubernetes cluster:

```
$ gcloud compute ssh k8s-couchbase-server-node-1
```

Next, use curl to add a value for the `/couchbase.com/userpass` key.  Replace `user:passw0rd` with the actual values you want to use.  

```
root@k8s~$ curl -L http://10.248.1.30:2379/v2/keys/couchbase.com/userpass -X PUT -d value="user:passw0rd"
```

## Kick off Service and Replication Controller for couchbase-server

First the service:

```
$ gcloud alpha container kubectl create -f services/couchbase-service.yaml
```

Then the replication controller:

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

View the logs on all of the containers via:

```
$ gcloud alpha container kubectl log couchbase-controller-ho6ta couchbase-server
$ gcloud alpha container kubectl log couchbase-controller-ho6ta couchbase-sidekick
$ gcloud alpha container kubectl log couchbase-controller-j7yzf couchbase-server
$ gcloud alpha container kubectl log couchbase-controller-j7yzf couchbase-sidekick
```

## Expose port 8091 to public IP

In order to access port 8091 from the outside world, you will need to add firewall rules to expose it.  While this isn't strictly necessary, it make administration much easier.  Rather than allowing blanket access, it would be possible to lock down access to a specific ip or range of ip addresses.

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

At this point, you should find the public IP of one your nodes by running `gcloud compute instances list` and looking for the EXTERNAL_IP (ignore the `k8s-couchbase-server-master` entry in that list).

Now visit public-ip:8091 in your browser, and you should see:

![Couchbase Login Screen](http://tleyden-misc.s3.amazonaws.com/blog_images/couchbase_cluster_login.png)

Login with the credentials used above in place of `user:passw0rd`

## Create a Sync Gateway replication set

Sync Gateway is a server-side component for Couchbase Mobile which provides a REST API in front of Couchbase Server, which Couchbase Lite enabled mobile apps connect to in order to sync their data.

It provides a good example of setting up an application tier on top of Couchbase Server.  If you were creating a tier of webservers that used a Couchbase SDK to store data in Couchbase Server, you're architecture would be very similar to this.

To kick off a Sync Gateway replica set, run:

```
$ gcloud alpha container kubectl create -f replication-controllers/sync-gateway.yaml
```

By default, it will use the sync gateway config in [`config/sync-gateway.config`](https://github.com/tleyden/couchbase-kubernetes/blob/master/config/sync-gateway.config) -- note that for the IP address of Couchbase Server, it uses the **service** address: `http://couchbase-service:8091`

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

Congrats!  You are now running Couchbase Server and Sync Gateway on Kubernetes.

## TODO

* Improve story with pod termination -- add a shutdown hook
* Wrap etcd in a service 
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
