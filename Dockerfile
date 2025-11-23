FROM node:current-slim

RUN set -eux; \
    sed -i 's/Components: main/Components: main contrib/' /etc/apt/sources.list.d/debian.sources; \
    \
    apt-get update; \
    \
    apt-get install -y --no-install-recommends \
        git\
        ca-certificates\
        poppler-utils\
        ghostscript\
        fonts-ibm-plex \
        chromium \
        chromium-driver \
        chromium-l10n; \
    \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

COPY fonts /usr/local/share/fonts/custom-fonts

RUN fc-cache -f -v

RUN npm install -g @vivliostyle/cli press-ready
