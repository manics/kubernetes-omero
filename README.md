# Kubernetes OMERO

[![CI Status](https://github.com/manics/kubernetes-omero/workflows/Test%20and%20Publish/badge.svg)](https://github.com/manics/kubernetes-omero/actions?query=branch%3Amaster)

Kubernetes Helm charts for [OMERO](https://www.openmicroscopy.org/).


## Quick start

Add the OMERO Helm chart repository:

    helm repo add omero https://manics.github.io/kubernetes-omero/
    helm repo update

Optionally create your OMERO.server and OMERO.web Helm configuration files.
You can use [`test-omero-server.yaml`](test-omero-server.yaml) and [`test-omero-web.yaml`](test-omero-web.yaml) as examples.

Install OMERO.server and OMERO.web

    helm install --name omeroserver omero/omero-server -f test-omero-server.yaml
    helm install --name omeroweb omero/omero-web -f test-omero-web.yaml


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

Install a test server on K3S (assumes the default ingress and dynamic local volumes are enabled):

    helm upgrade --install omero-server ./omero-server -f test-omero-server.yaml
    helm upgrade --install omero-web ./omero-web -f test-omero-web.yaml

Wait for all pods to be ready:

    kubectl get pods

Optionally check logs:

    kubectl logs -f statefulset/omero-server
    kubectl logs -f deploy/omero-web

Get the OMERO.server 4064 external port mapping:

    kubectl get svc omero-server -o jsonpath='{.spec.ports[0].nodePort}'


## Release process

Tags and Docker images are automatically pushed when the Chart.yaml versions are changed.
Charts are versioned independently. GitHub tags are prefixed with the component name.

This is all handled using [Chartpress](./ci/chartpress.py).

See:
- [`.github/workflows/test.yml`](.github/workflows/test.yml)
