#!/usr/bin/env python3
"""Fail closed on likely private release content; never print matched values."""
import argparse
import json
import re
import struct
import subprocess
import sys
import tarfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
PRIVATE_PARTS = {
    '.git', '.work', 'work', '.build', 'build', 'dist', 'DerivedData', 'xcuserdata',
    'evidence', 'screenshots', 'recordings', 'Engine', 'Favicons', 'Profiles',
    '__pycache__', '.venv', 'venv', '.ssh', '.aws', '.gnupg',
}
PRIVATE_SUFFIXES = {
    '.app', '.dSYM', '.xcarchive', '.xcresult', '.xcodeproj', '.xcworkspace',
    '.log', '.db', '.sqlite', '.sqlite3', '.pem', '.key', '.p8', '.p12', '.pfx',
    '.cer', '.mobileprovision', '.provisionprofile', '.keychain', '.keychain-db',
    '.zip', '.gz', '.bz2', '.tar', '.mp4', '.mov', '.xcuserstate', '.pyc',
}
PRIVATE_NAMES = {
    '.DS_Store', '.netrc', '.npmrc', '.pypirc', 'LocalSigning.xcconfig',
    'Workspace.json', 'Workspace.backup.json', 'Workspace.recovered.json',
    'Local State', 'Cookies', 'Login Data', 'Web Data', 'History',
}
PATTERNS = {
    'private-key': r'-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----',
    'github-token': r'\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,})\b',
    'cloud-key': r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b',
    'service-key': r'\b(?:sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{24,}|AIza[0-9A-Za-z_-]{35})\b',
    'jwt': r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b',
    'personal-path': r'/(?:Users|home)/[A-Za-z0-9_.-]+|/(?:private/)?var/folders/[A-Za-z0-9_/.-]+',
    'private-design-link': r'figma\.com/(?:design|file)/[A-Za-z0-9]+',
    'signing-team': r'\b(?:DEVELOPMENT_TEAM|TeamIdentifier)\s*[=:]\s*["\x27]?[A-Z0-9]{10}\b',
    'literal-secret': r'(?i)\b(?:api[_-]?key|secret[_-]?key|client[_-]?secret|access[_-]?token|refresh[_-]?token|password)\s*[:=]\s*["\x27][A-Za-z0-9_+./=-]{12,}["\x27]',
}
EMAIL = re.compile(r'\b[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})\b')
URL_CREDENTIAL = re.compile(r'https?://[^\s/:@]+:[^\s/@]+@', re.I)


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def scan(name, data, mode='100644'):
    findings = []

    def add(category, line=None):
        row = {'path': name, 'category': category}
        if line is not None:
            row['line'] = line
        findings.append(row)

    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts:
        add('unsafe-path')
    if mode not in {'100644', '100755'}:
        add('symlink-or-non-file')
        return findings
    if any(p in PRIVATE_PARTS or Path(p).suffix in PRIVATE_SUFFIXES for p in path.parts):
        add('private-file-class')
    if path.name in PRIVATE_NAMES or path.name.startswith(('.env', 'Cookies-', 'Login Data-', 'History-')):
        if path.name != '.env.example':
            add('private-file-class')
    if len(data) > 2 * 1024 * 1024:
        add('oversized-unreviewed-file')
        return findings
    if path.suffix.lower() == '.png':
        try:
            if data[:8] != b'\x89PNG\r\n\x1a\n':
                raise ValueError('signature')
            offset = 8
            ended = False
            while offset < len(data):
                size = struct.unpack('>I', data[offset:offset + 4])[0]
                kind = data[offset + 4:offset + 8]
                if size > len(data) - offset - 12:
                    raise ValueError('length')
                if kind not in {b'IHDR', b'PLTE', b'IDAT', b'IEND', b'sRGB', b'gAMA', b'cHRM', b'pHYs', b'tRNS'}:
                    add('image-metadata-or-unknown-chunk')
                offset += size + 12
                if kind == b'IEND':
                    ended = True
                    break
            if not ended or offset != len(data):
                raise ValueError('trailing bytes')
        except (ValueError, struct.error):
            add('invalid-image')
        return findings
    try:
        text = data.decode('utf-8')
    except UnicodeError:
        add('unreviewed-binary')
        return findings
    for category, pattern in PATTERNS.items():
        for match in re.finditer(pattern, text):
            add(category, text.count('\n', 0, match.start()) + 1)
    for match in EMAIL.finditer(text):
        domain = match.group(1).lower()
        if domain not in {'example.com', 'example.org', 'example.net', 'users.noreply.github.com', 'github.com', 'phosphoricons.com'}:
            add('non-example-email', text.count('\n', 0, match.start()) + 1)
    for match in URL_CREDENTIAL.finditer(text):
        # Exact synthetic origin-normalization fixtures, never real credentials.
        synthetic = name == 'Tests/WorkspaceTests.swift' and re.match(
            r'https?://user:secret@example\.com(?::[0-9]+)?(?:[/\s"\x27]|$)', text[match.start():], re.I)
        if not synthetic:
            add('embedded-url-credential', text.count('\n', 0, match.start()) + 1)
    if path.suffix.lower() == '.svg' and re.search(r'<(?:script|foreignObject)\b|(?:href|src)=["\x27](?:https?:|file:|data:)', text, re.I):
        add('active-or-external-svg-content')
    return findings


