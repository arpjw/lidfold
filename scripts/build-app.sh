#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
configuration=${CONFIGURATION:-release}
marketing_version=${MARKETING_VERSION:-0.1.0}
build_number=${CURRENT_PROJECT_VERSION:-0}
output_root="$project_root/dist"
app_dir="$output_root/LidFold.app"
contents_dir="$app_dir/Contents"

cd "$project_root"
swift build -c "$configuration" --product LidFold
binary_dir=$(swift build -c "$configuration" --show-bin-path)

rm -rf "$app_dir"
mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$binary_dir/LidFold" "$contents_dir/MacOS/LidFold"
cp "$project_root/Resources/Info.plist" "$contents_dir/Info.plist"
cp "$project_root/Resources/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"
cp "$project_root/Resources/PrivacyInfo.xcprivacy" "$contents_dir/Resources/PrivacyInfo.xcprivacy"

plutil -replace CFBundleShortVersionString -string "$marketing_version" "$contents_dir/Info.plist"
plutil -replace CFBundleVersion -string "$build_number" "$contents_dir/Info.plist"

codesign --force --sign "${CODESIGN_IDENTITY:--}" "$app_dir"
echo "$app_dir"
