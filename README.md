
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

## Install kubectl

In order to avoid typing `gcloud alpha container kubectl` for every command, and just typing `kubectl`, you will need to install `kubectl`.  You will also need `jsawk`.

On OSX, you can install these tools via:

```
$ brew install kubectl
$ brew install jsawk
```
The rest of the document will assume you have `kubectl` installed.  Otherwise, you can run the `kubectl` commands by running `gcloud alpha container kubectl` instead.

## Pass credentials to kubectl

If your cluster was not created with the gcloud alpha container command (i.e. you created it through the Developers Console), or you created it with gcloud from a different machine, you'll need to run an additional command to make your credentials available to kubectl. Your default zone and cluster must be already set or should be passed as flags to the command.

```
$ gcloud alpha container get-credentials
    [--zone ZONE] [--cluster CLUSTER_NAME]
```

You only need to run this once per cluster per machine (e.g. if you created your cluster from your laptop, you'll need to run get-credentials on your desktop before you're able to access the cluster from that machine.)

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
*Don't use* `--machine-type f1-micro` *as it isn't powerful enough to complete the bootstrap process*

Set your default cluster:

```
$ gcloud config set container/cluster couchbase-server
```

# Couchbase Server + Sync Gateway

## Clone couchbase-kubernetes

```
$ git clone https://github.com/couchbase/kubernetes.git couchbase-kubernetes
$ cd couchbase-kubernetes
```

## Start etcd 

Although Kubernetes runs its own etcd, this is not accessible to applications running within Kubernetes.  The Couchbase sidekick containers require etcd to discover Couchbase Server Nodes and bootstrap the cluster.

The current recommended approach is to either:

