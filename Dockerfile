FROM circleci/python:latest
LABEL maintainer="Perdy <perdy@perdy.io>"

ENV LC_ALL='C.UTF-8' PYTHONIOENCODING='utf-8'
ENV APPDIR=/etc/builder/
ENV PYTHONPATH=$APPDIR:$PYTHONPATH
ENV BUILD_PACKAGES build-essential
ENV RUNTIME_PACKAGES curl

# Install system dependencies
RUN apt-get update && \
    apt-get install -y $RUNTIME_PACKAGES && \
    rm -rf \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/*

# Create initial dirs
RUN mkdir -p $APPDIR
WORKDIR $APPDIR

COPY requirements.txt $APPDIR/

RUN apt-get update && \
    apt-get install -y $BUILD_PACKAGES && \
    python -m pip install --upgrade pip poetry && \
    python -m pip install --no-cache-dir -r requirements.txt && \
    apt-get purge -y --auto-remove $BUILD_PACKAGES && \
    apt-get clean && \
    rm -rf \
        requirements.txt \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/*

ENTRYPOINT ["python"]
