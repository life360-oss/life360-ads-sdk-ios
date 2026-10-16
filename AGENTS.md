# AGENTS.md

Canonical instructions for AI coding agents working in this repository. Codex, Cursor, and Copilot
read this file directly; Claude Code reaches it via the `@AGENTS.md` import in `CLAUDE.md`.

## Overview

**Life360 Ads SDK** (`life360-oss/life360-ads-sdk-ios`), a fork of the open-source
[Prebid Mobile iOS SDK](https://github.com/prebid/prebid-mobile-ios) maintained by Life360. Supports iOS 15+.
Distributed through CocoaPods (`Life360AdsSDK*.podspec`) and SPM (the root `Package.swift`), both
resolved from this repo's `vX.Y.Z` tags.

What the fork adds on top of Prebid:

- **Life360 demand.** Each ad load requests a bid from the Life360 exchange
  (`exchange.postrelease.com`, via `Life360BidRequester`) alongside Prebid Server, and the higher
  price wins (`AdLoadFlowController`). `Life360Ads.initializeWithoutPrebid()` runs Life360 demand
  only. The Life360 exchange currently takes banner only; native goes to Prebid Server.
- **Life360 rendering** through the `NativoRenderer` plugin renderer (`Life360RendererInternal`), with
  scroll-driven viewability (`Life360ViewExposureChecker`) and Open Measurement through the bundled
  `Frameworks/OMSDK_Life360.xcframework`.
- **Optional ad quality** through AppHarbr (`Life360AppHarbrQualityProvider`, CocoaPods subspec
  `AppHarbr`, `Frameworks/AppHarbrSDK.xcframework`).
- **Life360 identity in requests**: `life360-ads-sdk` as the SDK name, the Life360 SDK version, and
  `omidpn` `"Life360"`, instead of Prebid's values.

Most of the codebase is upstream Prebid code, still named `Prebid*` / `PBM*`, and it is merged in
regularly from `prebid/master`. Keep Life360 changes to upstream files small and grouped, because
every one has to be carried through each merge. New Life360 code goes in
`PrebidMobile/Swift/Life360/`. Use the `prebid-merge-latest` runbook for upstream merges.

## Agent runbooks (`agents/`)

Detailed procedures live in `agents/` as plain markdown, readable by any agent. Read the relevant
file before acting rather than improvising the commands.

Claude Code additionally loads these as Agent Skills through the committed `.claude/skills`
symlink, which points at `agents/`. `agents/` remains the single source of truth — do not duplicate
files under `.claude/`.

| Task | Read |
|------|------|
| Build the 4 XCFrameworks | `agents/build-sdk/SKILL.md` |
| Run tests, a single test class, or fix post-migration build errors | `agents/xcodebuild/SKILL.md` |
| Review a PR on this repo | `agents/review/SKILL.md` |
| Run SwiftLint | `agents/lint/SKILL.md` |
| CocoaPods install | `agents/pod-install/SKILL.md` |
| Merge the latest `prebid/master` into a new branch and port Life360 changes | `agents/prebid-merge-latest/SKILL.md` |
| Generic iOS/Swift background (not repo-specific; playbook wins on conflicts) | `agents/ios-development/SKILL.md` |
| Generic ObjC → Swift / XCTest migration background (playbook wins on conflicts) | `agents/migration-patterns/SKILL.md` |

## Commands

### Build

```bash
# Build all XCFrameworks (core SDK, GAM, AdMob, MAX) into generated/output/
./scripts/buildPrebidMobile.sh

# Compile the SPM package the way an SPM consumer does (run in PR checks)
./scripts/buildPrebidMobilePackage.sh
```

Requires CocoaPods installed (`pod` on PATH — GHA `macos-26` ships with it pre-installed). Build output goes to `generated/output/` as `XCLife360AdsSDK.xcframework`, `XCLife360AdsSDKGAMEventHandlers.xcframework`, `XCLife360AdsSDKAdMobAdapters.xcframework` and `XCLife360AdsSDKMAXAdapters.xcframework`. Logs go to `generated/log/prebid_mobile_build.log`. The script ends by running `./scripts/verifyXCFrameworkInterfaces.sh`, which typechecks each XCFramework's `.swiftinterface` files the way a consumer's compiler does; `xcodebuild` skips that check, so a broken interface otherwise archives cleanly. Build uses `Lib-`-prefixed scheme names (`Lib-PrebidMobile`, etc.) to avoid colliding with auto-generated SPM schemes; the products they build are the `Life360AdsSDK*` frameworks.

`buildPrebidMobilePackage.sh` is the only check that builds through `Package.swift` rather than the Xcode project. SPM compiles every file under `PrebidMobile/Swift` and `PrebidMobile/Objc` regardless of project membership, and ObjC reaches Swift through `@import Life360AdsSDK` (the `PrebidMobile_SPM` flag), so it catches breaks the Xcode build misses.

### Tests

```bash
# Run PR subset — used on PRs in CI
./scripts/testPrebidMobile.sh --latest --quick

# Run full suite — used on bump-to branches / run-full-tests label
./scripts/testPrebidMobile.sh --latest

# Run adapter tests (GAM, AdMob, MAX)
./scripts/testPrebidMobileAdapters.sh
```

Flags: `--latest` is a no-op kept for backward compatibility (the old iOS 13 sanity run is gone); `--quick` switches the test plan from `PrebidMobileTests` (full) to `PrebidMobilePRTests` (PR subset). The script creates the `iPhone-17-Pro-PrebidMobile` simulator, deleting any leftovers with that name first, runs `build-for-testing` then `test-without-building` with `-retry-tests-on-failure` against it by UDID, and deletes it on exit. If the iPhone 17 Pro device type isn't installed locally, run `xcodebuild` directly against an existing simulator's UDID.

Test plans: `PrebidMobileTests/PrebidMobileTests.xctestplan` (full) and `PrebidMobileTests/PrebidMobilePRTests.xctestplan` (PR subset), both on the `Life360AdsSDKTests` test target. The scheme is still named `PrebidMobileTests`.

**When adding new tests:** both plans select by *exclusion*, so a new test class runs on every PR without any registration step. `PrebidMobilePRTests.xctestplan` trims the suite via a `skippedTests` list — check that a new class isn't (prefix-)matched there, and add an entry only if you deliberately want it excluded from the PR subset.

Some tests fail on `develop` for reasons outside the change at hand, such as tests that call `prebid-server-test-j.prebid.org` on a network that intercepts TLS. Before treating a failure as a regression, run the same class on `origin/develop` in a separate `git worktree`.

To run a single test class:
```bash
# Step 1 — build once
xcodebuild \
  -workspace Life360AdsSDK.xcworkspace \
  -scheme PrebidMobileTests \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone-17-Pro-PrebidMobile,OS=latest' \
  build-for-testing

# Step 2 — run (repeat as needed without rebuilding)
xcodebuild \
  -workspace Life360AdsSDK.xcworkspace \
  -scheme PrebidMobileTests \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone-17-Pro-PrebidMobile,OS=latest' \
  -only-testing Life360AdsSDKTests/TargetingTests \
  test-without-building
```

See `agents/xcodebuild/SKILL.md` for a guided single-class run, and for the post-migration
build-error checklist.

### Setup

```bash
pod install --repo-update
```

Open `Life360AdsSDK.xcworkspace` (not an `.xcodeproj`) for development. When `--repo-update` fails on the CocoaPods CDN, plain `pod install` works if the specs are cached.

## Architecture

### Workspace structure

The workspace (`Life360AdsSDK.xcworkspace`) contains:
- `PrebidMobile.xcodeproj` — core SDK (`Life360AdsSDK` target) + unit tests (`Life360AdsSDKTests`)
- `EventHandlers/EventHandlers.xcodeproj` — ad network adapters
- `Example/Life360AdsDemo/Life360AdsDemo.xcodeproj` — the Life360 demo app (scheme `Life360AdsDemo`)
- `Example/PrebidDemo/PrebidDemo.xcodeproj` — upstream's Prebid demo apps
- `InternalTestApp/InternalTestApp.xcodeproj` — upstream's internal test app
- `Pods/Pods.xcodeproj`

### Core SDK (`PrebidMobile/`)

Upstream is migrating the ObjC layer to Swift in phases (see `docs/migration/`), so more of it moves into `PrebidMobile/Swift/` with each merge.

**`PrebidMobile/Swift/`**:
- `Life360/` — all Life360-specific Swift: `Life360Ads`, `Life360BidRequester`, `Life360BidResponse`, `Life360Bid`, `Life360ParameterBuilder`, `Life360GeoLocationParameterBuilder`, `Life360ViewExposureChecker`, `Life360RendererInternal` (in `Life360PrebidRendererInternal.swift`), `Life360AppHarbrQualityProvider`, `Life360Utils`
- `ConfigurationAndTargeting/` — `Prebid.swift` (SDK configuration singleton), `Targeting.swift` (user targeting)
- `AdUnits/` — `BannerAdUnit`, `InterstitialAdUnit`, `RewardedVideoAdUnit`, `InstreamVideoAdUnit`, `MultiformatAdUnit`; `AdUnits/Native/` for native
- `CacheManagement/` — bid caching layer
- `Host.swift` — Prebid Server endpoint configuration; `Global.swift` — shared error types; `Factory.swift` — creates bid requesters and other swappable components
- `PrebidMobileRendering/` — the rendering API and everything already migrated from ObjC: the OpenRTB request model (`Prebid/PBMCore/ORTB/Request/`, e.g. `ORTBBidRequest`, `ORTBImp`), the request parameter builders (`Networking/Parameters/`, `Prebid/PBMCore/PrebidParameterBuilder.swift`), `BidRequesterImpl`, `BidResponse`, VAST, video, ad view management, and viewability (`ExtensionsAndWrappers/Exposure/`)

**`PrebidMobile/Objc/`** — the ObjC that remains, mostly the rendering core:
- `PrebidMobileRendering/AdTypes/` — HTML creatives, MRAID, web view
- `PrebidMobileRendering/3dPartyWrappers/OpenMeasurement/` — OMSDK integration
- `PrebidMobileRendering/CreativeFactory/`, `PrebidMobileRendering/Prebid/`
- `Life360/Life360Utils.m` — the one remaining Life360 ObjC file
- `PrivateHeaders/` — headers for all of the above

ObjC reaches Swift through `SwiftImport.h`: `@import Life360AdsSDK` under SPM (the `PrebidMobile_SPM` compile flag), the generated `Life360AdsSDK-Swift.h` otherwise. Swift classes that ObjC uses keep their old ObjC names with `@objc(PBM…)`.

### Event Handlers / Adapters (`EventHandlers/`)

Thin wrappers that bridge bids into third-party ad SDKs. Folder names are upstream's; the modules are `Life360AdsSDK*`:
- `PrebidMobileGAMEventHandlers/` → `Life360AdsSDKGAMEventHandlers` — Google Ad Manager (GAM/DFP) banner, interstitial, rewarded
- `PrebidMobileAdMobAdapters/` → `Life360AdsSDKAdMobAdapters` — Google AdMob mediation adapters
- `PrebidMobileMAXAdapters/` → `Life360AdsSDKMAXAdapters` — AppLovin MAX adapters

GAM and AdMob have test targets (`*Tests/`). The MAX test scheme exists but has no test files.

### SPM vs CocoaPods layout

**SPM** (`Package.swift` at root): products `Life360AdsSDK`, `Life360AdsSDKGAMEventHandlers`, `Life360AdsSDKAdMobAdapters`, `Life360AdsSDKMAXAdapters`. The `Life360AdsSDK` product combines the `Life360AdsSDK` target (Swift sources) and the `__PrebidMobileInternal` target (ObjC sources). `__PrebidMobileInternal` depends on the binary target `PrebidMobileOMSDK` = `Frameworks/OMSDK_Life360.xcframework`. `EventHandlers/Package.swift` is upstream's separate adapters package (still `PrebidMobile*` names) and isn't how Life360 ships the adapters.

**CocoaPods**: `Life360AdsSDK.podspec` has a default `core` subspec pulling all `PrebidMobile/**/*.{h,m,swift}`, and an optional `AppHarbr` subspec. The adapters ship as `Life360AdsSDKGAMEventHandlers.podspec`, `Life360AdsSDKAdMobAdapters.podspec` and `Life360AdsSDKMAXAdapters.podspec`.

### Build schemes

Framework build uses `Lib-PrebidMobile`, `Lib-PrebidMobileGAMEventHandlers`, `Lib-PrebidMobileAdMobAdapters`, `Lib-PrebidMobileMAXAdapters` schemes (prefixed `Lib-` to avoid collision with auto-generated SPM schemes). They build the `Life360AdsSDK*` frameworks.

### CI

GitHub Actions (Xcode 26.5.0, macOS 26), `.github/workflows/PR_checks.yml`:
- PRs build the XCFrameworks and the SPM package, and run the adapter tests and the quick unit tests (the full suite instead when labeled `run-full-tests`)
- Branch names starting with `bump-to` trigger full test suite + UI/integration tests

`SPM.yml` is upstream's release flow: on version tags it syncs the packages to Prebid's own `prebid/prebid-mobile-ios-sdk` and `prebid/prebid-mobile-ios-adapters` repos. Life360 doesn't publish there. Life360 SPM consumers resolve this repo's root `Package.swift` directly.

## ObjC → Swift migration

`docs/migration/` is upstream's record of its ObjC → Swift migration, merged in from `prebid/master`. Read it when upstream's Swift rewrite of a class Life360 depends on needs explaining:

- **`docs/migration/playbook.md`** — per-class porting guide and gap decisions.
- **`docs/migration/pr-phase-<phases>.md`** — one file per upstream migration PR, with what was done and its test plan.

When an upstream merge rewrites a class Life360 had modified, port the Life360 change into the Swift version as part of the merge (see `agents/prebid-merge-latest/`). Life360 ports of Life360's own ObjC classes go to `PrebidMobile/Swift/Life360/`.
