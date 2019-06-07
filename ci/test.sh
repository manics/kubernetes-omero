#!/bin/bash

fold_start() {
  echo -e "travis_fold:start:$1\033[33;1m$2\033[0m"
}

fold_end() {
  echo -e "\ntravis_fold:end:$1\r"
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
  fold_start logs.1 "Display kubernetes logs"
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
  fold_end logs.1
}

set -eux

# Is there a standard interface name?
for iface in eth0 ens4 enp0s3; do
  IP=$(ifconfig $iface | grep 'inet addr' | cut -d: -f2 | awk '{print $1}');
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

helm install --name omero-server --namespace $TEST_NAMESPACE ./omero-server/ \
  -f minikube-omero-server.yaml $HELM_EXTRA_ARGS
helm install --name omero-web --namespace $TEST_NAMESPACE ./omero-web/ \
  -f minikube-omero-web.yaml $HELM_EXTRA_ARGS

fold_start deploy.1 "Waiting for servers to be ready"

echo "waiting for omero-server"
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

echo "waiting for omero-web"
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

fold_end deploy.1

echo "Importing image"
OMERO_PORT=$(kubectl -n $TEST_NAMESPACE get svc omero-server -o jsonpath='{.spec.ports[0].nodePort}')
IMAGE_ID=$(docker run --rm -v $PWD:/data:ro --entrypoint /opt/omero/server/OMERO.server/bin/omero openmicroscopy/omero-server:5.4.10 \
  import -s root@$IP:$OMERO_PORT -w omero -T Dataset:name:test /data/ci/opengraph-repo-image.jpg --encrypted true)

pytest ci/test_image.py

display_logs
kubectl_retry --namespace $TEST_NAMESPACE get pods
