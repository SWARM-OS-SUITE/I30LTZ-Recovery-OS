#!/usr/bin/env python3
"""Claude cloud hook: checkpoint source to the current claude/* task branch.
No model calls, no force push, no main writes. A live cloud session is required.
"""
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def git(*args, check=True):
    p = subprocess.run(['git', *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       env={**os.environ, 'GIT_TERMINAL_PROMPT': '0'}, timeout=25)
    if check and p.returncode:
        raise RuntimeError('Git ' + args[0] + ' failed; checkpoint will retry on the next hook')
    return p


def val(*args):
    return git(*args).stdout.decode().strip()


def blocked(path):
    p = Path(path)
    return (any(x in {'.cc-writes', 'secrets', '.gradle', '.idea', 'build', 'target',
                     'node_modules', '__pycache__'} for x in p.parts)
            or p.name == '.env' or p.name.startswith('.env.')
            or p.name in {'local.properties', 'settings.local.json', 'id_rsa', 'id_ed25519'}
            or p.suffix.lower() in {'.key', '.pem', '.p12', '.jks', '.keystore', '.apk', '.aab', '.iso'}
            or p.name.startswith(('credentials', 'client_secret', 'service-account')))


def checkpoint():
    if os.environ.get('CLAUDE_CODE_REMOTE') != 'true':
        return
    os.chdir(os.environ.get('CLAUDE_PROJECT_DIR', '.'))
    # Refuse the surrounding monorepo when this script is invoked from a subfolder.
    root = Path(val('rev-parse', '--show-toplevel')).resolve()
    if Path(__file__).resolve().parent.parent != root:
        return
    os.chdir(root)
    gitdir = Path(val('rev-parse', '--absolute-git-dir'))
    with (gitdir / 'cloud-checkpoint.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        branch = val('branch', '--show-current')
        if not branch.startswith('claude/'):
            raise RuntimeError('waiting for the session claude/* branch; main is never auto-committed')
        for name in ('index.lock', 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'rebase-merge', 'rebase-apply'):
            if (gitdir / name).exists():
                raise RuntimeError('Git operation in progress; retrying after the next tool')
        if git('diff', '--cached', '--quiet', check=False).returncode:
            raise RuntimeError('existing staged changes left for Claude to commit')
        raw = git('ls-files', '-z', '--modified', '--deleted', '--others', '--exclude-standard').stdout
        paths = sorted(set(os.fsdecode(p) for p in raw.split(b'\0') if p))
        eligible = [p for p in paths if not blocked(p)]
        # Avoid publishing common live credential formats, even inside source files.
        sensitive = re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-(?:ant-|proj-)?[A-Za-z0-9_-]{24,}|AKIA[A-Z0-9]{16})')
        for name in eligible:
            p = Path(name)
            if p.is_file() and not p.is_symlink():
                if p.stat().st_size > 2 * 1024 * 1024:
                    raise RuntimeError('large changed file needs manual review; no checkpoint staged')
                if sensitive.search(p.read_bytes()):
                    raise RuntimeError('possible credential in changed content; no checkpoint staged')
        if eligible:
            git('add', '-A', '--', *eligible)
            if git('diff', '--cached', '--quiet', check=False).returncode:
                # Use repo identity when available; fallback is scoped to this commit.
                name = git('config', 'user.name', check=False).stdout.decode().strip() or 'Claude cloud checkpoint'
                email = git('config', 'user.email', check=False).stdout.decode().strip() or 'cloud-checkpoint@users.noreply.github.com'
                git('-c', 'user.name=' + name, '-c', 'user.email=' + email,
                    'commit', '-m', 'checkpoint: save Claude mobile progress')
        # Always retry a previous unpushed commit, including on Stop/SessionStart.
        git('push', '--quiet', 'origin', 'HEAD:refs/heads/' + branch)
        (gitdir / 'cloud-checkpoint-status.json').write_text(json.dumps({
            'status': 'pushed', 'branch': branch, 'commit': val('rev-parse', 'HEAD'),
            'excluded_changed_files': len(paths) - len(eligible)}) + '\n')
        print('Cloud checkpoint saved to ' + branch)


if __name__ == '__main__':
    try:
        checkpoint()
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
        # Warn without blocking editing or exposing command output/secrets.
        print('Cloud checkpoint pending: ' + str(exc), file=sys.stderr)
