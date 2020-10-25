ARG OMERO_SERVER_VERSION=latest
FROM openmicroscopy/omero-server:$OMERO_SERVER_VERSION

LABEL maintainer="https://github.com/manics"
LABEL org.opencontainers.image.source="https://github.com/manics/kubernetes-omero"

ADD 50-config.py /startup/
USER root
RUN /opt/omero/server/venv3/bin/pip install omero-certificates==0.2.0
USER omero-server
