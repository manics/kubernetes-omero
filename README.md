# Kubernetes OMERO

Kubernetes Helm charts for [OMERO](https://www.openmicroscopy.org/).

Install dependencies:

    helm dependency update omero-server/
    helm dependency update omero-web/

Install a test server (no persistent storage):

    helm upgrade --install omero-server --namespace omero ./omero-server -f omero-server.yaml
    helm upgrade --install omero-web --namespace omero ./omero-web -f omero-web.yaml

Wait for all pods to be ready:

    kubectl -n omero get pods

Check omero-server logs to see whether server has started since health-checks aren't implemented:

    kubectl -n omero logs -f deploy/omero-server-omero-server
