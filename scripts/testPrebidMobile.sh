if [ -d "scripts" ]; then
cd scripts/
fi

# Flags:
# --latest:             run tests only for the latest iOS.
#                       It is needed for the GitHub Actions builds.
#                       Do not use this flag locally to keep everything updated.
# --quick:              run only quick set of tests for PR.
#                       It is needed for the GitHub Actions builds on every PR to avoid running all tests.
# --concurrency:        run only the concurrency suites, under Thread Sanitizer, with retries disabled.
#                       Kept separate because TSan runs 5-15x slower.

run_only_with_latest_ios="NO"
run_only_PR_tests="NO"
run_concurrency_tests="NO"

usage() {
  cat <<'USAGE'
Usage: testPrebidMobile.sh [--latest] [--quick] [--concurrency]
USAGE
}

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --latest)         run_only_with_latest_ios="YES"; shift ;;
    --quick)          run_only_PR_tests="YES"; shift ;;
    --concurrency)    run_concurrency_tests="YES"; shift ;;
    -h|--help)        usage; exit 0 ;;
    --)               shift; break ;;
    -*)               echo "Unknown option: $1" >&2; usage; exit 2 ;;
    *)                break ;;
  esac
done


set -e

# CocoaPods crashes with an Encoding::CompatibilityError when the locale is not
# UTF-8 (Ruby falls back to US-ASCII). Force a UTF-8 locale so `pod install` runs
# regardless of the inherited environment.
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

GREEN='\033[0;32m'
NC='\033[0m' # No Color

# --- Ephemeral test simulator -------------------------------------------------
# These own the purge/create/delete strategy; callers pass only the device name and
# type, and pair provision with `trap remove_test_simulator EXIT`.

# Creates a fresh simulator and publishes its UDID as $SIMULATOR_ID. A run that aborts
# before cleanup leaves its simulator behind, and duplicate same-named devices make
# xcodebuild's -destination ambiguous ("multiple devices matched") — so purge any
# leftovers first. Target the new device by UDID, never by name.
provision_test_simulator() {
    local name="$1"
    local device_type="$2"

    for leaked_id in $(xcrun simctl list devices | grep "$name" | grep -oE '[0-9A-F-]{36}'); do
        xcrun simctl delete "$leaked_id" || true
    done

    echo -e "\n${GREEN}Creating simulator${NC} \n"
    SIMULATOR_ID=$(xcrun simctl create "$name" "$device_type")
}

# Deletes the provisioned simulator. Registered as an EXIT trap *at top level* so it
# fires when a build/test step aborts under `set -e` — top level because zsh runs an
# in-function EXIT trap on function return, not on shell exit.
remove_test_simulator() {
    echo -e "\n${GREEN}Removing simulator${NC} \n"
    xcrun simctl delete "$SIMULATOR_ID" >/dev/null 2>&1 || true
}

echo -e "\n\n${GREEN}INSTALL PODS${NC}\n\n"

cd ..

export PATH="/Users/distiller/.gem/ruby/2.7.0/bin:$PATH"
gem install cocoapods
pod install --repo-update

echo -e "\n\n${GREEN}RUN PREBID MOBILE TESTS${NC}\n\n"

provision_test_simulator "iPhone-16-Pro-PrebidMobile" "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
trap remove_test_simulator EXIT

if [ "$run_only_PR_tests" != "YES" ]; then
    echo -e "\n${GREEN}Clean build\n"
    xcodebuild clean build
fi

if [ "$run_only_with_latest_ios" != "YES" ]
then
 echo -e "\n${GREEN}Running some unit tests for iOS 13${NC} \n"
 xcodebuild test \
    -workspace Life360AdsSDK.xcworkspace \
    -scheme "PrebidMobileTests" \
    -destination 'platform=iOS Simulator,name=iPhone 11 Pro Max,OS=13.7' \
    -only-testing PrebidMobileTests/RequestBuilderTests/testPostData

 if [[ ${PIPESTATUS[0]} == 0 ]]; then
     echo "✅ unit tests for iOS 13 Passed"
 else
     echo "🔴 unit tests for iOS 13 Failed"
     exit 1
 fi
fi

TESTPLAN=""
SANITIZER_ARGS=()
RETRY_ARGS=(-retry-tests-on-failure)

if [ "$run_concurrency_tests" == "YES" ]; then
    TESTPLAN="PrebidMobileConcurrencyTests"
    # Thread Sanitizer must be on for build-for-testing as well. Instrumenting only the test run
    # leaves the binary uninstrumented, and the run reports nothing.
    SANITIZER_ARGS=(-enableThreadSanitizer YES)
    # No retries here. A concurrency regression is intermittent by nature, so a retry that happens to
    # pass would report green and hide exactly what this plan exists to catch.
    RETRY_ARGS=()
elif [ "$run_only_PR_tests" != "YES" ]; then
    TESTPLAN="PrebidMobileTests"
else
    TESTPLAN="PrebidMobilePRTests"
fi

echo -e "\n${GREEN}Running PrebidMobile unit tests (${TESTPLAN})${NC} \n"

xcodebuild \
    -workspace Life360AdsSDK.xcworkspace \
    -scheme PrebidMobileTests \
    -sdk iphonesimulator \
    -configuration Debug \
    -destination "id=$SIMULATOR_ID" \
    -destination-timeout 60 \
    "${SANITIZER_ARGS[@]}" \
    build-for-testing

xcodebuild \
    -workspace Life360AdsSDK.xcworkspace \
    -scheme PrebidMobileTests \
    -sdk iphonesimulator \
    -testPlan "${TESTPLAN}" \
    -destination "id=$SIMULATOR_ID" \
    -destination-timeout 60 \
    "${SANITIZER_ARGS[@]}" \
    "${RETRY_ARGS[@]}" \
    test-without-building

if [[ ${PIPESTATUS[0]} == 0 ]]; then
    echo "✅ PrebidMobile Unit Tests Passed"
else
    echo "🔴 PrebidMobile Unit Tests Failed"
    exit 1
fi

# Simulator cleanup is handled by the EXIT trap registered after creation.

# echo -e "\n${GREEN}Running swiftlint tests${NC} \n"
# swiftlint --config .swiftlint.yml
