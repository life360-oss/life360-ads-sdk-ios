#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    echo "Usage: $0 <version>"
    echo "  version  Semantic version string, e.g. 1.0.0 or 1.0.0-alpha.1"
    exit 1
}

# Validate semver: MAJOR.MINOR.PATCH with optional pre-release and build metadata
validate_semver() {
    local version="$1"
    local semver_regex='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$'
    if [[ ! "$version" =~ $semver_regex ]]; then
        echo "Error: '$version' is not a valid semantic version."
        echo "Expected format: MAJOR.MINOR.PATCH[-prerelease][+buildmeta]"
        echo "Examples: 1.0.0  |  1.0.0-alpha.1  |  2.3.0-rc.1+build.42"
        exit 1
    fi
}

[[ $# -ne 1 ]] && usage

NEW_VERSION="$1"
validate_semver "$NEW_VERSION"

echo "Updating version to: $NEW_VERSION"

# --- Constants.swift ---
CONSTANTS="$ROOT_DIR/PrebidMobile/Swift/Constants.swift"
sed -i '' 's/\(public static let PREBID_VERSION[[:space:]]*=[[:space:]]*"\)[^"]*"/\1'"$NEW_VERSION"'"/' "$CONSTANTS"
echo "  Updated: PrebidMobile/Swift/Constants.swift"

# --- CocoaPods podspecs ---
for podspec in \
    "$ROOT_DIR/Life360AdsSDK.podspec" \
    "$ROOT_DIR/Life360AdsSDKAdMobAdapters.podspec" \
    "$ROOT_DIR/Life360AdsSDKGAMEventHandlers.podspec" \
    "$ROOT_DIR/Life360AdsSDKMAXAdapters.podspec"
do
    # s.version line
    sed -i '' 's/\(s\.version[[:space:]]*=[[:space:]]*"\)[^"]*"/\1'"$NEW_VERSION"'"/' "$podspec"
    # dependency on Life360AdsSDK with pinned version
    sed -i '' "s/'Life360AdsSDK', '[^']*'/'Life360AdsSDK', '$NEW_VERSION'/" "$podspec"
    echo "  Updated: $(basename "$podspec")"
done

# --- Xcode project (CURRENT_PROJECT_VERSION for the PrebidMobile target only) ---
PBXPROJ="$ROOT_DIR/PrebidMobile.xcodeproj/project.pbxproj"
sed -i '' "s/CURRENT_PROJECT_VERSION = \"1\.[^\"]*\";/CURRENT_PROJECT_VERSION = \"$NEW_VERSION\";/g" "$PBXPROJ"
echo "  Updated: PrebidMobile.xcodeproj/project.pbxproj"

echo "Done. Version is now $NEW_VERSION"
