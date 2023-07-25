#!/bin/bash

BITNAMI_POSTGRESQL_VERSION=12.6.0

fold_start() {
    echo "::group::$1"
}

fold_end() {
    echo "::endgroup::"
}

# kubectl seems to frequently loose its connection on Travis, auto-retry once
kubectl_retry() {
    kubectl "$@" || {
        >&2 echo "kubectl failed, retrying..."
        sleep 3
        kubectl "$@"
    }
}

display_logs() {
    fold_start "Display kubernetes resources"
    echo "***** node *****"
    kubectl_retry describe node
    for obj in daemonset deployment statefulset pods service ingress pv pvc events; do
        echo "***** $obj *****"
        kubectl_retry --namespace $TEST_NAMESPACE get "$obj"
    done
    echo "***** hub *****"
    kubectl_retry --namespace $TEST_NAMESPACE logs statefulset/omero-server
    echo "***** proxy *****"
    kubectl_retry --namespace $TEST_NAMESPACE logs deploy/omero-web
    fold_end
}

set -eux

IP=$(hostname -I | awk '{print $1}')

TEST_NAMESPACE=omero-test

helm repo add bitnami https://charts.bitnami.com/bitnami
helm upgrade --install postgresql --namespace $TEST_NAMESPACE --create-namespace bitnami/postgresql  --version $BITNAMI_POSTGRESQL_VERSION -f test-postgresql.yaml

helm upgrade --install omero-server --namespace $TEST_NAMESPACE --create-namespace \
    ./omero-server/ -f test-omero-server.yaml

helm dependency update ./omero-web/
helm upgrade --install omero-web --namespace $TEST_NAMESPACE --create-namespace \
    ./omero-web/ -f test-omero-web.yaml

fold_start "waiting for omero-server"
n=0
# Built-in bash timer
SECONDS=0
until [ "`kubectl_retry -n $TEST_NAMESPACE get statefulset omero-server -o jsonpath='{.status.readyReplicas}'`" = 1 ]; do
    let ++n
    if [ $(( $n % 12 )) -eq 0 ]; then
        kubectl_retry -n $TEST_NAMESPACE describe pod
    else
        kubectl_retry -n $TEST_NAMESPACE get pod
    fi
    if [ $SECONDS -gt 600 ]; then
        echo "Failed to start OMERO.server after $SECONDS s, exiting"
        display_logs
        exit 1
    fi
    sleep 10
done
fold_end

fold_start "waiting for omero-web"
n=0
# Built-in bash timer
SECONDS=0
until [ "`kubectl_retry -n $TEST_NAMESPACE get deploy omero-web -o jsonpath='{.status.readyReplicas}'`" = 1 ]; do
    let ++n
    if [ $(( $n % 12 )) -eq 0 ]; then
        kubectl_retry -n $TEST_NAMESPACE describe pod
    else
        kubectl_retry -n $TEST_NAMESPACE get pod
    fi
    if [ $SECONDS -gt 300 ]; then
        echo "Failed to start OMERO.web after $SECONDS s, exiting"
        display_logs
        exit 1
    fi
    sleep 10
done
fold_end

echo "Importing image"
OMERO_PORT=$(kubectl -n $TEST_NAMESPACE get svc omero-server -o jsonpath='{.spec.ports[0].nodePort}')
omero login -s root@localhost:$OMERO_PORT -w omero
omero import -T Dataset:name:test ci/opengraph-repo-image.jpg
omero logout
omero login -s wss://localhost/omero-ws -u root -w omero
omero import -T Dataset:name:testws ci/opengraph-repo-image.jpg
omero logout

SERVER="https://localhost" pytest ci/test_image.py

display_logs
