

* **k8s-gce-register.sh** -- this stands up the Couchbase cluster if you are running on raw GCE (as opposed to GKE, which has Kubernetes running already).  Assumes you have a running GCE cluster started with `echo curl -sS https://get.k8s.io | bash` as per the source's comments
* **k8s-gce-cleanup.sh** -- cleanup/teardown for k8s-gce-register.sh
* **register.sh**	--  this stands up the Couchbase cluster if you are running on GKE
* **cleanup.sh** -- cleanup/teardown for register.sh
* **nodes.js** -- ??
