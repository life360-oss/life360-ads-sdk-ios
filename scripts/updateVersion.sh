#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    echo "Usage: updateVersion.sh [<version>] [--gam-version <X.Y.Z>]"
    echo "  version            App release version, e.g. 1.0.0 or 1.0.0-alpha.1"
    echo "  --gam-version      Latest tested Google Mobile Ads (GMA) SDK version, e.g. 13.5.0"
    echo
    show_current
    exit 1
}

# Print the versions currently declared in the sources, so the script can answer
# "what are we on?" without having to grep through the Swift files by hand.
show_current() {
    local constants checker sdk_version gam_version
    constants="$ROOT_DIR/PrebidMobile/Swift/Constants.swift"
    checker="$ROOT_DIR/PrebidMobile/Swift/ConfigurationAndTargeting/PrebidGAMVersionChecker.swift"

    sdk_version="$(sed -n 's/.*public static let VERSION[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$constants" | head -1)"
    gam_version="$(sed -n -E '/latestTestedGMAVersion/,/}/ s/^[[:space:]]*\(([0-9]+),[[:space:]]*([0-9]+),[[:space:]]*([0-9]+)\)[[:space:]]*$/\1.\2.\3/p' "$checker" | head -1)"

    echo "  Current:  ${sdk_version:-unknown}"
    echo "  GAM:      ${gam_version:-unknown}"
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

# The GMA SDK version is split into integer major/minor/patch in the Swift sources,
# so it must be a plain three-part numeric version (no pre-release/build metadata).
validate_gam_version() {
    local version="$1"
    if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        echo "Error: '$version' is not a valid GMA SDK version."
        echo "Expected format: MAJOR.MINOR.PATCH (e.g. 13.5.0)"
        exit 1
    fi
}

# Fail loudly if a sed-based replacement didn't take, so a future change to the
# source format can't silently leave a stale GMA version behind (the kind of miss
# that breaks the adapter version-check tests).
assert_contains() {
    local file="$1" needle="$2"
    if ! grep -qF "$needle" "$file"; then
        echo "Error: expected '$needle' in $file after update, but it was not found."
        echo "The file format may have changed; update updateVersion.sh."
        exit 1
    fi
}

# No arguments: report the current versions, then show usage for reference.
if [[ $# -eq 0 ]]; then
    echo
    usage
    exit 0
fi

NEW_VERSION=""
GAM_VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --gam-version)       GAM_VERSION="${2:-}"; shift 2 ;;
        --gam-version=*)     GAM_VERSION="${1#*=}"; shift ;;
        -h|--help)           usage ;;
        -*)                  echo "Unknown option: $1"; usage ;;
        *)
            if [[ -z "$NEW_VERSION" ]]; then
                NEW_VERSION="$1"; shift
            else
                echo "Unexpected argument: $1"; usage
            fi
            ;;
    esac
done

[[ -z "$NEW_VERSION" && -z "$GAM_VERSION" ]] && usage

# --- App release version ---
if [[ -n "$NEW_VERSION" ]]; then
    validate_semver "$NEW_VERSION"
    echo "Updating version to: $NEW_VERSION"

    # --- Constants.swift ---
    CONSTANTS="$ROOT_DIR/PrebidMobile/Swift/Constants.swift"
    sed -i '' 's/\(public static let VERSION[[:space:]]*=[[:space:]]*"\)[^"]*"/\1'"$NEW_VERSION"'"/' "$CONSTANTS"
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
fi

# --- Latest tested GMA SDK version ---
# This value is hard-coded in three Swift sources that warn / fail tests when the
# installed GMA SDK is newer than what has been validated. They must be kept in sync
# with the Google-Mobile-Ads-SDK pulled in by CocoaPods/SPM.
if [[ -n "$GAM_VERSION" ]]; then
    validate_gam_version "$GAM_VERSION"
    echo "Updating tested GMA SDK version to: $GAM_VERSION"

    GAM_MAJOR="${GAM_VERSION%%.*}"
    GAM_REST="${GAM_VERSION#*.}"
    GAM_MINOR="${GAM_REST%%.*}"
    GAM_PATCH="${GAM_REST##*.}"

    # 1. Tuple form: `latestTestedGMAVersion: (Int, Int, Int) { (13, 5, 0) }`
    CHECKER="$ROOT_DIR/PrebidMobile/Swift/ConfigurationAndTargeting/PrebidGAMVersionChecker.swift"
    sed -i '' -E '/latestTestedGMAVersion/,/}/ s/^([[:space:]]*)\([0-9]+,[[:space:]]*[0-9]+,[[:space:]]*[0-9]+\)([[:space:]]*)$/\1('"$GAM_MAJOR, $GAM_MINOR, $GAM_PATCH"')\2/' "$CHECKER"
    assert_contains "$CHECKER" "($GAM_MAJOR, $GAM_MINOR, $GAM_PATCH)"
    echo "  Updated: PrebidMobile/Swift/ConfigurationAndTargeting/PrebidGAMVersionChecker.swift"

    # 2 & 3. VersionNumber form: `VersionNumber(majorVersion: 13, minorVersion: 5, patchVersion: 0)`
    for src in \
        "$ROOT_DIR/EventHandlers/PrebidMobileGAMEventHandlers/Sources/GAMUtils.swift" \
        "$ROOT_DIR/EventHandlers/PrebidMobileAdMobAdapters/Sources/PrebidAdMobMediationBaseAdapter.swift"
    do
        sed -i '' -E '/latestTestedGMAVersion/,/}/ s/(majorVersion:[[:space:]]*)[0-9]+/\1'"$GAM_MAJOR"'/' "$src"
        sed -i '' -E '/latestTestedGMAVersion/,/}/ s/(minorVersion:[[:space:]]*)[0-9]+/\1'"$GAM_MINOR"'/' "$src"
        sed -i '' -E '/latestTestedGMAVersion/,/}/ s/(patchVersion:[[:space:]]*)[0-9]+/\1'"$GAM_PATCH"'/' "$src"
        assert_contains "$src" "majorVersion: $GAM_MAJOR"
        assert_contains "$src" "minorVersion: $GAM_MINOR"
        assert_contains "$src" "patchVersion: $GAM_PATCH"
        echo "  Updated: ${src#"$ROOT_DIR/"}"
    done

    echo "Done. Tested GMA SDK version is now $GAM_VERSION"
fi
