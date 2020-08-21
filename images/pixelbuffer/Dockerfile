ARG OMERO_IMAGEREGION_VERSION=latest
FROM openmicroscopy/omero-server:$OMERO_SERVER_VERSION

LABEL maintainer="https://github.com/manics"
LABEL org.opencontainers.image.source="https://github.com/manics/kubernetes-omero"

RUN cd /opt/omero/server/OMERO.server/lib/python && \
    set -o pipefail && \
    curl -sSfL https://patch-diff.githubusercontent.com/raw/openmicroscopy/openmicroscopy/pull/5884.diff | \
    patch -p5
