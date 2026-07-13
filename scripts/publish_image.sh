#!/usr/bin/env bash
# Tags the locally-built image, pushes it to Artifact Registry, and deploys
# it to Cloud Run. Expects gcloud to already be authenticated via OIDC
# (Workload Identity Federation) before this script runs.
set -euo pipefail

IMAGE_LOCAL="app:${CIRCLE_SHA1}"
IMAGE_REMOTE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${AR_REPO}/app:${CIRCLE_SHA1}"

echo "Configuring docker auth for Artifact Registry..."
gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet

echo "Tagging and pushing ${IMAGE_REMOTE}..."
docker tag "$IMAGE_LOCAL" "$IMAGE_REMOTE"
docker push "$IMAGE_REMOTE"

echo "Deploying to Cloud Run..."
gcloud run deploy app-service \
  --image "$IMAGE_REMOTE" \
  --project "$GCP_PROJECT_ID" \
  --region "$GCP_REGION" \
  --platform managed \
  --allow-unauthenticated \
  --quiet

echo "Published ${IMAGE_REMOTE} and deployed to Cloud Run."
