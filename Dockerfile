FROM circleci/python:latest
LABEL maintainer="Perdy <perdy@perdy.io>"

ENV PYTHONPATH=$APPDIR:$PYTHONPATH

USER root

COPY requirements.txt $APPDIR/

RUN apt-get update && \
    apt-get install -y $BUILD_PACKAGES && \
    curl -o /usr/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && \
    chmod +x /usr/bin/kubectl && \
    curl -o /usr/bin/aws-iam-authenticator https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-07-26/bin/linux/amd64/aws-iam-authenticator && \
    chmod +x /usr/bin/aws-iam-authenticator && \
    python -m pip install --no-cache-dir --upgrade pip poetry && \
    python -m pip install --no-cache-dir -r requirements.txt && \
    apt-get purge -y --auto-remove $BUILD_PACKAGES && \
    apt-get clean && \
    rm -rf \
        requirements.txt \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/*

# Copy build script
COPY builder /usr/local/bin

USER circleci

