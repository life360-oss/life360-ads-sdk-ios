#!/usr/bin/env python3
"""Finds build-phase entries a project-file merge dropped.

A merged project.pbxproj can keep a file's PBXBuildFile definition yet lose its line in the
Sources/Headers/Resources/Frameworks phase list. Xcode then silently stops compiling the file,
which surfaces later as an undefined-symbol link error. Compares every phase in the merged file
against the same phase in both parents and prints entries a parent had that the merge lost.

Usage: audit-build-phases.py PROJECT.pbxproj [ours-rev] [theirs-rev]
  The revisions default to HEAD^1 and HEAD^2 (the parents of a merge commit). Before committing
  the merge, pass HEAD and MERGE_HEAD.

Output: "<parent>\t<phase name> <phase id>\t<build file id>\t<build file name>", or nothing.
"""
import re
import subprocess
import sys


def parse(text):
    build_files = {
        m.group(1): m.group(2)
        for m in re.finditer(r'^\t\t([0-9A-F]{24}) /\* (.+?) \*/ = \{isa = PBXBuildFile;', text, re.M)
    }
    phases = {}
    for m in re.finditer(
        r'^\t\t([0-9A-F]{24}) /\* (\w+) \*/ = \{\n\t\t\tisa = (PBX\w+BuildPhase);.*?files = \((.*?)\);',
        text, re.M | re.S,
    ):
        phases[m.group(1)] = (m.group(2), set(re.findall(r'([0-9A-F]{24}) /\*', m.group(4))))
    return build_files, phases


def at_revision(rev, path):
    return subprocess.run(['git', 'show', f'{rev}:{path}'], capture_output=True, text=True, check=True).stdout


def main(argv):
    path = argv[0]
    revs = (argv[1] if len(argv) > 1 else 'HEAD^1', argv[2] if len(argv) > 2 else 'HEAD^2')
    with open(path) as f:
        merged_files, merged_phases = parse(f.read())
    for label, rev in zip(('ours', 'theirs'), revs):
        _, parent_phases = parse(at_revision(rev, path))
        for phase_id, (name, files) in merged_phases.items():
            if phase_id not in parent_phases:
                continue
            for build_file in sorted(parent_phases[phase_id][1] - files):
                if build_file in merged_files:
                    print(f'{label}\t{name} {phase_id}\t{build_file}\t{merged_files[build_file]}')


if __name__ == '__main__':
    main(sys.argv[1:])
