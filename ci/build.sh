#!/bin/bash
set -eux

env

helm lint omero-server omero-web

/usr/share/miniconda/bin/pip list
which python
which conda
python -c 'import ruamel.yaml'
python -c 'from ruamel.yaml import YAML'
/usr/share/miniconda/bin/python ./ci/chartpress.py
git diff

./ci/test.sh
