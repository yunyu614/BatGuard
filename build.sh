#!/bin/sh
set -e
cd "$(dirname "$0")"
VER=$(sed -n 's/^version=//p' pkg/module.prop | tr -d '\r')
OUT="BatGuard-${VER}.zip"
rm -f "$OUT"
( cd pkg && zip -qr "../$OUT" . -x 'data/*' '.git/*' )
echo "打包完成: $(pwd)/$OUT  ($(stat -c%s "$OUT") bytes)"
unzip -l "$OUT" | tail -20
