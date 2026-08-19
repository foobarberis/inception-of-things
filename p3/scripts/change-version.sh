#!/bin/bash
REPO="mbernard-iot"
FULL_REPO_LINK="git@github.com:melobern/"$REPO".git"

if [ ! -d "$REPO" ]; then
	git clone "$FULL_REPO_LINK"
fi

cd "$REPO"
CURRENT_VERSION=$(grep "image:" deployment.yaml | cut -d':' -f3)

if [ "$CURRENT_VERSION" = "v1" ]; then
NEW_VERSION="v2"
sed -i 's/wil42\/playground\:v1/wil42\/playground\:v2/g' deployment.yaml
else
NEW_VERSION="v1"
sed -i 's/wil42\/playground\:v2/wil42\/playground\:v1/g' deployment.yaml
fi

git add deployment.yaml
git commit -m "change version to "$NEW_VERSION""
git push
