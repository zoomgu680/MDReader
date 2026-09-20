#!/usr/bin/env bash
# ============================================================
# MDReader - dist 同步脚本 (macOS / Linux bash)
# 用途：把根目录 index.html 和 resources/ 复制到 dist/
# 用法：在项目根目录执行 ./sync-dist.sh
# ============================================================
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
SRC_INDEX="$ROOT/index.html"
SRC_RES="$ROOT/resources"

mkdir -p "$DIST/resources"

echo "[Sync] 复制 index.html ..."
cp "$SRC_INDEX" "$DIST/index.html"

echo "[Sync] 复制 resources/ ..."
cp -R "$SRC_RES/"* "$DIST/resources/"

echo "[Sync] 完成 $(date +%H:%M:%S)"
