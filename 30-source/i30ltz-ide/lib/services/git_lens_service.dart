import 'dart:async';
import 'dart:io';

enum GitGutterType { added, modified, deleted }

class GitBlameInfo {
  final String hash;
  final String shortHash;
  final String author;
  final String authorMail;
  final DateTime authorTime;
  final String summary;
  final int lineNumber;
  final bool isUncommitted;

  const GitBlameInfo({
    required this.hash,
    required this.shortHash,
    required this.author,
    required this.authorMail,
    required this.authorTime,
    required this.summary,
    required this.lineNumber,
    this.isUncommitted = false,
  });

  String get timeAgo {
    if (isUncommitted) return 'uncommitted';
    final diff = DateTime.now().difference(authorTime);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  String get inlineAnnotation {
    if (isUncommitted) return 'You • Uncommitted changes';
    return '$author, $timeAgo • $summary [$shortHash]';
  }
}

class GitCommit {
  final String hash;
  final String shortHash;
  final String author;
  final String authorEmail;
  final String relativeDate;
  final DateTime date;
  final String message;
  final List<String> parentHashes;
  final List<String> refs; // branches, tags
  final String graphNode; // visual character from git log --graph

  const GitCommit({
    required this.hash,
    required this.shortHash,
    required this.author,
    required this.authorEmail,
    required this.relativeDate,
    required this.date,
    required this.message,
    this.parentHashes = const [],
    this.refs = const [],
    this.graphNode = '*',
  });
}

class GitBranch {
  final String name;
  final bool isCurrent;
  final bool isRemote;
  final String? upstream;
  final int ahead;
  final int behind;

  const GitBranch({
    required this.name,
    this.isCurrent = false,
    this.isRemote = false,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
  });
}

class GitStash {
  final int index;
  final String branch;
  final String message;
  final String relativeDate;

  const GitStash({
    required this.index,
    required this.branch,
    required this.message,
    required this.relativeDate,
  });
}

class GitGutterMarker {
  final int line;
  final GitGutterType type;
  final String? originalContent;

  const GitGutterMarker({
    required this.line,
    required this.type,
    this.originalContent,
  });
}

class GitLensService {
  static final GitLensService instance = GitLensService._();
  GitLensService._();

  // Cache: filePath -> (fileModifiedTimestamp, Map<lineNumber, GitBlameInfo>)
  final Map<String, (DateTime, Map<int, GitBlameInfo>)> _blameCache = {};
  final Map<String, (DateTime, Map<int, GitGutterMarker>)> _gutterCache = {};

  Future<ProcessResult> _run(List<String> args, {String? cwd}) async {
    final workDir = cwd ?? Directory.current.path;
    return await Process.run('git', args, workingDirectory: workDir);
  }

  // ── Blame Inspection ────────────────────────────────────────────────────────

  Future<Map<int, GitBlameInfo>> getBlameForFile(String filePath, {String? cwd}) async {
    final file = File(filePath);
    if (!file.existsSync()) return {};

    final lastMod = file.lastModifiedSync();
    if (_blameCache.containsKey(filePath)) {
      final cached = _blameCache[filePath]!;
      if (cached.$1 == lastMod) return cached.$2;
    }

    try {
      final res = await _run([
        'blame',
        '--line-porcelain',
        filePath,
      ], cwd: cwd);

      if (res.exitCode != 0) return {};

      final lines = (res.stdout as String).split('\n');
      final result = <int, GitBlameInfo>{};

      String currentHash = '';
      String author = 'Unknown';
      String authorMail = '';
      DateTime authorTime = DateTime.now();
      String summary = '';
      int currentLine = 1;

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.isEmpty) continue;

        if (RegExp(r'^[0-9a-f]{40}\s+\d+\s+(\d+)').hasMatch(line)) {
          final parts = line.split(RegExp(r'\s+'));
          currentHash = parts[0];
          if (parts.length >= 3) {
            currentLine = int.tryParse(parts[2]) ?? currentLine;
          }
        } else if (line.startsWith('author ')) {
          author = line.substring(7).trim();
        } else if (line.startsWith('author-mail ')) {
          authorMail = line.substring(12).replaceAll('<', '').replaceAll('>', '').trim();
        } else if (line.startsWith('author-time ')) {
          final ts = int.tryParse(line.substring(12).trim()) ?? 0;
          if (ts > 0) {
            authorTime = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
          }
        } else if (line.startsWith('summary ')) {
          summary = line.substring(8).trim();
        } else if (line.startsWith('\t')) {
          final isUncommitted = currentHash.startsWith('0000000') || author == 'Not Committed Yet';
          final shortHash = isUncommitted ? 'uncommitted' : (currentHash.length >= 8 ? currentHash.substring(0, 8) : currentHash);

          result[currentLine] = GitBlameInfo(
            hash: currentHash,
            shortHash: shortHash,
            author: isUncommitted ? 'You' : author,
            authorMail: authorMail,
            authorTime: authorTime,
            summary: isUncommitted ? 'Uncommitted changes' : summary,
            lineNumber: currentLine,
            isUncommitted: isUncommitted,
          );
        }
      }