1. Run your own etcd cluster *outside* the Kubernetes cluster, and setup secure networking between the two (you don't want to expose your etcd cluster publicly)
1. Start up a single node etcd within the Kubernetes cluster.

Running your own separate etcd cluster is outside the scope of this document, so we'll ignore that option for now and focus on the other option.

The downside with running a single etcd node within Kubernetes has the major disadvantage of being a single point of failure, nor will it handle pod restarts of the etcd pod -- if that pod is restarted and gets a new ip address, then future couchbase nodes that are started won't be able to find etcd and auto-join the cluster.

Having said that, here's how to start the app-etcd service and pod:

```
$ kubectl create -f services/app-etcd.yaml
$ kubectl create -f pods/app-etcd.yaml
```

Get the pod ip:

```
$ kubectl get pod app-etcd
```

you should see:

```
POD        IP            CONTAINER(S)   IMAGE(S)                     HOST                               ...
app-etcd   10.248.1.30   app-etcd       tleyden5iwx/etcd-discovery   k8s-couchbase-server-node-2/104..  ...
```

Make a note of the Host it's running on (eg, k8s-couchbase-server-node-2)

## Add Couchbase Server Admin credentials in etcd

First, you will need to ssh into the host node where the app-etcd pod is running:

```
$ gcloud compute ssh k8s-couchbase-server-node-2
```

Replace `k8s-couchbase-server-node-2` with the host found in the previous step.

Next, use curl to add a value for the `/couchbase.com/userpass` key in etcd.  

```
root@k8s~$ curl -L http://10.248.1.30:2379/v2/keys/couchbase.com/userpass -X PUT -d value="user:passw0rd"
```

Replace `user:passw0rd` with the actual values you want to use.  

## Kick off Service and Replication Controller for couchbase-server

First the service:

```
$ kubectl create -f services/couchbase-service.yaml
```

Then the replication controller:

```
$ kubectl create -f replication-controllers/couchbase-server.yaml
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
$ kubectl get pods
```

Under the POD column in the resulting table formatted output, you should see:

```
couchbase-controller-ho6ta
couchbase-controller-j7yzf
```

View the logs on all of the containers via:

```
$ kubectl logs couchbase-controller-ho6ta couchbase-server
$ kubectl logs couchbase-controller-ho6ta couchbase-sidekick
$ kubectl logs couchbase-controller-j7yzf couchbase-server
$ kubectl logs couchbase-controller-j7yzf couchbase-sidekick
```

* Expected [couchbase-server logs](https://gist.github.com/tleyden/b9677515952fa054ddd2)
* Expected [couchbase-sidekick logs](https://gist.github.com/tleyden/269679e71131b7e8536e)

## Expose port 8091 to public IP

In order to access port 8091 from the outside world, you will need to add firewall rules to expose it.  While this isn't strictly necessary, it make administration much easier.  Rather than allowing blanket access, it would be possible to lock down access to a specific ip or range of ip addresses.

**Find instances**

```
$ gcloud compute instances list
```

You should see:

```
NAME                        ZONE          MACHINE_TYPE INTERNAL_IP    EXTERNAL_IP    STATUS
k8s-couchbase-server-master us-central1-b g1-small     10.240.190.47  104.197.76.201 RUNNING
k8s-couchbase-server-node-1 us-central1-b g1-small     10.240.23.227  104.197.79.56  RUNNING
k8s-couchbase-server-node-2 us-central1-b g1-small     10.240.164.118 146.148.57.164 RUNNING
```

The two we care about are `k8s-couchbase-server-node-1` and `k8s-couchbase-server-node-2`.

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

At this point, you should find the public IP of either one your from the `gcloud compute instances list` command and looking for the EXTERNAL_IP.

Now visit public-ip:8091 in your browser, and you should see:

![Couchbase Login Screen](http://tleyden-misc.s3.amazonaws.com/blog_images/couchbase_cluster_login.png)

Login with the credentials used above in place of `user:passw0rd`

## Create a Sync Gateway replication set

Sync Gateway is a server-side component for Couchbase Mobile which provides a REST API in front of Couchbase Server, which Couchbase Lite enabled mobile apps connect to in order to sync their data.

It provides a good example of setting up an application tier on top of Couchbase Server.  If you were creating a tier of webservers that used a Couchbase SDK to store data in Couchbase Server, your architecture would be very similar to this.

To kick off a Sync Gateway replica set, run:

```
$ kubectl create -f replication-controllers/sync-gateway.yaml
```

By default, it will use the sync gateway config in [`config/sync-gateway.config`](https://github.com/tleyden/couchbase-kubernetes/blob/master/config/sync-gateway.config) -- note that for the IP address of Couchbase Server, it uses the **service** address: `http://couchbase-service:8091`

## Create a publicly exposed Sync Gateway service

```
$ kubectl create -f services/sync-gateway.yaml
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

where `104.197.15.37` is a publicly accessible IP.  To verify, from your local workstation or any machine connected to the internet, wait for a few minutes to give it a chance to startup, and then run:

```
$ curl 104.197.15.37:4984
```

and you should see:

```
{"couchdb":"Welcome","vendor":{"name":"Couchbase Sync Gateway","version":1},"version":"Couchbase Sync Gateway/HEAD(nobranch)(04138fd)"}
```

Congrats!  You are now running Couchbase Server and Sync Gateway on Kubernetes.

## TODO

* Run this on a different Kubernetes environment other than GKE.
* Improve the story when Pods go down.  Currently some manual intervention is needed to rebalance the cluster, ideally I'd like this to be fully automated.  (possibly via pod shutdown hook).  Currently:
    * New pod comes up with different ip
    * Rebalance fails because there are now 3 couchbase server nodes, one which is unreachable
    * To manually fix: fail over downed cb node, kick off rebalance
* Improve the story on the "app-etcd" (I need my own etcd running to bootstrap the Couchbase cluster with, since the Kubernetes etcd is off-limits).  The instructions currently make the user go find the pod IP where etcd is running, and enter that in their config.  I'm hoping to get feedback from Kelsey or others on this [google groups post](https://groups.google.com/forum/#!msg/google-containers/rFIFD6Y0_Ew/PlYh0z7weLEJ) to get etcd wrapped up into a Kubernetes service.
* Look into host mounted volumes


## References

* [Couchbase Docker image on Dockerhub](https://hub.docker.com/u/couchbase/server)

* [Google cloud sdk](https://registry.hub.docker.com/u/google/cloud-sdk/)

* https://cloud.google.com/container-engine/docs/hello-wordpress

* https://cloud.google.com/container-engine/docs/guestbook

* [google groups post regarding etcd service](https://groups.google.com/d/msg/google-containers/rFIFD6Y0_Ew/GeDa8ZuPWd8J).
