FROM ubuntu:22.04

LABEL tool="mft-tools"
LABEL version="1.2.0.0"
LABEL purpose="MFT parsing (analyzeMFT primary, MFTECmd via manual install)"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip wget \
    && rm -rf /var/lib/apt/lists/*

# analyzeMFT (Python-based MFT parser — primary tool)
RUN pip3 install --no-cache-dir analyzemft==2.1.0

# MFTECmd placeholder — Zimmerman tools CDN changed, install manually later
# RUN wget -q <URL> && unzip ... -d /opt/mftecmd

RUN mkdir -p /evidence /output
WORKDIR /evidence

COPY validate.sh /usr/local/bin/validate.sh
RUN chmod +x /usr/local/bin/validate.sh
