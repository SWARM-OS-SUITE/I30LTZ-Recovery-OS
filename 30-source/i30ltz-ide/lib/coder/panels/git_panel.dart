import 'dart:io';
import 'package:flutter/material.dart';
import '../../theme/swarm_colors.dart';
import '../../theme/swarm_text_styles.dart';
import '../editor_model.dart';
import '../../services/git_lens_service.dart';

enum _GitTab { changes, branches, commits, stashes }

class GitPanel extends StatefulWidget {
  final String? workspacePath;
  const GitPanel({super.key, this.workspacePath});

  @override
  State<GitPanel> createState() => _GitPanelState();
}

class _GitPanelState extends State<GitPanel> {
  _GitTab _activeTab = _GitTab.changes;
  GitStatus? _status;
  List<GitBranch> _branches = [];
  List<GitCommit> _commits = [];
  List<GitStash> _stashes = [];
  bool _loading = false;
  final _commitMsgCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  bool _amend = false;

  // Diff view state
  String? _diffTitle;
  String? _diffContent;
  bool _showDiff = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(GitPanel old) {
    super.didUpdateWidget(old);
    if (old.workspacePath != widget.workspacePath) _refresh();
  }

  @override
  void dispose() {
    _commitMsgCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (widget.workspacePath == null) return;
    setState(() => _loading = true);
    try {
      final statusRaw = await _runGit(['status', '--porcelain', '-b'], widget.workspacePath!);
      final branches = await GitLensService.instance.getBranches(cwd: widget.workspacePath);
      final commits = await GitLensService.instance.getCommitGraph(
        limit: 40,
        search: _searchCtrl.text.isNotEmpty ? _searchCtrl.text : null,
        cwd: widget.workspacePath,
      );
      final stashes = await GitLensService.instance.getStashes(cwd: widget.workspacePath);

      if (mounted) {
        setState(() {
          _status = _parseStatus(statusRaw);
          _branches = branches;
          _commits = commits;
          _stashes = stashes;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _runGit(List<String> args, String cwd) async {
    final r = await Process.run('git', args, workingDirectory: cwd);
    return r.stdout.toString();
  }

  GitStatus _parseStatus(String raw) {
    final lines = raw.split('\n').where((l) => l.isNotEmpty).toList();
    String branch = 'unknown';
    int ahead = 0, behind = 0;
    final staged = <GitChange>[], unstaged = <GitChange>[], untracked = <GitChange>[];

    for (final line in lines) {
      if (line.startsWith('## ')) {
        final branchInfo = line.substring(3);
        branch = branchInfo.split('...').first.trim();
        final aheadM = RegExp(r'\[ahead (\d+)').firstMatch(branchInfo);
        final behindM = RegExp(r'behind (\d+)').firstMatch(branchInfo);
        if (aheadM != null) ahead = int.tryParse(aheadM.group(1)!) ?? 0;
        if (behindM != null) behind = int.tryParse(behindM.group(1)!) ?? 0;
        continue;
      }
      if (line.length < 3) continue;
      final x = line[0], y = line[1];
      final path = line.substring(3);
      if (x == '?' && y == '?') {
        untracked.add(GitChange(path: path, status: '?', isStaged: false));
      } else {
        if (x != ' ' && x != '?') staged.add(GitChange(path: path, status: x, isStaged: true));
        if (y != ' ' && y != '?') unstaged.add(GitChange(path: path, status: y, isStaged: false));
      }
    }
    return GitStatus(branch: branch, staged: staged, unstaged: unstaged, untracked: untracked, ahead: ahead, behind: behind);
  }

  // ── Source Control Actions ──────────────────────────────────────────────────

  Future<void> _stageAll() async {
    await GitLensService.instance.stageAll(cwd: widget.workspacePath);
    _refresh();
  }

  Future<void> _unstageAll() async {
    await GitLensService.instance.unstageAll(cwd: widget.workspacePath);
    _refresh();
  }

  Future<void> _stageFile(String path) async {
    await GitLensService.instance.stageFile(path, cwd: widget.workspacePath);
    _refresh();
  }

  Future<void> _unstageFile(String path) async {
    await GitLensService.instance.unstageFile(path, cwd: widget.workspacePath);
    _refresh();
  }

  Future<void> _discardChanges(String path) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F141F),
        title: const Text('Discard Changes?', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to discard changes in $path? This action cannot be undone.', style: const TextStyle(color: SwarmColors.textSecondary, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: SwarmColors.agentRose),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await GitLensService.instance.discardFileChanges(path, cwd: widget.workspacePath);
      _refresh();
    }
  }

  Future<void> _commit() async {
    final msg = _commitMsgCtrl.text.trim();
    if (msg.isEmpty || widget.workspacePath == null) return;
    await GitLensService.instance.commit(msg, amend: _amend, cwd: widget.workspacePath);
    _commitMsgCtrl.clear();
    setState(() => _amend = false);
    _refresh();
  }

  Future<void> _generateAiCommit() async {
    if (widget.workspacePath == null || _status == null) return;
    final files = [..._status!.staged.map((c) => c.path), ..._status!.unstaged.map((c) => c.path)];
    final diff = await GitLensService.instance.getFileDiff('', staged: true, cwd: widget.workspacePath);
    final msg = GitLensService.instance.generateAiCommitMessage(files, diff);
    setState(() => _commitMsgCtrl.text = msg);
  }

  Future<void> _pull() async {
    final res = await GitLensService.instance.pull(cwd: widget.workspacePath);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res), duration: const Duration(seconds: 2)));
    }
    _refresh();
  }

  Future<void> _push() async {
    final res = await GitLensService.instance.push(cwd: widget.workspacePath);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res), duration: const Duration(seconds: 2)));
    }
    _refresh();
  }

  Future<void> _showFileDiff(String path, {bool staged = false}) async {
    final diff = await GitLensService.instance.getFileDiff(path, staged: staged, cwd: widget.workspacePath);
    setState(() {
      _diffTitle = '$path (${staged ? "Staged" : "Working Tree"})';
      _diffContent = diff;
      _showDiff = true;
    });
  }

  // ── Branch Actions ──────────────────────────────────────────────────────────

  Future<void> _createNewBranchDialog() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F141F),
        title: const Text('Create New Branch', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
          decoration: const InputDecoration(
            hintText: 'feature/branch-name',
            hintStyle: TextStyle(color: SwarmColors.textDisabled, fontSize: 12),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: SwarmColors.agentCyan),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Create & Checkout', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final ok = await GitLensService.instance.createBranch(name, cwd: widget.workspacePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Created and checked out $name' : 'Failed to create branch $name')),
        );
      }
      _refresh();
    }
  }

  Future<void> _checkoutBranch(String name) async {
    final ok = await GitLensService.instance.checkoutBranch(name, cwd: widget.workspacePath);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Switched to branch $name' : 'Failed to checkout $name')),
      );
    }
    _refresh();
  }

  // ── Stash Actions ───────────────────────────────────────────────────────────

  Future<void> _createStashDialog() async {
    final ctrl = TextEditingController();
    final msg = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F141F),
        title: const Text('Create Git Stash', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: const InputDecoration(
            hintText: 'Optional stash description...',
            hintStyle: TextStyle(color: SwarmColors.textDisabled, fontSize: 12),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: SwarmColors.agentAmber),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Stash Changes', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (msg != null) {
      await GitLensService.instance.stashSave(msg, cwd: widget.workspacePath);
      _refresh();
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_showDiff && _diffContent != null) {
      return _DiffView(
        file: _diffTitle ?? 'Diff',
        diff: _diffContent!,
        onBack: () => setState(() => _showDiff = false),
      );
    }

    return Column(
      children: [
        _TopBar(
          branch: _status?.branch ?? '—',
          ahead: _status?.ahead ?? 0,
          behind: _status?.behind ?? 0,
          onRefresh: _refresh,
          onPull: _pull,
          onPush: _push,
          loading: _loading,
          onOpenStudio: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('GitLens Studio is not part of the I30LTZ IDE yet. Use the Git panel.'))),
        ),
        // Tab Selector
        _TabHeader(
          activeTab: _activeTab,
          onSelectTab: (tab) => setState(() => _activeTab = tab),
          changesCount: _status?.totalChanges ?? 0,
          branchesCount: _branches.length,
          stashesCount: _stashes.length,
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 1.5, color: SwarmColors.accent))
              : widget.workspacePath == null
                  ? Center(child: Text('No workspace open', style: SwarmTextStyles.bodySmall.copyWith(color: SwarmColors.textMuted)))
                  : switch (_activeTab) {
                      _GitTab.changes => _buildChangesTab(),
                      _GitTab.branches => _buildBranchesTab(),
                      _GitTab.commits => _buildCommitsTab(),
                      _GitTab.stashes => _buildStashesTab(),
                    },
        ),
      ],
    );
  }

  // ── Tabs ────────────────────────────────────────────────────────────────────

  Widget _buildChangesTab() {
    if (_status == null || _status!.totalChanges == 0) {
      return _NoChanges(onRefresh: _refresh);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Commit Box
          _CommitBox(
            controller: _commitMsgCtrl,
            isAmend: _amend,
            onToggleAmend: (v) => setState(() => _amend = v),
            onCommit: _commit,
            onStageAll: _stageAll,
            onGenerateAiMessage: _generateAiCommit,
          ),
          const SizedBox(height: 12),

          // Staged Changes
          if (_status!.staged.isNotEmpty) ...[
            _SectionHeader(
              'STAGED CHANGES (${_status!.staged.length})',
              actionIcon: Icons.remove_circle_outline,
              actionTooltip: 'Unstage All',
              onAction: _unstageAll,
            ),
            ..._status!.staged.map((c) => _ChangeRow(
                  change: c,
                  onAction: () => _unstageFile(c.path),
                  actionIcon: Icons.remove_circle_outline,
                  actionTooltip: 'Unstage',
                  onDiff: () => _showFileDiff(c.path, staged: true),
                )),
            const SizedBox(height: 8),
          ],

          // Changes (Unstaged)
          if (_status!.unstaged.isNotEmpty) ...[
            _SectionHeader(
              'CHANGES (${_status!.unstaged.length})',
              actionIcon: Icons.add_circle_outline,
              actionTooltip: 'Stage All',
              onAction: _stageAll,
            ),
            ..._status!.unstaged.map((c) => _ChangeRow(
                  change: c,
                  onAction: () => _stageFile(c.path),
                  actionIcon: Icons.add_circle_outline,
                  actionTooltip: 'Stage',
                  onDiscard: () => _discardChanges(c.path),
                  onDiff: () => _showFileDiff(c.path, staged: false),
                )),
            const SizedBox(height: 8),
          ],

          // Untracked
          if (_status!.untracked.isNotEmpty) ...[
            _SectionHeader('UNTRACKED (${_status!.untracked.length})', onAction: null),
            ..._status!.untracked.map((c) => _ChangeRow(
                  change: c,
                  onAction: () => _stageFile(c.path),
                  actionIcon: Icons.add_circle_outline,
                  actionTooltip: 'Stage',
                  onDiscard: () => _discardChanges(c.path),
                  onDiff: null,
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildBranchesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _createNewBranchDialog,
                  icon: const Icon(Icons.add, size: 13),
                  label: const Text('New Branch', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SwarmColors.agentCyan.withValues(alpha: 0.15),
                    foregroundColor: SwarmColors.agentCyan,
                    elevation: 0,
                    side: BorderSide(color: SwarmColors.agentCyan.withValues(alpha: 0.4)),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _branches.length,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemBuilder: (_, i) {
              final b = _branches[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: b.isCurrent ? SwarmColors.agentCyan.withValues(alpha: 0.1) : SwarmColors.bgElevated,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: b.isCurrent ? SwarmColors.agentCyan.withValues(alpha: 0.5) : SwarmColors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      b.isRemote ? Icons.cloud_queue : Icons.call_split,
                      size: 13,
                      color: b.isCurrent ? SwarmColors.agentCyan : SwarmColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                b.name,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontFamily: 'monospace',
                                  fontWeight: b.isCurrent ? FontWeight.bold : FontWeight.normal,
                                  color: b.isCurrent ? Colors.white : SwarmColors.textSecondary,
                                ),
                              ),
                              if (b.isCurrent) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: SwarmColors.agentCyan,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text('CURRENT', style: TextStyle(fontSize: 8, color: Colors.black, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                          if (b.ahead > 0 || b.behind > 0)
                            Text(
                              '${b.ahead > 0 ? "↑${b.ahead} " : ""}${b.behind > 0 ? "↓${b.behind}" : ""}',
                              style: const TextStyle(fontSize: 10, color: SwarmColors.agentEmerald),
                            ),
                        ],
                      ),
                    ),
                    if (!b.isCurrent)
                      TextButton(
                        onPressed: () => _checkoutBranch(b.name),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Checkout', style: TextStyle(fontSize: 10, color: SwarmColors.agentCyan)),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCommitsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _searchCtrl,
            onSubmitted: (_) => _refresh(),
            style: const TextStyle(fontSize: 11.5, color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search commits (Enter to search)...',
              hintStyle: const TextStyle(fontSize: 11, color: SwarmColors.textDisabled),
              filled: true,
              fillColor: SwarmColors.bgElevated,
              prefixIcon: const Icon(Icons.search, size: 14, color: SwarmColors.textMuted),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 14, color: SwarmColors.textMuted),
                      onPressed: () {
                        _searchCtrl.clear();
                        _refresh();
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: SwarmColors.border)),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _commits.length,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemBuilder: (_, i) {
              final c = _commits[i];
              return InkWell(
                onTap: () async {
                  final diff = await GitLensService.instance.getCommitDiff(c.hash, cwd: widget.workspacePath);
                  setState(() {
                    _diffTitle = '${c.shortHash} - ${c.message}';
                    _diffContent = diff;
                    _showDiff = true;
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: SwarmColors.bgElevated,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: SwarmColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.commit, size: 13, color: SwarmColors.agentCyan),
                          const SizedBox(width: 4),
                          Text(c.shortHash, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: SwarmColors.agentCyan, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          Text(c.relativeDate, style: const TextStyle(fontSize: 10, color: SwarmColors.textMuted)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        c.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: SwarmColors.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      Text(c.author, style: const TextStyle(fontSize: 10, color: SwarmColors.textSecondary)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStashesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _createStashDialog,
                  icon: const Icon(Icons.archive_outlined, size: 13),
                  label: const Text('Create Stash', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SwarmColors.agentAmber.withValues(alpha: 0.15),
                    foregroundColor: SwarmColors.agentAmber,
                    elevation: 0,
                    side: BorderSide(color: SwarmColors.agentAmber.withValues(alpha: 0.4)),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _stashes.isEmpty
              ? const Center(child: Text('No saved stashes', style: TextStyle(fontSize: 11.5, color: SwarmColors.textMuted)))
              : ListView.builder(
                  itemCount: _stashes.length,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemBuilder: (_, i) {
                    final s = _stashes[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: SwarmColors.bgElevated,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: SwarmColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('stash@{${s.index}}', style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: SwarmColors.agentAmber, fontWeight: FontWeight.bold)),
                              const Spacer(),
                              Text(s.relativeDate, style: const TextStyle(fontSize: 10, color: SwarmColors.textMuted)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(s.message, style: const TextStyle(fontSize: 11.5, color: SwarmColors.textPrimary)),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () async {
                                  final diff = await GitLensService.instance.getStashDiff(s.index, cwd: widget.workspacePath);
                                  setState(() {
                                    _diffTitle = 'stash@{${s.index}} Diff';
                                    _diffContent = diff;
                                    _showDiff = true;
                                  });
                                },
                                child: const Text('Diff', style: TextStyle(fontSize: 10.5, color: SwarmColors.agentCyan)),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await GitLensService.instance.stashApply(s.index, cwd: widget.workspacePath);
                                  _refresh();
                                },
                                child: const Text('Apply', style: TextStyle(fontSize: 10.5, color: SwarmColors.agentEmerald)),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await GitLensService.instance.stashPop(s.index, cwd: widget.workspacePath);
                                  _refresh();
                                },
                                child: const Text('Pop', style: TextStyle(fontSize: 10.5, color: SwarmColors.agentSky)),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await GitLensService.instance.stashDrop(s.index, cwd: widget.workspacePath);
                                  _refresh();
                                },
                                child: const Text('Drop', style: TextStyle(fontSize: 10.5, color: SwarmColors.agentRose)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─── Header & Helper Components ──────────────────────────────────────────────

class _TabHeader extends StatelessWidget {
  final _GitTab activeTab;
  final ValueChanged<_GitTab> onSelectTab;
  final int changesCount, branchesCount, stashesCount;

  const _TabHeader({
    required this.activeTab,
    required this.onSelectTab,
    required this.changesCount,
    required this.branchesCount,
    required this.stashesCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: const BoxDecoration(
        color: Color(0xFF0F141F),
        border: Border(bottom: BorderSide(color: SwarmColors.border)),
      ),
      child: Row(
        children: [
          _TabItem('Changes', changesCount > 0 ? '$changesCount' : null, _GitTab.changes, activeTab, onSelectTab),
          _TabItem('Branches', '$branchesCount', _GitTab.branches, activeTab, onSelectTab),
          _TabItem('Commits', null, _GitTab.commits, activeTab, onSelectTab),
          _TabItem('Stashes', stashesCount > 0 ? '$stashesCount' : null, _GitTab.stashes, activeTab, onSelectTab),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final String label;
  final String? badge;
  final _GitTab tab, active;
  final ValueChanged<_GitTab> onTap;

  const _TabItem(this.label, this.badge, this.tab, this.active, this.onTap);

  @override
  Widget build(BuildContext context) {
    final isSelected = tab == active;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(tab),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? SwarmColors.agentCyan : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : SwarmColors.textMuted,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                    decoration: BoxDecoration(
                      color: isSelected ? SwarmColors.agentCyan.withValues(alpha: 0.2) : SwarmColors.bgHover,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(badge!, style: TextStyle(fontSize: 8.5, color: isSelected ? SwarmColors.agentCyan : SwarmColors.textMuted)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String branch;
  final int ahead, behind;
  final VoidCallback onRefresh, onPull, onPush, onOpenStudio;
  final bool loading;

  const _TopBar({
    required this.branch,
    required this.ahead,
    required this.behind,
    required this.onRefresh,
    required this.onPull,
    required this.onPush,
    required this.onOpenStudio,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: SwarmColors.bgSurface,
        border: Border(bottom: BorderSide(color: SwarmColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.call_split_rounded, size: 14, color: SwarmColors.accent),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(branch, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: SwarmColors.textPrimary), overflow: TextOverflow.ellipsis),
          ),
          if (ahead > 0) ...[
            const SizedBox(width: 6),
            Text('↑$ahead', style: const TextStyle(fontSize: 10, color: SwarmColors.agentEmerald)),
          ],
          if (behind > 0) ...[
            const SizedBox(width: 4),
            Text('↓$behind', style: const TextStyle(fontSize: 10, color: SwarmColors.agentAmber)),
          ],
          const Spacer(),
          Tooltip(
            message: 'Open GitLens Studio',
            child: IconButton(
              iconSize: 14,
              icon: const Icon(Icons.hub_rounded),
              color: SwarmColors.agentCyan,
              onPressed: onOpenStudio,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
          const SizedBox(width: 6),
          if (loading)
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: SwarmColors.accent))
          else
            IconButton(iconSize: 14, icon: const Icon(Icons.refresh), color: SwarmColors.textMuted, tooltip: 'Refresh', onPressed: onRefresh, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          const SizedBox(width: 6),
          _SmallBtn('Pull', Icons.download_rounded, SwarmColors.agentSky, onPull),
          const SizedBox(width: 4),
          _SmallBtn('Push', Icons.upload_rounded, SwarmColors.agentEmerald, onPush),
        ],
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _SmallBtn(this.label, this.icon, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
          ]),
        ),
      );
}

class _CommitBox extends StatelessWidget {
  final TextEditingController controller;
  final bool isAmend;
  final ValueChanged<bool> onToggleAmend;
  final VoidCallback onCommit, onStageAll, onGenerateAiMessage;

  const _CommitBox({
    required this.controller,
    required this.isAmend,
    required this.onToggleAmend,
    required this.onCommit,
    required this.onStageAll,
    required this.onGenerateAiMessage,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            maxLines: 3,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: SwarmColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Commit message...',
              hintStyle: const TextStyle(color: SwarmColors.textDisabled, fontSize: 12),
              filled: true,
              fillColor: SwarmColors.bgElevated,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: SwarmColors.border)),
              contentPadding: const EdgeInsets.all(8),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          // Conventional Commit Pills + AI Button
          Row(
            children: [
              _PrefixPill('feat', controller),
              const SizedBox(width: 4),
              _PrefixPill('fix', controller),
              const SizedBox(width: 4),
              _PrefixPill('docs', controller),
              const SizedBox(width: 4),
              _PrefixPill('refactor', controller),
              const Spacer(),
              Tooltip(
                message: 'AI Commit Message Generator',
                child: InkWell(
                  onTap: onGenerateAiMessage,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: SwarmColors.agentCyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: SwarmColors.agentCyan.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, size: 10, color: SwarmColors.agentCyan),
                        SizedBox(width: 3),
                        Text('AI Suggest', style: TextStyle(fontSize: 9.5, color: SwarmColors.agentCyan, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              InkWell(
                onTap: () => onToggleAmend(!isAmend),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: Checkbox(
                        value: isAmend,
                        onChanged: (v) => onToggleAmend(v ?? false),
                        activeColor: SwarmColors.agentCyan,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('Amend', style: TextStyle(fontSize: 10.5, color: SwarmColors.textMuted)),
                  ],
                ),
              ),
              const Spacer(),
              _ActionBtn('Stage All', Icons.add_circle_outline, SwarmColors.agentAmber, onStageAll),
              const SizedBox(width: 6),
              _ActionBtn(isAmend ? 'Amend Commit' : 'Commit', Icons.check_circle_outline, SwarmColors.agentEmerald, onCommit),
            ],
          ),
        ],
      );
}

class _PrefixPill extends StatelessWidget {
  final String prefix;
  final TextEditingController controller;
  const _PrefixPill(this.prefix, this.controller);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        final current = controller.text;
        if (!current.startsWith('$prefix:')) {
          controller.text = '$prefix: $current';
        }
      },
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: SwarmColors.bgHover,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(prefix, style: const TextStyle(fontSize: 9.5, color: SwarmColors.textMuted, fontFamily: 'monospace')),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(this.label, this.icon, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 12),
        label: Text(label, style: const TextStyle(fontSize: 10.5)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData? actionIcon;
  final String? actionTooltip;
  final VoidCallback? onAction;

  const _SectionHeader(this.title, {this.actionIcon, this.actionTooltip, this.onAction});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 9.5, color: SwarmColors.textMuted, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            const Spacer(),
            if (onAction != null && actionIcon != null)
              Tooltip(
                message: actionTooltip ?? '',
                child: InkWell(
                  onTap: onAction,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(actionIcon, size: 13, color: SwarmColors.textMuted),
                  ),
                ),
              ),
          ],
        ),
      );
}

class _ChangeRow extends StatefulWidget {
  final GitChange change;
  final VoidCallback onAction;
  final IconData actionIcon;
  final String actionTooltip;
  final VoidCallback? onDiscard;
  final VoidCallback? onDiff;

  const _ChangeRow({
    required this.change,
    required this.onAction,
    required this.actionIcon,
    required this.actionTooltip,
    this.onDiscard,
    this.onDiff,
  });

  @override
  State<_ChangeRow> createState() => _ChangeRowState();
}

class _ChangeRowState extends State<_ChangeRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(color: _hovered ? SwarmColors.bgHover : Colors.transparent, borderRadius: BorderRadius.circular(3)),
          child: Row(
            children: [
              Text(widget.change.status, style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: widget.change.statusColor, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Expanded(
                child: GestureDetector(
                  onTap: widget.onDiff,
                  child: Text(
                    widget.change.path,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: SwarmColors.textSecondary),
                  ),
                ),
              ),
              if (_hovered) ...[
                if (widget.onDiff != null)
                  Tooltip(message: 'View Diff', child: InkWell(onTap: widget.onDiff, child: const Icon(Icons.compare, size: 12, color: SwarmColors.textMuted))),
                if (widget.onDiscard != null) ...[
                  const SizedBox(width: 4),
                  Tooltip(message: 'Discard Changes', child: InkWell(onTap: widget.onDiscard, child: const Icon(Icons.undo, size: 12, color: SwarmColors.agentRose))),
                ],
                const SizedBox(width: 4),
                Tooltip(message: widget.actionTooltip, child: InkWell(onTap: widget.onAction, child: Icon(widget.actionIcon, size: 13, color: widget.change.statusColor))),
              ],
            ],
          ),
        ),
      );
}

class _NoChanges extends StatelessWidget {
  final VoidCallback onRefresh;
  const _NoChanges({required this.onRefresh});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_outline, size: 40, color: SwarmColors.agentEmerald),
          const SizedBox(height: 8),
          const Text('Working tree clean', style: TextStyle(fontSize: 13, color: SwarmColors.textMuted)),
          TextButton(onPressed: onRefresh, child: const Text('Refresh', style: TextStyle(fontSize: 11))),
        ]),
      );
}

class _DiffView extends StatelessWidget {
  final String file, diff;
  final VoidCallback onBack;
  const _DiffView({required this.file, required this.diff, required this.onBack});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SwarmColors.border))),
            child: Row(children: [
              IconButton(iconSize: 14, icon: const Icon(Icons.arrow_back), onPressed: onBack, padding: EdgeInsets.zero, constraints: const BoxConstraints(), color: SwarmColors.textMuted),
              const SizedBox(width: 8),
              Expanded(child: Text(file, style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: SwarmColors.textSecondary), overflow: TextOverflow.ellipsis)),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: SelectableText.rich(
                TextSpan(
                  children: diff.split('\n').map((line) {
                    Color c = SwarmColors.textSecondary;
                    if (line.startsWith('+')) c = SwarmColors.agentEmerald;
                    if (line.startsWith('-')) c = SwarmColors.agentRose;
                    if (line.startsWith('@@')) c = SwarmColors.agentCyan;
                    if (line.startsWith('diff') || line.startsWith('index') || line.startsWith('+++') || line.startsWith('---')) c = SwarmColors.textMuted;
                    return TextSpan(
                      text: '$line\n',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: c,
                        backgroundColor: line.startsWith('+') ? const Color(0x1510B981) : line.startsWith('-') ? const Color(0x15EF4444) : null,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      );
}
