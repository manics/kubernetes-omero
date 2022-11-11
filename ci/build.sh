#!/bin/bash
set -eux

helm lint omero-server omero-web

./ci/chartpress.py
git diff
