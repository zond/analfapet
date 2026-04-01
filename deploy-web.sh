#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Build if not already built (CI may have built already)
if [ ! -d build/web ]; then
  echo "Building..."
  flutter build web --release --base-href /analfapet/
fi

# Stamp the service worker so the browser detects a new version
echo "// build: $(date -Iseconds)" >> build/web/firebase-messaging-sw.js

# Use provided remote URL or default to SSH
REMOTE="${1:-git@github.com:zond/analfapet.git}"

echo "Deploying to gh-pages via $REMOTE..."
DIR=$(mktemp -d)
cp -r build/web/* "$DIR"
cd "$DIR"
git init
git checkout -b gh-pages
git add -A
git commit -m "Deploy $(date -Iseconds)"
git push -f "$REMOTE" gh-pages
rm -rf "$DIR"

echo "Done. Site will update in ~30 seconds."
