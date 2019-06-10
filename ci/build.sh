#!/bin/bash
set -eux

helm lint omero-server omero-web

chartpress
git diff

./ci/test.sh