      _blameCache[filePath] = (lastMod, result);
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<GitBlameInfo?> getBlameForLine(String filePath, int lineNum, {String? cwd}) async {
    final map = await getBlameForFile(filePath, cwd: cwd);
    return map[lineNum];
  }

  // ── Gutter Diff Markers ─────────────────────────────────────────────────────

  Future<Map<int, GitGutterMarker>> getGutterDiff(String filePath, {String? cwd}) async {
    final file = File(filePath);
    if (!file.existsSync()) return {};

    final lastMod = file.lastModifiedSync();
    if (_gutterCache.containsKey(filePath)) {
      final cached = _gutterCache[filePath]!;
      if (cached.$1 == lastMod) return cached.$2;
    }

    try {
      final res = await _run(['diff', '-U0', 'HEAD', '--', filePath], cwd: cwd);
      if (res.exitCode != 0) return {};

      final output = res.stdout as String;
      final markers = <int, GitGutterMarker>{};
      final hunkRegex = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@');

      for (final line in output.split('\n')) {
        final match = hunkRegex.firstMatch(line);
        if (match != null) {
          final oldCount = match.group(2) != null ? int.parse(match.group(2)!) : 1;
          final newStart = int.parse(match.group(3)!);
          final newCount = match.group(4) != null ? int.parse(match.group(4)!) : 1;

          if (oldCount == 0 && newCount > 0) {
            // Lines added
            for (int i = 0; i < newCount; i++) {
              markers[newStart + i] = GitGutterMarker(
                line: newStart + i,
                type: GitGutterType.added,
              );
            }
          } else if (oldCount > 0 && newCount == 0) {
            // Line(s) deleted before newStart
            markers[newStart > 0 ? newStart : 1] = GitGutterMarker(
              line: newStart > 0 ? newStart : 1,
              type: GitGutterType.deleted,
            );
          } else {
            // Line(s) modified
            for (int i = 0; i < newCount; i++) {
              markers[newStart + i] = GitGutterMarker(
                line: newStart + i,
                type: GitGutterType.modified,
              );
            }
          }
        }
      }

      _gutterCache[filePath] = (lastMod, markers);
      return markers;
    } catch (_) {
      return {};
    }
  }

  // ── File Revision History ───────────────────────────────────────────────────

  Future<List<GitCommit>> getFileHistory(String filePath, {int limit = 40, String? cwd}) async {
    try {
      final res = await _run([
        'log',
        '-n',
        '$limit',
        '--follow',
        '--pretty=format:%H%x1f%h%x1f%an%x1f%ae%x1f%ar%x1f%at%x1f%s%x1f%d',
        '--',
        filePath,
      ], cwd: cwd);

      if (res.exitCode != 0) return [];
      return _parseCommitList(res.stdout as String);
    } catch (_) {
      return [];
    }
  }

