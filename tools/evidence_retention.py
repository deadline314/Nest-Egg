#!/usr/bin/env python3
"""Remove expired local evidence only when the published ZIP holds the same bytes."""

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from tempfile import TemporaryFile
import time
from zipfile import BadZipFile, ZipFile


RETENTION_DAYS = 30
SECONDS_PER_DAY = 86400
CHUNK_SIZE = 1024 * 1024
PUBLISHED = 'refs/remotes/origin/main'
OID = re.compile(r'[a-f0-9]{40}|[a-f0-9]{64}')
ATTACHMENT = re.compile(r'pm/[^/]+/attachments/.+\.zip', re.IGNORECASE)


def git(repo, *args, expected=(0,), stdout=subprocess.PIPE):
    result = subprocess.run(['git', *args], cwd=repo, stdout=stdout, stderr=subprocess.PIPE)
    if result.returncode not in expected:
        detail = result.stderr.decode('utf-8', errors='replace').strip()
        raise ValueError(detail or f'git {args[0]} exited {result.returncode}')
    return result


def plain_path(root, parts, *, directory=False, skip_worktrees=False):
    """Check every component so symlinks, junctions and special files never match."""
    path = root
    for index, component in enumerate(parts):
        path /= component
        try:
            info = path.lstat()
        except FileNotFoundError:
            return None
        if getattr(info, 'st_file_attributes', 0) & getattr(stat, 'FILE_ATTRIBUTE_REPARSE_POINT', 0x400):
            return None
        expect_dir = directory or index < len(parts) - 1
        if not (stat.S_ISDIR(info.st_mode) if expect_dir else stat.S_ISREG(info.st_mode)):
            return None
        if expect_dir and skip_worktrees and os.path.lexists(path / '.git'):
            return None
    return path


def member_parts(name):
    parts = name.split('/')
    if any(part in ('', '.', '..') or part.endswith((' ', '.')) or ':' in part or '\\' in part for part in parts):
        return None
    if parts[0].casefold() == 'publish' or any(part.casefold() == '.git' for part in parts):
        return None
    return parts


def same_bytes(local, archived):
    while True:
        chunk = local.read(CHUNK_SIZE)
        if chunk != archived.read(CHUNK_SIZE):
            return False
        if not chunk:
            return True


def fingerprint(info):
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns


def prune_archive(zip_file, folder, cutoff, apply):
    members = zip_file.infolist()
    names = Counter(item.filename.casefold() for item in members)
    for item in members:
        if item.is_dir() or names[item.filename.casefold()] != 1:
            continue
        parts = member_parts(item.filename)
        if parts is None:
            continue
        relative = [folder.name, *parts]
        local = plain_path(folder.parent, relative, skip_worktrees=True)
        if local is None:
            continue
        try:
            initial = local.lstat()
            if initial.st_nlink != 1 or initial.st_mtime > cutoff or initial.st_size != item.file_size:
                continue
            with local.open('rb') as source, zip_file.open(item) as archived:
                # Windows path and handle stat can report different ctime values.
                if fingerprint(os.fstat(source.fileno())) != fingerprint(initial) or not same_bytes(source, archived):
                    continue
            if plain_path(folder.parent, relative, skip_worktrees=True) != local:
                continue
            latest = local.lstat()
            if fingerprint(latest) != fingerprint(initial) or latest.st_ctime_ns != initial.st_ctime_ns:
                continue
            if apply:
                local.unlink()
            print(f'{"清理" if apply else "預覽"} {local}')
        except FileNotFoundError:
            # A second sweep or the producer already moved the file.
            continue
        except (OSError, BadZipFile, RuntimeError, NotImplementedError) as error:
            raise ValueError(f'{local} — {error}') from error


