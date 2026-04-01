#!/bin/bash
set -e

echo "Building..."
flutter build web --release --base-href /analfapet/

echo "Deploying to gh-pages..."
DIR=$(mktemp -d)
cp -r build/web/* "$DIR"
cd "$DIR"
git init
git checkout -b gh-pages
git add -A
git commit -m "Deploy $(date -Iseconds)"
git push -f git@github.com:zond/analfapet.git gh-pages
rm -rf "$DIR"

echo "Done. Site will update in ~30 seconds."
