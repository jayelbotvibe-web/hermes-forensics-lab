# mft-tools — MFT parsing container
# Primary: analyzeMFT (Python). Cross-validation: MFTECmd (Eric Zimmerman, .NET 9).
FROM mcr.microsoft.com/dotnet/runtime:9.0

LABEL tool="mft-tools"
LABEL version="1.2.0.0"
LABEL purpose="MFT parsing (analyzeMFT primary, MFTECmd cross-validation)"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip unzip curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# analyzeMFT (Python-based MFT parser — primary tool)
RUN pip3 install --no-cache-dir --break-system-packages analyzemft==2.1.0

# MFTECmd — cross-validation parser.
# The Zimmerman CDN serves latest-only (no versioned URLs), so the archive is
# pinned by SHA256: an upstream release change fails this build LOUDLY instead
# of drifting silently. On a new MFTECmd release: verify the new zip, update
# MFTECMD_SHA256 here, rebuild, and update tools/tool-catalog.yaml.
ARG MFTECMD_URL=https://download.ericzimmermanstools.com/net9/MFTECmd.zip
ARG MFTECMD_SHA256=60ae857a554b830243e38e91fafdfdf6066f31c703282c5c6f40daf3b64d3160
RUN curl -fsSL "$MFTECMD_URL" -o /tmp/mftecmd.zip \
    && echo "$MFTECMD_SHA256  /tmp/mftecmd.zip" | sha256sum -c - \
    && mkdir -p /opt/mftecmd \
    && unzip -q /tmp/mftecmd.zip -d /opt/mftecmd \
    && rm /tmp/mftecmd.zip \
    && (dotnet /opt/mftecmd/MFTECmd.dll 2>&1 || true) \
       | grep -m1 -oE 'version [0-9][0-9.]*' | grep -oE '[0-9][0-9.]*' \
       > /opt/mftecmd/VERSION \
    && echo "MFTECmd version: $(cat /opt/mftecmd/VERSION)"

# Convenience wrapper so callers don't need the dll path
RUN printf '#!/bin/sh\nexec dotnet /opt/mftecmd/MFTECmd.dll "$@"\n' > /usr/local/bin/mftecmd \
    && chmod +x /usr/local/bin/mftecmd

RUN mkdir -p /evidence /output
WORKDIR /evidence

COPY validate.sh /usr/local/bin/validate.sh
RUN chmod +x /usr/local/bin/validate.sh
