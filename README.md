# Kubernetes OMERO

Kubernetes Helm charts for [OMERO](https://www.openmicroscopy.org/).

Install dependencies:

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

For the full set of configuration options see
- [omero-server/values.yaml](omero-server/values.yaml)
- [omero-web/values.yaml](omero-web/values.yaml)


## Storage volumes

You can define existing PersistentVolumeClaims to use for PostgreSQL and OMERO.server data storage.

Alternatively PersistentVolumes can be automatically created using dynamic provisioning if supported by your cluster.
These volumes will *not* be deleted by `helm delete` to reduce the likehood of inadvertent data loss, and will be reused if the chart is re-installed.
You must delete the PVCs manually if you want a fresh installation.