#!/usr/bin/env bash
# Trivy scan of the PUSHED images (pulled from Docker Hub; no Docker socket mount needed).
# Fails if any fixable CRITICAL vulnerability is found.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DOCKERHUB_USER:?export DOCKERHUB_USER=<your dockerhub username>}"
TAG="$(git rev-parse --short HEAD)"
for svc in api worker; do
  img="${DOCKERHUB_USER}/linkly-${svc}:${TAG}"
  echo "=== trivy: $img"
  docker run --rm --cap-drop ALL --security-opt no-new-privileges:true \
    -v trivy-cache:/root/.cache/ \
    aquasec/trivy:0.56.2 image --severity CRITICAL --ignore-unfixed --exit-code 1 "$img"
done
echo "trivy: 0 fixable CRITICAL vulnerabilities"
