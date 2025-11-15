FROM node:current-slim
RUN sed -i 's/components=main/components=main contrib/' /etc/apt/sources.list.d/debian.sources
RUN apt-get update && apt-get install -y fonts-ibm-plex \
chromium chromium-driver chromium-l10n && \
apt-get clean && rm -rf /var/lib/apt/lists/*
RUN npm install -g @vivliostyle/cli
