FROM node:current-slim

RUN set -eux; \
    sed -i 's/Components: main/Components: main contrib/' /etc/apt/sources.list.d/debian.sources; \
    \
    apt-get update; \
    \
    apt-get install -y --no-install-recommends \
        git\
        fonts-ibm-plex \
        chromium \
        chromium-driver \
        chromium-l10n; \
    \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g @vivliostyle/cli
