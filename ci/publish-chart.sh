#!/bin/bash
set -eu

# Chartpress uses git to push to the Helm chart repository
echo -----BEGIN OPENSSH PRIVATE KEY----- > ci/id_rsa
echo $CHARTPRESS_PUBLISH_KEY >> ci/id_rsa
echo -----END OPENSSH PRIVATE KEY----- >> ci/id_rsa
chmod 0400 ci/id_rsa

docker login -u "${DOCKER_USERNAME}" -p "${DOCKER_PASSWORD}"

# Activate logging of bash commands now that the sensitive stuff is done
set -x

export GIT_SSH_COMMAND="ssh -i ${PWD}/ci/id_rsa"

chartpress --commit-range "${TRAVIS_COMMIT_RANGE}" --push --publish-chart

# Log changes made by chartpress
git diff
