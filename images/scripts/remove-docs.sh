#!/usr/bin/env bash
set -euo pipefail

# ドキュメント、ヘルプファイルを削除
for dir in /usr/share/doc ; do
  if [ -d "$dir" ]; then
    find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  fi
done
if [ -d /usr/share/locale ]; then
  find /usr/share/locale -mindepth 1 -maxdepth 1 -type d ! -name 'en' ! -name 'ja' -exec rm -rf -- {} + || true
fi
if [ -d /usr/share/icons ]; then
  find /usr/share/icons -mindepth 1 -maxdepth 1 ! -name 'hicolor' ! -name 'Adwaita' -exec rm -rf -- {} +
fi
if [ -d /usr/share/icons/Adwaita ]; then
  find /usr/share/icons/Adwaita -mindepth 1 -maxdepth 1 ! -name 'symbolic' ! -name 'index.theme' -exec rm -rf -- {} +
fi
