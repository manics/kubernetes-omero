#!/bin/bash
set -eux

helm lint omero-server
helm lint omero-web

chartpress
git diff

./ci/test.sh
