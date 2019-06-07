#!/bin/sh
# Run this inside vagrant to test the travis scripts

set -eux
export SCENARIO=1.14-default

pip3 install --no-cache-dir -r dev-requirements.txt
. ./ci/minikube-${SCENARIO}.env
./ci/install.sh
./ci/test.sh
