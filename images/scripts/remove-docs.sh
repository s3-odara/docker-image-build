#!/usr/bin/env bash
set -euo pipefail

# ドキュメント、マニュアル、ヘルプファイルを削除
for dir in /usr/share/doc /usr/share/gtk-doc /usr/share/help /usr/share/info /usr/share/man; do
  if [ -d "$dir" ]; then
    find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  fi
done
if [ -d /usr/share/locale ]; then
  find /usr/share/locale -mindepth 1 -maxdepth 1 -type d ! -name 'en' ! -name 'ja' -exec rm -rf -- {} + || true
fi
for dir in /usr/share/icons; do
  if [ -d "$dir" ]; then
    find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  fi
done
