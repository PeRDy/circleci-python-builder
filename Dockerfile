FROM circleci/python:latest
LABEL maintainer="Perdy <perdy@perdy.io>"

ENV PYTHONPATH=$APPDIR:$PYTHONPATH

USER root

COPY requirements.txt $APPDIR/

RUN apt-get update && \
    apt-get install -y $BUILD_PACKAGES && \
    python -m pip install --no-cache-dir --upgrade pip poetry && \
    python -m pip install --no-cache-dir -r requirements.txt && \
    apt-get purge -y --auto-remove $BUILD_PACKAGES && \
    apt-get clean && \
    rm -rf \
        requirements.txt \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/*

USER circleci
