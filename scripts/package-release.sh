#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=${VERSION:-${1:-}}
build_number=${BUILD_NUMBER:-1}
output_root=${OUTPUT_DIR:-"$project_root/dist"}
derived_data="$output_root/DerivedData"
products_dir="$derived_data/Build/Products/Release"
app_source="$products_dir/LidFold.app"
signing_identity=${SIGNING_IDENTITY:-}

if [ -z "$version" ]; then
    echo "usage: VERSION=1.2.3 $0 (or $0 1.2.3)" >&2
    exit 64
fi

case "$version" in
    v*) version=${version#v} ;;
esac

app_archive="$output_root/LidFold-${version}-macOS-universal.zip"
dmg_path="$output_root/LidFold-${version}-macOS-universal.dmg"
checksum_path="$output_root/SHA256SUMS.txt"

case "$version" in
    *[!0-9A-Za-z.-]* | "")
        echo "error: invalid version: $version" >&2
        exit 64
        ;;
esac

marketing_version=${version%%[-+]*}
if ! printf '%s\n' "$marketing_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "error: version must begin with three numeric components: $version" >&2
    exit 64
fi
if ! printf '%s\n' "$build_number" | grep -Eq '^[1-9][0-9]*$'; then
    echo "error: BUILD_NUMBER must be a positive integer: $build_number" >&2
    exit 64
fi

if ! command -v xcodebuild >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
    echo "error: packaging requires a full Xcode installation selected with xcode-select" >&2
    exit 69
fi

"$project_root/scripts/check-xcode-project.sh"

mkdir -p "$output_root"
rm -rf "$derived_data" "$app_archive" "$dmg_path" "$checksum_path"

xcodebuild \
    -project "$project_root/LidFold.xcodeproj" \
    -scheme LidFold \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$derived_data" \
    MARKETING_VERSION="$marketing_version" \
    CURRENT_PROJECT_VERSION="$build_number" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    build

if [ ! -d "$app_source" ]; then
    echo "error: Xcode did not produce $app_source" >&2
    exit 1
fi

architectures=$(lipo -archs "$app_source/Contents/MacOS/LidFold")
for required_architecture in arm64 x86_64; do
    case " $architectures " in
        *" $required_architecture "*) ;;
        *)
            echo "error: app is missing $required_architecture (found: $architectures)" >&2
            exit 1
            ;;
    esac
done

if [ -n "$signing_identity" ]; then
    echo "Signing LidFold.app with Developer ID"
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$signing_identity" \
        "$app_source"
    codesign --verify --deep --strict --verbose=2 "$app_source"
else
    echo "No SIGNING_IDENTITY supplied; applying an ad-hoc signature"
    codesign \
        --force \
        --deep \
        --sign - \
        "$app_source"
    codesign --verify --deep --strict --verbose=2 "$app_source"
fi

ditto -c -k --sequesterRsrc --keepParent "$app_source" "$app_archive"

dmg_stage=$(mktemp -d "${TMPDIR:-/tmp}/lidfold-dmg.XXXXXX")
trap 'rm -rf "$dmg_stage"' EXIT INT TERM
ditto "$app_source" "$dmg_stage/LidFold.app"
ln -s /Applications "$dmg_stage/Applications"
hdiutil create \
    -volname "LidFold $version" \
    -srcfolder "$dmg_stage" \
    -ov \
    -format UDZO \
    "$dmg_path"

if [ -n "$signing_identity" ]; then
    echo "Signing disk image with Developer ID"
    codesign --force --timestamp --sign "$signing_identity" "$dmg_path"
    codesign --verify --strict --verbose=2 "$dmg_path"
fi

(
    cd "$output_root"
    shasum -a 256 "$(basename "$app_archive")" "$(basename "$dmg_path")"
) > "$checksum_path"

echo "$app_archive"
echo "$dmg_path"
echo "$checksum_path"
