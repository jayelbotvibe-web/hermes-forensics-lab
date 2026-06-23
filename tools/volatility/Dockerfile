FROM python:3.10-slim

LABEL tool="volatility3"
LABEL version="2.7.0"
LABEL purpose="Memory forensics analysis"

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir volatility3==2.7.0

RUN mkdir -p /fixtures /output
WORKDIR /fixtures

COPY validate.sh /usr/local/bin/validate.sh
RUN chmod +x /usr/local/bin/validate.sh

ENTRYPOINT ["vol"]
