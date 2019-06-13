# Kubernetes OMERO

[![Build Status](https://travis-ci.com/manics/kubernetes-omero.svg?branch=master)](https://travis-ci.com/manics/kubernetes-omero)

Kubernetes Helm charts for [OMERO](https://www.openmicroscopy.org/).


## Quick start

Add the OMERO Helm chart repository:

    helm repo add omero https://manics.github.io/kubernetes-omero/
    helm repo update

Optionally create your OMERO.server and OMERO.web Helm configuration files.
You can use [`minikube-omero-server.yaml`](minikube-omero-server.yaml) and [`minikube-omero-web.yaml`](minikube-omero-web.yaml) as examples.

Install OMERO.server and OMERO.web

    helm install --name omeroserver omero/omero-server -f minikube-omero-server.yaml
    helm install --name omeroweb omero/omero-web -f minikube-omero-web.yaml


For the full set of configuration options see
- [omero-server/values.yaml](omero-server/values.yaml)
- [omero-web/values.yaml](omero-web/values.yaml)


## Storage volumes

You can define existing PersistentVolumeClaims to use for PostgreSQL and OMERO.server data storage.

Alternatively PersistentVolumes can be automatically created using dynamic provisioning if supported by your cluster.
These volumes will *not* be deleted by `helm delete` to reduce the likehood of inadvertent data loss, and will be reused if the chart is re-installed.
You must delete the PVCs manually if you want a fresh installation.


## Development

Install build dependencies:

    pip install dev-requirements.txt

Install chart dependencies:

    helm dependency update omero-server/
    helm dependency update omero-web/

Install a test server on Minikube (assumes your Minikube has the default ingress and dynamic hostpath volumes enabled):

    helm upgrade --install omero-server --namespace omero ./omero-server -f minikube-omero-server.yaml
    helm upgrade --install omero-web --namespace omero ./omero-web -f minikube-omero-web.yaml

Wait for all pods to be ready:

    kubectl -n omero get pods

Optionally check omero-server logs:

    kubectl -n omero logs -f deploy/omero-server-omero-server

Get the OMERO.server 4064 external port mapping:

    kubectl -n omero get svc omero-server -o jsonpath='{.spec.ports[0].nodePort}'


## Release process

Tags and Docker images are automatically pushed when the Chart.yaml versions are changed.
Charts are versioned independently. GitHub tags are prefixed with the component name.

This is all handled using [Chartpress](https://github.com/manics/chartpress/tree/devel).

See:
- [`.github/main.workflow`](.github/main.workflow)
- [`.travis.yml`](.travis.yml)
