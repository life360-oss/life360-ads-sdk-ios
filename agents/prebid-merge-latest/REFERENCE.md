# Prebid merge reference

Reference for [SKILL.md](SKILL.md): what must survive a merge, how to resolve each kind of conflict, and the traps found in past merges.

## Life360 invariants

These values are Life360's identity in requests and builds. After resolving, each must still hold. Upstream will keep re-introducing the Prebid value.

| What | Life360 value | Upstream value |
|---|---|---|
| Swift module / SPM product | `Life360AdsSDK`, `Life360AdsSDK{GAMEventHandlers,AdMobAdapters,MAXAdapters}` | `PrebidMobile…` |
| Workspace in scripts | `Life360AdsSDK.xcworkspace` | `PrebidMobile.xcworkspace` |
| OM SDK framework | `Frameworks/OMSDK_Life360.xcframework` | `OMSDK_Prebidorg.xcframework` |
| `app.ext.prebid.source`, `imp.displaymanager` | `PrebidConstants.SDK_NAME` (`life360-ads-sdk`) | `"prebid-mobile"` |
| `app.ext.prebid.version`, `Functions.sdkVersion`, `omidpv` | `PrebidConstants.VERSION` | `PREBID_VERSION` / `Prebid.shared.version` |
| `source.ext.omidpn` | `"Life360"`, also for native on the original API | `"Prebid"`, rendering API only |
| Native OM `imp.native.api` | from `nativeAdConfiguration.api` | not sent |
| Bundle ID in tests | `com.life360.ads` | `org.prebid.mobile` |
| `sdk` field in MRAID env tests | `life360-ads-sdk` | `prebid-mobile-sdk` |
| GAM version warning | "…Life360 Ads SDK… or post a ticket on the github." | "…Prebid SDK…" |
| Renderer name | `NativoRenderer` (kept for the Prebid Server Nativo module) | — |

Life360-only code lives under `PrebidMobile/Swift/Life360/` and `PrebidMobile/Objc/Life360/`. Upstream never touches it, so it merges cleanly, and that's exactly why it breaks silently when an upstream type it depends on changes. Check it compiles against the merged upstream.

## Conflict rules

- **Rename-only.** If the Life360 side differs from the base only by `PrebidMobile` → `Life360AdsSDK`, take upstream's file and re-apply the rename (`scripts/apply-life360-module-rename.py --resolve`).
- **Both sides changed.** State each side's intent in one sentence before editing. Keep upstream's structure and fold the Life360 behavior into it, so the next merge has less to reconcile. Example: upstream moved `BidResponse`'s winner selection into helpers, while Life360 had made bid creation overridable for `Life360BidResponse`. The merge keeps both.
- **Same fix on both sides.** When upstream fixed the bug Life360 had patched (e.g. the millisecond/second timeout bug, #1325), take upstream's code and tests and drop the Life360 duplicates.
- **Modify/delete.** Upstream deleted a file Life360 had edited. Accept the deletion and port the Life360 edit into the Swift replacement (SKILL.md step 5). Keeping the ObjC file alive next to its Swift replacement leaves two implementations.
- **Life360 ObjC on migrated upstream code.** ObjC cannot subclass a Swift class, and the deleted ObjC headers are gone. Port the Life360 class to Swift. When the port removes the reason for an `NSClassFromString` lookup in `Factory` or a bridging protocol, remove those too.
- **Upstream signature changes reach Life360 code and tests.** Watch for protocol return types (`createBannerView` now returns `(UIView & PrebidMobileDisplayViewProtocol)?`), required initializers on classes Life360 extended (`AdLoadFlowController` takes `life360BidRequesterFactory`), and protocol members Life360 added that upstream's Swift rewrite lacks (`ModalState.onStateWillPop`).
- **Scripts and CI.** Take upstream's improvements, then restore the invariants: workspace name, OM SDK path, the UTF-8 locale export, and the UDID-targeted simulator with EXIT-trap cleanup in `scripts/testPrebidMobile.sh`. New upstream CI jobs often hard-code Prebid paths: grep the merged `.github/` and `scripts/` for `PrebidMobile.xcworkspace` and `OMSDK_Prebidorg`.
- **Project files.** A merged `project.pbxproj` can keep a file's build-file entry but drop it from its build phase. Run `scripts/audit-build-phases.py` for `PrebidMobile.xcodeproj` and `EventHandlers/EventHandlers.xcodeproj`. In EventHandlers, upstream's `Pods_PrebidMobile*` entries are expected to differ; `pod install` re-points them at the `Life360AdsSDK*` targets.
- **Packages.** Upstream deletes `Package.resolved` files. Xcode regenerates the workspace one with a new `originHash`, so leave it out of commits.

## Verification setup

**Baseline worktree.** The workspace refers to a local package by the relative path `../life360-ads-sdk-ios`, so the worktree folder must have that exact name, and `Pods/` is git-ignored:

```bash
mkdir -p /tmp/prebid-baseline
git worktree add --detach /tmp/prebid-baseline/life360-ads-sdk-ios origin/develop
(cd /tmp/prebid-baseline/life360-ads-sdk-ios && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install)
# build-for-testing and test-without-building there with -only-testing for the failing classes
git worktree remove --force /tmp/prebid-baseline/life360-ads-sdk-ios
```

Give each build its own `-derivedDataPath` so the two trees don't share products.

**Simulator.** The scripts create `iPhone-17-Pro-PrebidMobile`. If that device type isn't installed, target an existing simulator by UDID (`xcrun simctl list devices available`), and use the same one for both trees.

**Known environmental failures.** `PrebidTest.testInitializeSDK` and `PrebidServerStatusRequesterTests.testRequestStatus_Success` call `prebid-server-test-j.prebid.org` and fail with a TLS certificate error on networks that intercept TLS. Confirm the message before dismissing them.

**Request fields to diff.** Life360 values from the invariants table, `tagid`, `app.bundle` (the bundle ID on the Life360 request; the iTunes ID on Prebid Server requests), `user.id` (`publisherUserId`, Life360 request only), `device.geo` (needs `shareGeoLocationWithLife360`, location permission, and a simulator location), and `user.eids` / `user.ext.eids` (placement follows `Prebid.shared.eidsPlacement`). Native ads currently go to Prebid Server only; the Life360 exchange gets banner.

## Shell pitfalls

- zsh reads `$c:path` as a path modifier. Write `"${c}:path"` in `git show "${rev}:${file}"`.
- zsh doesn't word-split `$VAR`. Pass file lists through a file and `$(cat list)` or `xargs`.
- `git stash` takes the user's uncommitted work and untracked-but-staged files with it. To compare against another revision, use a worktree.
- `git stash -- <paths>` on a staged new file removes it from disk; the Life360AdsDemo shared scheme went missing this way once.