  // ── Commit Graph / Log ──────────────────────────────────────────────────────

  Future<List<GitCommit>> getCommitGraph({int limit = 60, String? search, String? cwd}) async {
    try {
      final args = [
        'log',
        '-n',
        '$limit',
        '--pretty=format:%H%x1f%h%x1f%an%x1f%ae%x1f%ar%x1f%at%x1f%s%x1f%d%x1f%p',
      ];
      if (search != null && search.trim().isNotEmpty) {
        args.addAll(['--grep', search.trim(), '-i']);
      }

      final res = await _run(args, cwd: cwd);
      if (res.exitCode != 0) return [];
      return _parseCommitList(res.stdout as String);
    } catch (_) {
      return [];
    }
  }

  List<GitCommit> _parseCommitList(String raw) {
    final list = <GitCommit>[];
    for (final line in raw.split('\n')) {
      if (line.trim().isEmpty) continue;
      final parts = line.split('\x1f');
      if (parts.length < 7) continue;

      final hash = parts[0].trim();
      final shortHash = parts[1].trim();
      final author = parts[2].trim();
      final email = parts[3].trim();
      final relDate = parts[4].trim();
      final ts = int.tryParse(parts[5].trim()) ?? 0;
      final date = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      final msg = parts[6].trim();

      final refsStr = parts.length > 7 ? parts[7].trim() : '';
      final refs = refsStr.isEmpty
          ? <String>[]
          : refsStr
              .replaceAll('(', '')
              .replaceAll(')', '')
              .split(',')
              .map((r) => r.trim())
              .where((r) => r.isNotEmpty)
              .toList();

      final parents = parts.length > 8 ? parts[8].trim().split(' ').where((p) => p.isNotEmpty).toList() : <String>[];

      list.add(GitCommit(
        hash: hash,
        shortHash: shortHash,
        author: author,
        authorEmail: email,
        relativeDate: relDate,
        date: date,
        message: msg,
        refs: refs,
        parentHashes: parents,
      ));
    }
    return list;
  }

  // ── Diffs & Historical Views ────────────────────────────────────────────────

  Future<String> getCommitDiff(String hash, {String? cwd}) async {
    try {
      final res = await _run(['show', '--stat', '-p', hash], cwd: cwd);
      return res.stdout.toString();
    } catch (e) {
      return 'Error loading commit diff: $e';
    }
  }

  Future<String> getFileDiff(String filePath, {bool staged = false, String? cwd}) async {
    try {
      final args = ['diff'];
      if (staged) args.add('--staged');
      args.addAll(['--', filePath]);
      final res = await _run(args, cwd: cwd);
      final diff = res.stdout.toString();
      return diff.isEmpty ? 'No changes detected.' : diff;
    } catch (e) {
      return 'Error generating diff: $e';
    }
  }

  Future<String> getFileContentAtCommit(String hash, String relativePath, {String? cwd}) async {
    try {
      final res = await _run(['show', '$hash:$relativePath'], cwd: cwd);
      return res.stdout.toString();
    } catch (e) {
      return 'Error loading file revision: $e';
    }
  }

  // ── Branch Management ───────────────────────────────────────────────────────

