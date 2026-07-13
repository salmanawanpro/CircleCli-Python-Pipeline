#!/usr/bin/env bash
# Deploys the Flask app to Vercel production. Expects VERCEL_TOKEN,
# VERCEL_ORG_ID, and VERCEL_PROJECT_ID to be present from the vercel-deploy
# CircleCI context. Only intended to run on the default branch.
set -euo pipefail

: "${VERCEL_TOKEN:?VERCEL_TOKEN is required}"
: "${VERCEL_ORG_ID:?VERCEL_ORG_ID is required}"
: "${VERCEL_PROJECT_ID:?VERCEL_PROJECT_ID is required}"

echo "Pulling Vercel production environment..."
vercel pull --yes --environment=production --token="$VERCEL_TOKEN"

echo "Building production artifacts..."
vercel build --prod --token="$VERCEL_TOKEN"

echo "Deploying prebuilt artifacts to Vercel production..."
DEPLOY_URL="$(vercel deploy --prebuilt --prod --token="$VERCEL_TOKEN")"

echo "Published to Vercel: ${DEPLOY_URL}"
