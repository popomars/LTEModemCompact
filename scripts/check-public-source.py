#!/usr/bin/env python3
"""Conservative staged-source audit. This is not a substitute for human review."""
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
def git(*args):
    return subprocess.check_output(['git', '-C', str(root), *args])

allowed_root = {'.gitignore', 'Package.swift', 'README.md', 'ROADMAP.md',
                'VALIDATION.md', 'CONTRIBUTING.md'}
allowed_dirs = {'Sources', 'Tests', 'Resources', 'scripts', 'docs'}
allowed_extensions = {'.swift', '.c', '.h', '.plist', '.sh', '.py', '.md'}
problems = []
entries = git('ls-files', '--stage', '-z').split(b'\0')
count = 0
for entry in entries:
    if not entry:
        continue
    metadata, raw_path = entry.split(b'\t', 1)
    mode, blob, stage = metadata.decode().split()
    name = raw_path.decode()
    path = pathlib.PurePosixPath(name)
    count += 1
    if mode not in {'100644', '100755'} or stage != '0':
        problems.append((name, 'symlink, submodule or unresolved index entry'))
        continue
    if name not in allowed_root and not (path.parts[0] in allowed_dirs and path.suffix in allowed_extensions):
        problems.append((name, 'not an approved public source path'))
    data = git('cat-file', 'blob', blob)
    if len(data) > 256 * 1024 or b'\0' in data:
        problems.append((name, 'binary or unusually large file'))
        continue
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        problems.append((name, 'not UTF-8 text'))
        continue
    checks = {
        'personal absolute path': r'/(?:Users|home)/[A-Za-z0-9_.-]+/',
        'mainland mobile number': r'(?<![0-9])1[3-9][0-9]{9}(?![0-9])',
        'credential-shaped string': r'(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9_-]{24,})',
        'private key material': r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
        'email address': r'\b[A-Za-z0-9_.+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
    }
    for label, expression in checks.items():
        if re.search(expression, text):
            problems.append((name, label))
    for candidate in re.findall(r'(?<![A-Za-z0-9])[0-9]{15,22}(?![A-Za-z0-9])', text):
        # Explicitly synthetic SIM identifiers in the in-memory modem tests.
        if not (path.parts[0] == 'Tests' and re.fullmatch(r'99990{13}[0-9]{2}', candidate)):
            problems.append((name, 'long numeric identifier'))
if not count:
    sys.exit('No staged source files to audit.')
for name, reason in problems:
    print(f'{name}: {reason}', file=sys.stderr)
if problems:
    sys.exit(1)
print(f'Checked {count} staged text files; no blocked paths or common sensitive patterns found.')