  Future<List<GitBranch>> getBranches({String? cwd}) async {
    try {
      final res = await _run(['branch', '-a', '-vv'], cwd: cwd);
      if (res.exitCode != 0) return [];

      final lines = (res.stdout as String).split('\n');
      final list = <GitBranch>[];

      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final isCurrent = line.startsWith('*');
        final clean = line.substring(1).trim();
        final parts = clean.split(RegExp(r'\s+'));
        if (parts.isEmpty) continue;

        final name = parts[0];
        final isRemote = name.startsWith('remotes/');

        int ahead = 0, behind = 0;
        String? upstream;

        final upstreamMatch = RegExp(r'\[([^\]]+)\]').firstMatch(clean);
        if (upstreamMatch != null) {
          final upStr = upstreamMatch.group(1)!;
          upstream = upStr.split(':').first.trim();
          final aheadMatch = RegExp(r'ahead (\d+)').firstMatch(upStr);
          final behindMatch = RegExp(r'behind (\d+)').firstMatch(upStr);
          if (aheadMatch != null) ahead = int.parse(aheadMatch.group(1)!);
          if (behindMatch != null) behind = int.parse(behindMatch.group(1)!);
        }

        list.add(GitBranch(
          name: name,
          isCurrent: isCurrent,
          isRemote: isRemote,
          upstream: upstream,
          ahead: ahead,
          behind: behind,
        ));
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<bool> createBranch(String name, {String? cwd}) async {
    final res = await _run(['checkout', '-b', name], cwd: cwd);
    return res.exitCode == 0;
  }

  Future<bool> checkoutBranch(String name, {String? cwd}) async {
    final target = name.replaceFirst('remotes/origin/', '');
    final res = await _run(['checkout', target], cwd: cwd);
    return res.exitCode == 0;
  }

  Future<bool> deleteBranch(String name, {bool force = false, String? cwd}) async {
    final flag = force ? '-D' : '-d';
    final res = await _run(['branch', flag, name], cwd: cwd);
    return res.exitCode == 0;
  }

  Future<bool> mergeBranch(String name, {String? cwd}) async {
    final res = await _run(['merge', name], cwd: cwd);
    return res.exitCode == 0;
  }

  // ── Stash Management ────────────────────────────────────────────────────────

  Future<List<GitStash>> getStashes({String? cwd}) async {
    try {
      final res = await _run(['stash', 'list', '--pretty=format:%gd%x1f%gs%x1f%cr'], cwd: cwd);
      if (res.exitCode != 0) return [];

      final lines = (res.stdout as String).split('\n');
      final list = <GitStash>[];

      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final parts = line.split('\x1f');
        if (parts.isEmpty) continue;

        final ref = parts[0];
        final idxMatch = RegExp(r'stash@\{(\d+)\}').firstMatch(ref);
        final index = idxMatch != null ? int.parse(idxMatch.group(1)!) : 0;
        final msg = parts.length > 1 ? parts[1] : ref;
        final relDate = parts.length > 2 ? parts[2] : '';

        String branch = 'HEAD';
        final bMatch = RegExp(r'On\s+([^\s:]+)').firstMatch(msg);
        if (bMatch != null) branch = bMatch.group(1)!;

        list.add(GitStash(
          index: index,
          branch: branch,
          message: msg,
          relativeDate: relDate,
        ));
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<bool> stashSave(String message, {bool includeUntracked = true, String? cwd}) async {
    final args = ['stash', 'push'];
    if (includeUntracked) args.add('-u');
    if (message.isNotEmpty) args.addAll(['-m', message]);
    final res = await _run(args, cwd: cwd);
    return res.exitCode == 0;
  }

  Future<bool> stashPop(int index, {String? cwd}) async {
    final res = await _run(['stash', 'pop', 'stash@{$index}'], cwd: cwd);
    return res.exitCode == 0;
  }

  Future<bool> stashApply(int index, {String? cwd}) async {
    final res = await _run(['stash', 'apply', 'stash@{$index}'], cwd: cwd);
    return res.exitCode == 0;
  }

  Future<bool> stashDrop(int index, {String? cwd}) async {
    final res = await _run(['stash', 'drop', 'stash@{$index}'], cwd: cwd);
    return res.exitCode == 0;
  }

  Future<String> getStashDiff(int index, {String? cwd}) async {
    try {
      final res = await _run(['stash', 'show', '-p', 'stash@{$index}'], cwd: cwd);
      return res.stdout.toString();
    } catch (e) {
      return 'Error loading stash diff: $e';
    }
  }

  // ── Source Control Staging & Commits ────────────────────────────────────────

  Future<bool> stageFile(String path, {String? cwd}) async {
    final res = await _run(['add', path], cwd: cwd);
    return res.exitCode == 0;
  }

  Future<bool> unstageFile(String path, {String? cwd}) async {
    final res = await _run(['restore', '--staged', path], cwd: cwd);
    return res.exitCode == 0;
  }

  Future<bool> stageAll({String? cwd}) async {
    final res = await _run(['add', '-A'], cwd: cwd);
    return res.exitCode == 0;
  }

  Future<bool> unstageAll({String? cwd}) async {
    final res = await _run(['restore', '--staged', '.'], cwd: cwd);
    return res.exitCode == 0;
  }

  Future<bool> discardFileChanges(String path, {String? cwd}) async {
    var res = await _run(['restore', path], cwd: cwd);
    if (res.exitCode != 0) {
      res = await _run(['checkout', '--', path], cwd: cwd);
    }
    if (res.exitCode != 0) {
      await _run(['clean', '-f', path], cwd: cwd);
    }
    return true;
  }

  Future<bool> commit(String message, {bool amend = false, String? cwd}) async {
    final args = ['commit', '-m', message];
    if (amend) args.add('--amend');
    final res = await _run(args, cwd: cwd);
    return res.exitCode == 0;
  }

  // ── Remote Sync ─────────────────────────────────────────────────────────────

  Future<String> fetch({String? cwd}) async {
    final res = await _run(['fetch', '--all', '--prune'], cwd: cwd);
    return res.exitCode == 0 ? 'Fetch completed.' : (res.stderr.toString().isEmpty ? 'Fetch failed' : res.stderr.toString());
  }

  Future<String> pull({String? cwd}) async {
    final res = await _run(['pull'], cwd: cwd);
    return res.exitCode == 0 ? 'Pull completed.' : (res.stderr.toString().isEmpty ? 'Pull failed' : res.stderr.toString());
  }

  Future<String> push({bool setUpstream = false, bool forceWithLease = false, String? cwd}) async {
    final args = ['push'];
    if (setUpstream) args.addAll(['-u', 'origin', 'HEAD']);
    if (forceWithLease) args.add('--force-with-lease');
    final res = await _run(args, cwd: cwd);
    return res.exitCode == 0 ? 'Push successful.' : (res.stderr.toString().isEmpty ? 'Push failed' : res.stderr.toString());
  }

  // ── AI Commit Message Generator ─────────────────────────────────────────────

  String generateAiCommitMessage(List<String> filesChanged, String diffSnippet) {
    if (filesChanged.isEmpty) return 'chore: update project configuration';

    final hasDart = filesChanged.any((f) => f.endsWith('.dart'));
    final hasCs = filesChanged.any((f) => f.endsWith('.cs'));
    final hasCpp = filesChanged.any((f) => f.endsWith('.cpp') || f.endsWith('.hpp'));
    final hasSh = filesChanged.any((f) => f.endsWith('.sh'));
    final hasMd = filesChanged.any((f) => f.endsWith('.md'));
    final hasTest = filesChanged.any((f) => f.contains('test'));

    String prefix = 'feat';
    if (hasTest) {
      prefix = 'test';
    } else if (hasMd) {
      prefix = 'docs';
    } else if (diffSnippet.contains('fix') || diffSnippet.contains('bug') || diffSnippet.contains('error')) {
      prefix = 'fix';
    } else if (diffSnippet.contains('refactor') || diffSnippet.contains('clean')) {
      prefix = 'refactor';
    }

    String scope = 'core';
    if (hasDart) {
      if (filesChanged.any((f) => f.contains('git'))) {
        scope = 'gitlens';
      } else if (filesChanged.any((f) => f.contains('cinema'))) {
        scope = 'cinema';
      } else if (filesChanged.any((f) => f.contains('coder'))) {
        scope = 'coder';
      } else {
        scope = 'frontend';
      }
    } else if (hasCs) {
      scope = 'server';
    } else if (hasCpp) {
      scope = 'engine';
    } else if (hasSh) {
      scope = 'build';
    }

    final topFile = filesChanged.first.split('/').last;
    return '$prefix($scope): update $topFile and related components';
  }
}
