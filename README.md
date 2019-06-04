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
