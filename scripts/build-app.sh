#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
dist_dir="$repo_root/dist"
app_path="$dist_dir/CodexQuotaIsland.app"
contents_path="$app_path/Contents"

cd "$repo_root"
swift build -c release

mkdir -p "$contents_path/MacOS"
cp "$repo_root/.build/release/CodexQuotaIsland" "$contents_path/MacOS/CodexQuotaIsland"
cp "$repo_root/Resources/Info.plist" "$contents_path/Info.plist"

codesign --force --deep --sign - "$app_path"
ditto -c -k --keepParent "$app_path" "$dist_dir/CodexQuotaIsland.zip"

echo "Built: $dist_dir/CodexQuotaIsland.zip"
