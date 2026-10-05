#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/output"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="$OUT_DIR/intercity-vps-deploy-$STAMP.tar.gz"

mkdir -p "$OUT_DIR"

tar \
  --exclude='backend/node_modules' \
  --exclude='apps/mobile_flutter/build' \
  --exclude='apps/admin_web/build' \
  --exclude='.playwright-mcp' \
  --exclude='output' \
  -czf "$ARCHIVE" \
  -C "$ROOT_DIR" \
  backend infra/vps packages scripts README.md

shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"

echo "$ARCHIVE"
echo "$ARCHIVE.sha256"
