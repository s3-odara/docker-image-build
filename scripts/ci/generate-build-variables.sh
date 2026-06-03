#!/usr/bin/env bash
set -euo pipefail

BUILD_SERIAL="$(date -u +%Y%m%d_%H%M)"

INPUT_RELEASE="${ISO_RELEASE_INPUT:-}"
INPUT_INCUS_VERSION="${INCUS_VERSION_INPUT:-}"
SKIP_ISO_RELEASE="${SKIP_ISO_RELEASE:-}"

if [ "$SKIP_ISO_RELEASE" = "1" ]; then
  echo "Skipping ISO release detection."
else
  if [ -n "$INPUT_RELEASE" ]; then
    ISO_RELEASE="$INPUT_RELEASE"
    echo "Using manual input: $ISO_RELEASE"
  else
    echo "Fetching latest ISO release date from archive.archlinux.org..."

    LATEST_DATE=$(curl -fsSL --retry 5 --retry-delay 2 https://archive.archlinux.org/iso/ | \
      grep -oE '[0-9]{4}\.[0-9]{2}\.[0-9]{2}' | \
      sort -Vu | \
      tail -n 1)

    if [ -z "$LATEST_DATE" ]; then
      echo "::error::Failed to fetch latest ISO date from archive.archlinux.org"
      exit 1
    else
      ISO_RELEASE="$LATEST_DATE"
    fi
    echo "Detected latest release: $ISO_RELEASE"
  fi
fi

if [ -n "$INPUT_INCUS_VERSION" ]; then
  INCUS_VERSION="$INPUT_INCUS_VERSION"
else
  INCUS_VERSION="$(go list -m -versions github.com/lxc/incus/v6 | awk '{print $NF}')"
fi
if [ -z "$INCUS_VERSION" ]; then
  echo "::error::Failed to determine incus-simplestreams version"
  exit 1
fi
echo "Using incus-simplestreams: $INCUS_VERSION"

{
  if [ "$SKIP_ISO_RELEASE" != "1" ]; then
    echo "iso_release=$ISO_RELEASE"
  fi
  echo "build_serial=$BUILD_SERIAL"
  echo "incus_version=$INCUS_VERSION"
} >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
