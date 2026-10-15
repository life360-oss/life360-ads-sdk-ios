#!/usr/bin/env python3
"""Re-applies the Life360 module rename to Swift files written against upstream.

Upstream imports `PrebidMobile` (and `PrebidMobileGAMEventHandlers` etc.); this fork's modules are
`Life360AdsSDK*`. Rewrites import lines and `PrebidMobile.SomeType` qualifiers in place, leaving
type names such as `PrebidMobilePluginRegister` untouched.

Usage:
  apply-life360-module-rename.py FILE...            rewrite the given files
  apply-life360-module-rename.py --resolve FILE...  for each conflicted FILE whose Life360 side
                                                    differs from the merge base only by the rename,
                                                    take upstream's version, re-apply the rename,
                                                    and `git add` it; prints what it resolved
"""
import re
import subprocess
import sys

IMPORT = re.compile(r'(import\s+)PrebidMobile(GAMEventHandlers|AdMobAdapters|MAXAdapters)?[ \t]*$', re.M)
QUALIFIER = re.compile(r'(?<![\w"/.])PrebidMobile\.(?=[A-Z])')


def rename(text: str) -> str:
    text = IMPORT.sub(r'\1Life360AdsSDK\2', text)
    return QUALIFIER.sub('Life360AdsSDK.', text)


def stage(path: str, n: int):
    result = subprocess.run(['git', 'show', f':{n}:{path}'], capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else None


def resolve(path: str) -> bool:
    base, ours, theirs = stage(path, 1), stage(path, 2), stage(path, 3)
    if None in (base, ours, theirs):
        return False
    if ours.replace('Life360AdsSDK', 'PrebidMobile') != base:
        return False
    with open(path, 'w') as f:
        f.write(rename(theirs))
    subprocess.run(['git', 'add', '--', path], check=True)
    return True


def main(argv):
    if argv and argv[0] == '--resolve':
        for path in argv[1:]:
            if resolve(path):
                print(f'resolved {path}')
        return
    for path in argv:
        with open(path) as f:
            text = f.read()
        renamed = rename(text)
        if renamed != text:
            with open(path, 'w') as f:
                f.write(renamed)
            print(f'renamed {path}')


if __name__ == '__main__':
    main(sys.argv[1:])
