#!/bin/bash

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
    fold_start "Display kubernetes logs"
    # May crash on Travis:
    #echo "***** minikube *****"
    #minikube logs
    echo "***** node *****"
    kubectl_retry describe node
    echo "***** pods *****"
    kubectl_retry --namespace $TEST_NAMESPACE get pods
    echo "***** events *****"
    kubectl_retry --namespace $TEST_NAMESPACE get events
    echo "***** hub *****"
    kubectl_retry --namespace $TEST_NAMESPACE logs statefulset/omero-server
    echo "***** proxy *****"
    kubectl_retry --namespace $TEST_NAMESPACE logs deploy/omero-web
    fold_end
}

set -eux

# Is there a standard interface name?
for iface in eth0 ens4 enp0s3; do
    IP=$(ip -o -4 addr show $iface | awk '{print $4}' | cut -d/ -f1);
    if [ -n "$IP" ]; then
        echo "IP: $IP"
        break
    fi
done
if [ -z "$IP" ]; then
    echo "Failed to get IP, current interfaces:"
    ifconfig -a
    exit 2
fi

TEST_NAMESPACE=omero-test

helm dependency update ./omero-server/
helm dependency update ./omero-web/

helm upgrade --install omero-server --namespace $TEST_NAMESPACE --create-namespace \
    ./omero-server/ -f test-omero-server.yaml
helm upgrade --install omero-web --namespace $TEST_NAMESPACE --create-namespace \
    ./omero-web/ -f test-omero-web.yaml

fold_start "waiting for omero-server"
n=0
until [ "`kubectl_retry -n $TEST_NAMESPACE get statefulset omero-server -o jsonpath='{.status.readyReplicas}'`" = 1 ]; do
    let ++n
    if [ $(( $n % 12 )) -eq 0 ]; then
        kubectl_retry -n $TEST_NAMESPACE describe pod
    else
        kubectl_retry -n $TEST_NAMESPACE get pod
    fi
    sleep 10
done
fold_end

fold_start "waiting for omero-web"
n=0
until [ "`kubectl_retry -n $TEST_NAMESPACE get deploy omero-web -o jsonpath='{.status.readyReplicas}'`" = 1 ]; do
    let ++n
    if [ $(( $n % 12 )) -eq 0 ]; then
        kubectl_retry -n $TEST_NAMESPACE describe pod
    else
        kubectl_retry -n $TEST_NAMESPACE get pod
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
kubectl_retry --namespace $TEST_NAMESPACE get pods
