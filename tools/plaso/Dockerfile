FROM ubuntu:22.04

LABEL tool="plaso"
LABEL version="20240512"
LABEL purpose="Timeline analysis / super timeline generation"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common wget gnupg \
    && add-apt-repository -y ppa:gift/stable \
    && apt-get update \
    && apt-get install -y --no-install-recommends plaso-tools \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /fixtures /output
WORKDIR /fixtures

COPY validate.sh /usr/local/bin/validate.sh
RUN chmod +x /usr/local/bin/validate.sh

ENTRYPOINT ["log2timeline.py"]
