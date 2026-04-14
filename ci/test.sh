#!/bin/bash

# https://cloudnative-pg.io/docs/1.28/supported_releases#support-status-of-cloudnativepg-releases
CNPG_VERSION=1.28.1

f_green="\n\033[32;1m%s\033[0m\n"
f_red="\n\033[31;1m%s\033[0m\n"

fold_start() {
    echo "::group::$1"
}

fold_end() {
    echo "::endgroup::"
}

# kubectl seems to frequently loose its connection on Travis, auto-retry once
kubectl_retry() {
    kubectl "$@" || {
        >&2 printf "$f_red" "kubectl failed, retrying..."
        sleep 3
        kubectl "$@"
    }
}

display_logs() {
    fold_start "Display kubernetes resources"

    printf "$f_green" "***** node *****"

    kubectl_retry describe node
    for obj in daemonset deployment statefulset pods service ingress pv pvc events; do
        printf "$f_green" "***** $obj *****"
        kubectl_retry --namespace $TEST_NAMESPACE get "$obj"
    done
    for crd in cluster; do
        printf "$f_green" "***** crd: $crd *****"
        kubectl_retry --namespace $TEST_NAMESPACE get "$crd"
    done

    printf "$f_green" "***** logs: omero-server *****"
    kubectl_retry --namespace $TEST_NAMESPACE logs statefulset/omero-server

    printf "$f_green" "***** logs: omero-web *****"
    kubectl_retry --namespace $TEST_NAMESPACE logs deploy/omero-web

    printf "$f_green" "***** logs: cnpg-controller-manager *****"
    kubectl_retry --namespace cnpg-system logs deploy/cnpg-controller-manager

    fold_end
}

set -eux

fold_start "installing postgresql"

if [ $(kubectl version -ojson | jq -r '.serverVersion | "\(.major).\(.minor)"') == 1.21 ]; then
    CNPG_VERSION=1.15.1
fi

IP=$(hostname -I | awk '{print $1}')

TEST_NAMESPACE=omero-test

kubectl create namespace $TEST_NAMESPACE

kubectl apply --server-side=true -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/main/releases/cnpg-${CNPG_VERSION}.yaml
kubectl -ncnpg-system rollout status deploy cnpg-controller-manager --timeout=300s
kubectl apply --namespace $TEST_NAMESPACE -f test-postgresql.yaml
fold_end

fold_start "installing omero-server omero-web"

helm upgrade --install omero-server --namespace $TEST_NAMESPACE --create-namespace \
    ./omero-server/ -f test-omero-server.yaml

helm dependency update ./omero-web/
helm upgrade --install omero-web --namespace $TEST_NAMESPACE --create-namespace \
    ./omero-web/ -f test-omero-web.yaml
fold_end

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
        printf "$f_red" "Failed to start OMERO.server after $SECONDS s, exiting"
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
        printf "$f_red" "Failed to start OMERO.web after $SECONDS s, exiting"
        display_logs
        exit 1
    fi
    sleep 10
done
fold_end

# Display logs if tests fail
trap display_logs EXIT

fold_start "importing image"
OMERO_PORT=$(kubectl -n $TEST_NAMESPACE get svc omero-server -o jsonpath='{.spec.ports[0].nodePort}')
omero login -s root@localhost:$OMERO_PORT -w omero
omero import -T Dataset:name:test ci/opengraph-repo-image.jpg
omero logout
omero login -s wss://localhost/omero-ws -u root -w omero
omero import -T Dataset:name:testws ci/opengraph-repo-image.jpg
omero logout
fold_end

fold_start "pytest"
SERVER="https://localhost" pytest ci/test_image.py
fold_end

display_logs
