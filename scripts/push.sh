#!/usr/bin/env bash
# Push api and worker images (tagged with the short git SHA) to Docker Hub.
# Needs: docker login, and DOCKERHUB_USER exported; run ./scripts/up.sh first (it builds the images).
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DOCKERHUB_USER:?export DOCKERHUB_USER=<your dockerhub username>}"
TAG="$(git rev-parse --short HEAD)"
mkdir -p docs/evidence
: > docs/evidence/image-digests.txt
for svc in api worker; do
  img="${DOCKERHUB_USER}/linkly-${svc}:${TAG}"
  docker push "$img"
  docker image inspect -f '{{index .RepoDigests 0}}' "$img" | tee -a docs/evidence/image-digests.txt
done