def entries(args):
    if args.tree:
        for raw in git('ls-files', '-c', '-o', '--exclude-standard', '-z').split(b'\0'):
            if not raw:
                continue
            name = raw.decode()
            path = ROOT / name
            mode = '120000' if path.is_symlink() else '100644'
            if path.is_file() or path.is_symlink():
                yield name, path.read_bytes(), mode
    elif args.staged:
        for raw in git('ls-files', '--stage', '-z').split(b'\0'):
            if not raw:
                continue
            info, name = raw.split(b'\t', 1)
            mode, sha, stage = info.decode().split()
            if stage != '0':
                raise ValueError('Unmerged index')
            yield name.decode(), git('cat-file', 'blob', sha), mode
    elif args.history:
        for raw in git('rev-list', '--objects', '--all').splitlines():
            sha, _, name = raw.partition(b' ')
            kind = git('cat-file', '-t', sha.decode()).strip()
            if kind == b'blob':
                yield name.decode(), git('cat-file', 'blob', sha.decode()), '100644'
            elif kind == b'commit':
                yield '(commit-metadata)', git('cat-file', 'commit', sha.decode()), '100644'
        # Object lists do not carry modes; inspect every historical tree too.
        for sha in git('rev-list', '--all').splitlines():
            for row in git('ls-tree', '-r', '-z', sha.decode()).split(b'\0'):
                if not row:
                    continue
                info, name = row.split(b'\t', 1)
                mode, kind, obj = info.decode().split()
                if mode not in {'100644', '100755'}:
                    yield name.decode(), b'', mode
    else:
        with tarfile.open(args.archive, 'r:*') as archive:
            for member in archive:
                if member.isdir():
                    continue
                if not member.isfile():
                    yield member.name, b'', '120000'
                elif member.size > 2 * 1024 * 1024:
                    yield member.name, b'x' * (2 * 1024 * 1024 + 1), '100644'
                else:
                    yield member.name, archive.extractfile(member).read(), '100644'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--tree', action='store_true')
    group.add_argument('--staged', action='store_true')
    group.add_argument('--history', action='store_true')
    group.add_argument('--archive', type=Path)
    args = parser.parse_args()
    findings = []
    count = 0
    try:
        for name, data, mode in entries(args):
            count += 1
            findings.extend(scan(name, data, mode))
    except (OSError, ValueError, subprocess.CalledProcessError, tarfile.TarError):
        print(json.dumps({'status': 'error', 'reason': 'Input could not be fully audited'}))
        return 2
    print(json.dumps({'status': 'fail' if findings else 'pass', 'files_or_objects': count, 'findings': findings}, indent=2))
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
