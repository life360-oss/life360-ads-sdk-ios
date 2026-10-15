---
name: prebid-merge-latest
description: Merge the latest prebid/master into a new branch off develop, port Life360 changes onto upstream's rewrites, verify, and open a PR.
disable-model-invocation: true
---

Merge upstream Prebid (`prebid/master`) into this fork on a fresh branch, keeping both sides' intent. Upstream keeps rewriting ObjC classes in Swift, and the Life360 edits to those classes are where merges silently lose work, so most of this procedure exists to catch dropped edits.

Read [REFERENCE.md](REFERENCE.md) before step 4. It holds the Life360 invariants, the conflict rules, and the shell pitfalls.

Ground rules for the whole run:

- **Ask before every commit, push, or PR.** Each one is a separate approval; an approval for the merge commit does not cover the port.
- **Keep the user's working tree intact.** Get baselines from a `git worktree`, never from `git stash`. Leave untracked files you didn't create where they are.
- Report each step's result to the user as you finish it.

## 1. Start the branch

```bash
git status --short          # must be empty apart from files the user says to leave
git fetch origin
git fetch prebid            # remote prebid = git@github.com:prebid/prebid-mobile-ios.git
git switch -c prebid-merge-$(date +%Y-%m-%d) origin/develop
```

Add the `prebid` remote first if it's missing. Use the branch name the user gives, if any.

Done when: `git branch --show-current` prints the new branch, and it points at `origin/develop`.

## 2. Survey upstream before merging

```bash
git log --oneline HEAD..prebid/master
agents/prebid-merge-latest/scripts/find-dropped-life360-edits.sh
```

The second command lists every file Life360 modified that upstream deletes. Write that list down: each entry is a Life360 edit that disappears the moment you accept the deletion, and step 5 has to port every one. Also note upstream PRs titled "Swift Migration", CI, or release changes. Those drive most of the conflicts.

Done when: you've shown the user the upstream commit count, the dropped-edits list, and the Swift-migration PRs it includes.

## 3. Merge

```bash
git -c mergetool.keepBackup=false merge prebid/master
```

If anyone resolves conflicts with `git mergetool`, delete its leftovers before building: `*.orig` and `*_BACKUP_/_BASE_/_LOCAL_/_REMOTE_<digits>.*`. SPM compiles every file under `PrebidMobile/`, so a leftover `Foo_BACKUP_123.swift` breaks the SPM build even when Xcode builds.

Done when: `git diff --name-only --diff-filter=U` lists the conflicted files.

## 4. Resolve conflicts by intent

Follow the conflict rules in REFERENCE.md. In order:

1. Resolve conflicts that are only the module rename:
   `agents/prebid-merge-latest/scripts/apply-life360-module-rename.py --resolve $(git diff --name-only --diff-filter=U)`
2. Re-apply the rename to upstream's new or cleanly merged Swift files that still `import PrebidMobile`:
   `grep -rlE 'import PrebidMobile(GAMEventHandlers|AdMobAdapters|MAXAdapters)?\s*$|PrebidMobile\.[A-Z]' PrebidMobileTests EventHandlers/*Tests --include='*.swift' | xargs agents/prebid-merge-latest/scripts/apply-life360-module-rename.py`
3. Resolve the remaining conflicts one at a time. Compare base, ours, and theirs (`git show :1:<path>`, `:2:`, `:3:`), state each side's intent in a sentence, and merge so both survive.
4. Accept upstream's deletions of migrated ObjC files. Their Life360 edits are ported in step 5, not kept in ObjC.
5. Run the project audit and fix every line it prints:
   `python3 agents/prebid-merge-latest/scripts/audit-build-phases.py PrebidMobile.xcodeproj/project.pbxproj HEAD MERGE_HEAD`

Done when: `git diff --name-only --diff-filter=U` is empty, no conflict markers remain (`git grep -n '^<<<<<<< '`), the audit prints nothing, and every resolved Swift file passes `xcrun swiftc -parse`.

Then ask the user whether to commit the merge. It's normal for the SDK not to build at this commit, so say so in the commit message.

## 5. Port the dropped Life360 edits

For every entry on the step 2 list, find the Swift file that replaced it and port the Life360 edit there. Some will already be covered by an equivalent upstream fix; check before porting. Then check the Life360 ObjC classes (`PrebidMobile/Objc/Life360/`, `PrebidMobile/Objc/PrivateHeaders/Life360*.h`) for imports of headers upstream deleted:

```bash
for f in PrebidMobile/Objc/Life360/*.m PrebidMobile/Objc/PrivateHeaders/Life360*.h; do
  for h in $(grep -oE '#import "[^"]+"' "$f" | sed 's/#import "//;s/"//'); do
    [ -n "$(find PrebidMobile -name "$h" | head -1)" ] || echo "$f -> missing $h"
  done
done
```

Any class it flags moves to Swift under `PrebidMobile/Swift/Life360/`. Add new Swift files to the `Life360AdsSDK` target's Sources phase in `PrebidMobile.xcodeproj`, since the project lists files explicitly.

Done when: every step 2 entry is ported or confirmed covered upstream, the import check prints nothing, and the test target builds (step 6).

## 6. Verify

Run all of these and report each result:

1. `pod install` so `Pods/Manifest.lock` matches `Podfile.lock`. Plain `pod install` works when `--repo-update` fails on the CocoaPods CDN.
2. SDK and test build: `build-for-testing` on scheme `PrebidMobileTests` in `Life360AdsSDK.xcworkspace`.
3. PR and full test plans (see `agents/xcodebuild/SKILL.md`). For each failure, run the same test class on `origin/develop` in a worktree to tell **regressions** from pre-existing failures. Only regressions block.
4. Adapter tests: `PrebidMobileGAMEventHandlersTests`, `PrebidMobileAdMobAdaptersTests`, `PrebidMobileMAXAdaptersTests`.
5. SPM: `./scripts/buildPrebidMobilePackage.sh`.
6. Demo app: scheme `Life360AdsDemo`.
7. Ask the user to capture the Life360 banner request (to `exchange.postrelease.com`) before and after, then diff them. Expect only the per-request IDs (`id`, `imp[].id`, `source.tid`) to change. Explain every other difference.

Baseline worktree setup is in REFERENCE.md.

Done when: every check passes or each failure is shown to also fail on `origin/develop` (or to be environmental, such as a network error), and the request diff is explained.

## 7. Commit the port and open the PR

Ask before committing the port and before pushing. Leave the user's demo test settings and the regenerated workspace `Package.resolved` out of the commit unless they ask. Then:

```bash
git push -u origin <branch>
gh pr create --repo life360-oss/life360-ads-sdk-ios --base develop --head <branch>
```

The PR description lists both commits, the upstream behavior changes that reach Life360 requests, and a test plan with each step 6 result. Mark anything not run as unchecked.

Done when: the PR URL is shared with the user.
