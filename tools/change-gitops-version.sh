#!/usr/bin/env bash
set -euo pipefail

GITOPS_DIR="${GITOPS_DIR:-$HOME/goinfre/mbernard-iot}"
REPO_URL="git@github.com:melobern/mbernard-iot.git"

if [[ ! -d "$GITOPS_DIR/.git" ]]; then
    git clone "$REPO_URL" "$GITOPS_DIR"
fi

cd "$GITOPS_DIR"
CURRENT_VERSION="$(grep -m1 'image:' deployment.yaml | cut -d ':' -f 3)"

if [[ "$CURRENT_VERSION" == "v1" ]]; then
    NEW_VERSION="v2"
    sed -i 's/wil42\/playground\:v1/wil42\/playground\:v2/g' deployment.yaml
elif [[ "$CURRENT_VERSION" == "v2" ]]; then
    NEW_VERSION="v1"
    sed -i 's/wil42\/playground\:v2/wil42\/playground\:v1/g' deployment.yaml
else
    echo "Unsupported image version: $CURRENT_VERSION" >&2
    exit 1
fi

git add deployment.yaml
git commit -m "Change version to $NEW_VERSION"
git push
