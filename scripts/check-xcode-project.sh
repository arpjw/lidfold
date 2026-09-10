#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
project_file="$project_root/LidFold.xcodeproj/project.pbxproj"
status=0

plutil -lint "$project_file" "$project_root/Resources/Info.plist" "$project_root/Resources/PrivacyInfo.xcprivacy"

for source_path in "$project_root"/Sources/LidFold/*.swift "$project_root"/Tests/LidFoldTests/*.swift; do
    source_name=$(basename "$source_path")
    source_membership_count=$(grep -Fc "$source_name in Sources" "$project_file" || true)
    if [ "$source_membership_count" -lt 2 ]; then
        echo "error: $source_name is not in an Xcode Sources build phase" >&2
        status=1
    fi
done


for resource_name in Assets.xcassets PrivacyInfo.xcprivacy; do
    resource_membership_count=$(grep -Fc "$resource_name in Resources" "$project_file" || true)
    if [ "$resource_membership_count" -lt 2 ]; then
        echo "error: $resource_name is not in the app Resources build phase" >&2
        status=1
    fi
done

exit "$status"