def prune_scope(repo, head, folder, cutoff, apply):
    if os.path.lexists(folder / '.git'):
        return
    receipt = plain_path(folder.parent, (folder.name, 'publish', 'result.json'))
    if receipt is None or receipt.stat().st_mtime > cutoff:
        return
    with receipt.open('rb') as source:
        raw = source.read(16385)
    if len(raw) > 16384:
        raise ValueError(f'{receipt} — 交付紀錄超過 16 KiB')
    data = json.loads(raw)
    if not isinstance(data, dict) or data.get('main_origin_head_equal') is not True:
        return
    commit = data.get('commit')
    if not isinstance(commit, str) or not OID.fullmatch(commit):
        raise ValueError(f'{receipt} — 缺少有效的已發布提交')
    exists = git(repo, 'rev-parse', '--verify', '--quiet', f'{commit}^{{commit}}', expected=(0, 1))
    if exists.returncode or git(repo, 'merge-base', '--is-ancestor', commit, head, expected=(0, 1)).returncode:
        return
    published_at = int(git(repo, 'show', '-s', '--format=%ct', commit).stdout)
    if published_at > cutoff:
        return
    added = git(repo, 'diff-tree', '--root', '--no-commit-id', '--diff-filter=A', '--name-only',
                '-r', '-z', commit, '--', 'pm/').stdout.decode('utf-8').split('\0')
    for name in (item for item in added if ATTACHMENT.fullmatch(item)):
        archive = git(repo, 'rev-parse', '--verify', f'{commit}:{name}').stdout.strip()
        current = git(repo, 'rev-parse', '--verify', '--quiet', f'{head}:{name}', expected=(0, 1)).stdout.strip()
        if not current or archive != current:
            continue
        with TemporaryFile() as source:
            try:
                git(repo, 'cat-file', 'blob', archive.decode('ascii'), stdout=source)
                source.seek(0)
                with ZipFile(source) as zip_file:
                    prune_archive(zip_file, folder, cutoff, apply)
            except (BadZipFile, OSError, ValueError) as error:
                raise ValueError(f'{name} — {error}') from error


def sweep(repo, root, days, apply):
    root = Path(os.path.abspath(root))
    if not os.path.lexists(root):
        return 0
    if root.resolve(strict=True) != root or not root.is_dir() or root == Path(root.anchor) or root == repo:
        raise ValueError(f'{root} — 必須是獨立的本機證據目錄')
    if repo in root.parents and root != repo / 'work' / 'evidence':
        raise ValueError(f'{root} — 工作區內只允許 work/evidence')
    head = git(repo, 'rev-parse', '--verify', '--quiet', PUBLISHED, expected=(0, 1)).stdout.decode('ascii').strip()
    if not head:
        return 0
    cutoff = time.time() - days * SECONDS_PER_DAY
    status = 0
    for folder in root.iterdir():
        if folder == repo or folder in repo.parents:
            continue
        if not folder.name.startswith('evidence-') or plain_path(root, (folder.name,), directory=True) is None:
            continue
        try:
            prune_scope(repo, head, folder, cutoff, apply)
        except (OSError, ValueError) as error:
            print(f'證據清理：{folder} — {error}', file=sys.stderr)
            status = 1
    return status


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, help='local evidence root; defaults to nestegg.evidenceRoot or work/evidence')
    parser.add_argument('--days', type=int, default=RETENTION_DAYS, help='retention in days (default: 30)')
    parser.add_argument('--apply', action='store_true', help='delete verified local duplicates instead of previewing')
    args = parser.parse_args()
    if not 1 <= args.days <= 3650:
        parser.error('--days must be between 1 and 3650')
    repo = Path(__file__).resolve().parents[1]
    try:
        root = args.root
        if root is None:
            configured = git(repo, 'config', '--local', '--get', 'nestegg.evidenceRoot', expected=(0, 1)).stdout.decode('utf-8').strip()
            root = Path(configured) if configured else None
        if root is not None and not os.path.lexists(root):
            raise ValueError(f'{root} — 找不到已指定的證據目錄')
        return sweep(repo, root if root is not None else repo / 'work' / 'evidence', args.days, args.apply)
    except (OSError, ValueError) as error:
        print(f'證據清理：{error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
