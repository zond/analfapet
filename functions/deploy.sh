#!/bin/bash
set -e

PROJECT=fcm-switch
REGION=europe-west1
RUNTIME=go126

# Compute hash of all Go source + go.mod (the deployable code)
LOCAL_HASH="h$(cat *.go go.mod | sha256sum | cut -c1-16)"

for FUNC in Register Send Inbox; do
  # Get the hash label from the deployed function
  DEPLOYED_HASH=$(gcloud functions describe "$FUNC" \
    --region="$REGION" --project="$PROJECT" \
    --format='value(labels.src_hash)' 2>/dev/null || echo "")

  if [ "$DEPLOYED_HASH" = "$LOCAL_HASH" ]; then
    echo "$FUNC is up to date, skipping."
  else
    echo "Deploying $FUNC..."
    gcloud functions deploy "$FUNC" \
      --gen2 --runtime="$RUNTIME" --trigger-http --allow-unauthenticated \
      --entry-point="$FUNC" --source=. --project="$PROJECT" --region="$REGION" \
      --update-labels="src_hash=$LOCAL_HASH"
    echo "$FUNC deployed."
  fi
  echo
done

echo "Done."
