
**DEPRECATED** -- See [Couchbase Operator](https://blog.couchbase.com/introducing-couchbase-operator/)

--------------------------------------


Here are instructions on getting Couchbase Server and Couchbase Sync Gateway running under Kubernetes on GKE (Google Container Engine).  

To get a bird's eye view of what is being created, check the following [Architecture Diagrams](https://github.com/couchbase/kubernetes/wiki/Architecture-Diagrams)

# Kubernetes cluster setup

First you need to setup Kubernetes itself before running Couchbase on it.  These instructions are specific to your particular setup (bare metal or Cloud Provider).

# Couchbase Server

## Install Dependencies

* [Google Container Engine tools](https://github.com/couchbase/kubernetes/wiki/Running-on-Google-Container-Engine-(GKE))

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

Here's how to start the app-etcd service and pod:

```
$ kubectl create -f services/app-etcd.yaml
$ kubectl create -f pods/app-etcd.yaml
```

Get the pod ip:

```
$ kubectl describe pod app-etcd
```

you should see:

```
Name:				app-etcd
Namespace:			default
Image(s):			tleyden5iwx/etcd-discovery
Node:				gke-couchbase-server-648006db-node-qgu2/10.240.158.17
Labels:				name=app-etcd
Status:				Running
Reason:
Message:
IP:				10.248.1.5
```

Make a note of the Node it's running on (eg, gke-couchbase-server-648006db-node-qgu2) as well as the Pod IP (10.248.1.5)

## Add Couchbase Server Admin credentials in etcd


First, you will need to ssh into the host node where the app-etcd pod is running (or any other node in the cluster):


( Alternatively on linux and mac you can use this one liner )

```
kubectl describe pod app-etcd | grep Node | awk '{print $2}'| sed 's/\/.*//'
```

```
$ gcloud compute ssh gke-couchbase-server-648006db-node-qgu2
```

Replace `gcloud compute ssh gke-couchbase-server-648006db-node-qgu2` with the host found in the previous step.

Next, use curl to add a value for the `/couchbase.com/userpass` key in etcd.  Use the Pod IP found above.  

( Alternatively on linux and mac you can use this one liner to get the IP )

```
kubectl describe pod app-etcd | grep IP: | awk '{print $2}'
```

```
root@k8s~$ curl -L http://10.248.1.5:2379/v2/keys/couchbase.com/userpass -X PUT -d value="user:passw0rd"
```

Replace `user:passw0rd` with the actual values you want to use.

After you run the command, exit the SSH session to get back to your workstation.

```
$ exit 
```

## Kick off Service and Replication Controller for couchbase-server

First the replication controllers:
```
$ kubectl create -f replication-controllers/couchbase-admin-server.yaml
$ kubectl create -f replication-controllers/couchbase-server.yaml
```

Then the services:

```
$ kubectl create -f services/couchbase-service.yaml
$ kubectl create -f services/couchbase-admin-service.yaml
```

The `couchbase-admin` pod and service creates a couchbase server with an externally accessible admin ui. The admin replication controller (named `couchbase-admin-controller`) should never be scaled passed 1. Instead the `couchbase-controller` can be scaled to any desired number of replicas. The `couchbase-service` is configured to route traffic to both the `couchbase-admin-server` pod and the `couchbase-server` pods. 

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

Under the POD column in the resulting table formatted output, you should see pods similar to:

```
couchbase-admin-controller-ho6ta
couchbase-controller-j7yzf
```

View the logs on all of the containers via:

```
$ kubectl logs couchbase-admin-controller-ho6ta couchbase-server
$ kubectl logs couchbase-admin-controller-ho6ta couchbase-sidekick
$ kubectl logs couchbase-controller-j7yzf couchbase-server
$ kubectl logs couchbase-controller-j7yzf couchbase-sidekick
```

* Expected [couchbase-server logs](https://gist.github.com/tleyden/b9677515952fa054ddd2)
* Expected [couchbase-sidekick logs](https://gist.github.com/tleyden/269679e71131b7e8536e)


## Connect to Couchbase Server Admin UI

This is platform specific.  

Currently there are only instructions for [Google Container Engine](https://github.com/couchbase/kubernetes/wiki/Running-on-Google-Container-Engine-(GKE))

# Sync Gateway

## Create a Sync Gateway replication set

Sync Gateway is a server-side component for Couchbase Mobile which provides a REST API in front of Couchbase Server, which Couchbase Lite enabled mobile apps connect to in order to sync their data.

It provides a good example of setting up an application tier on top of Couchbase Server.  If you were creating a tier of webservers that used a Couchbase SDK to store data in Couchbase Server, your architecture would be very similar to this.

To kick off a Sync Gateway replica set, run:

```
$ kubectl create -f replication-controllers/sync-gateway.yaml
```

By default, it will use the sync gateway config in [`config/sync-gateway.config`](https://github.com/couchbase/kubernetes/blob/master/config/sync-gateway.config) -- note that for the IP address of Couchbase Server, it uses the **dns service** address in the `default` namespace: `http://couchbase-service.default.svc.cluster.local:8091`. SkyDNS is enabled by default in GKE/GCE, but if you are not running SkyDNS, then you will need to change the config to the service ip shown in `kubectl get service couchbase-service`.

## Create a publicly exposed Sync Gateway service

```
$ kubectl create -f services/sync-gateway.yaml
```

To find the IP address after the pod is running, run:

```
$ kubectl describe service sync-gateway
```

and you should see:

```
...
LoadBalancer Ingress: 104.197.15.37
...
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

* Documentation on how to run on a different Kubernetes environment other than GKE. (eg, AWS)
* Improve the story when Pods go down.  Currently some manual intervention is needed to rebalance the cluster, ideally I'd like this to be fully automated.  (possibly via pod shutdown hook).  Currently:
    * New pod comes up with different ip
    * Rebalance fails because there are now 3 couchbase server nodes, one which is unreachable
    * To manually fix: fail over downed cb node, kick off rebalance
* Improve the story surrounding etcd
* Look into persistent data storage host mounted volumes

## Related Work

* [tophatch/CouchbaseMobileWithKubernetes](https://github.com/tophatch/CouchbaseMobileWithKubernetes)

## References

* [Couchbase Docker image on Dockerhub](https://hub.docker.com/u/couchbase/server)

* [Google cloud sdk](https://registry.hub.docker.com/u/google/cloud-sdk/)

* https://cloud.google.com/container-engine/docs/hello-wordpress

* https://cloud.google.com/container-engine/docs/guestbook

* [google groups post regarding etcd service](https://groups.google.com/d/msg/google-containers/rFIFD6Y0_Ew/GeDa8ZuPWd8J).
