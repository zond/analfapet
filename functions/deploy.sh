#!/bin/bash
set -e

PROJECT=fcm-switch
REGION=europe-west1
RUNTIME=go126

for FUNC in Register Send Inbox; do
  echo "Deploying $FUNC..."
  gcloud functions deploy "$FUNC" \
    --gen2 --runtime="$RUNTIME" --trigger-http --allow-unauthenticated \
    --entry-point="$FUNC" --source=. --project="$PROJECT" --region="$REGION"
  echo "$FUNC deployed."
  echo
done

echo "All functions deployed."
