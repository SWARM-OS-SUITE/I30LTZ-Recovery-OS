import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/swarm_colors.dart';
import '../../services/hot_reload_service.dart';

// ─── Task Model ───────────────────────────────────────────────────────────────
class RunTask {
  String id;
  String name;
  String command;
  String args;
  String? workdir;
  bool isBuiltin;

  RunTask({required this.id, required this.name, required this.command, this.args = '', this.workdir, this.isBuiltin = false});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'command': command, 'args': args, 'workdir': workdir ?? ''};
  factory RunTask.fromJson(Map<String, dynamic> j) => RunTask(id: j['id'] ?? '', name: j['name'] ?? '', command: j['command'] ?? '', args: j['args'] ?? '', workdir: (j['workdir'] as String?)?.isNotEmpty == true ? j['workdir'] : null);
}

// ─── Builtin quick-task definitions ──────────────────────────────────────────
List<RunTask> _builtins(String? projectPath) => [
  RunTask(id: 'flutter-run',       name: 'flutter run (Live App)', command: 'flutter', args: 'run',          workdir: projectPath, isBuiltin: true),
  RunTask(id: 'flutter-pub-get',   name: 'flutter pub get',     command: 'flutter', args: 'pub get',       workdir: projectPath, isBuiltin: true),
  RunTask(id: 'flutter-test',      name: 'flutter test',        command: 'flutter', args: 'test',          workdir: projectPath, isBuiltin: true),
  RunTask(id: 'flutter-analyze',   name: 'dart analyze',        command: 'dart',    args: 'analyze',       workdir: projectPath, isBuiltin: true),
  RunTask(id: 'flutter-format',    name: 'dart format .',       command: 'dart',    args: 'format .',      workdir: projectPath, isBuiltin: true),
  RunTask(id: 'flutter-build-apk', name: 'flutter build apk',   command: 'flutter', args: 'build apk',    workdir: projectPath, isBuiltin: true),
  RunTask(id: 'flutter-clean',     name: 'flutter clean',       command: 'flutter', args: 'clean',         workdir: projectPath, isBuiltin: true),
  RunTask(id: 'gradle-test',       name: 'gradlew test',        command: './gradlew', args: 'test',        workdir: projectPath != null ? '$projectPath/android' : null, isBuiltin: true),
  RunTask(id: 'npm-install',       name: 'npm install',         command: 'npm',     args: 'install',       workdir: projectPath, isBuiltin: true),
  RunTask(id: 'npm-test',          name: 'npm test',            command: 'npm',     args: 'test',          workdir: projectPath, isBuiltin: true),
  RunTask(id: 'make',              name: 'make',                command: 'make',    args: '',              workdir: projectPath, isBuiltin: true),
];

// ─── Task Storage ─────────────────────────────────────────────────────────────
class TaskStorage {
  static const _key = 'ide_run_tasks';

  static Future<List<RunTask>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => RunTask.fromJson(e)).toList();
    } catch (_) { return []; }
  }

  static Future<void> save(List<RunTask> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(tasks.map((t) => t.toJson()).toList()));
  }
}

// ─── Task Runner Panel ────────────────────────────────────────────────────────
class TaskRunnerPanel extends StatefulWidget {
  final String? projectPath;
  const TaskRunnerPanel({super.key, this.projectPath});

  @override
  State<TaskRunnerPanel> createState() => _TaskRunnerPanelState();
}

class _TaskRunnerPanelState extends State<TaskRunnerPanel> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<RunTask> _custom = [];
  bool _loading = true;

  // Run state
  RunTask? _running;
  Process? _process;
  final List<_LogLine> _output = [];
  bool _isRunning = false;
  int? _exitCode;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    TaskStorage.load().then((tasks) => setState(() { _custom = tasks; _loading = false; }));
  }

  @override
  void dispose() {
    _tab.dispose();
    _process?.kill();
    HotReloadService.instance.unregisterActiveFlutterProcess();
    super.dispose();
  }

  List<RunTask> get _builtinTasks => _builtins(widget.projectPath);

  // ── Run ────────────────────────────────────────────────────────────────────

  Future<void> _runTask(RunTask task) async {
    if (_isRunning) { _process?.kill(); return; }
    setState(() { _running = task; _output.clear(); _isRunning = true; _exitCode = null; });
    _log('> ${task.command} ${task.args}', _LogKind.cmd);

    try {
      final parts = [task.command, ...task.args.trim().split(RegExp(r'\s+'))].where((s) => s.isNotEmpty).toList();
      final workdir = task.workdir ?? widget.projectPath;
      final absWorkdir = workdir != null ? Directory(workdir).absolute.path : Directory.current.absolute.path;

      // Real isolation via systemd-run --user (a transient SERVICE unit,
      // not --scope), not the fabricated "sandboxed" telemetry LucyServer's
      // /api/sandbox/execute reports (found 2026-09-19: that endpoint has
      // no cgroup, no enforced memory limit — MemoryPeakMb is literally
      // `limit / 2`, not measured — and it can't run here anyway: it
      // executes a code *string* in a fixed scratch dir with no streaming
      // output, incompatible with a long-running `flutter run` against the
      // real project).
      //
      // --scope was tried first and rejected: scope units only support
      // cgroup/resource properties (MemoryMax, CPUQuota) — the actual
      // sandboxing directives (NoNewPrivileges, ProtectSystem, ReadWritePaths)
      // are ExecContext properties that only apply to service units, and
      // systemd-run rejects them on a scope ("Unknown assignment") — verified
      // by actually running both forms, not assumed. --pipe connects the
      // transient service's stdio back to this process (so streaming output
      // still works) and --wait blocks until it exits with the real exit code.
      //
      // Deliberately does NOT lock down $HOME (ProtectHome) — flutter/npm/
      // gradle all write build caches under $HOME (~/.pub-cache, ~/.npm,
      // ~/.gradle) and every builtin task above depends on that working.
      // What this DOES enforce for real, via the kernel/cgroups — verified
      // by actually testing a write outside ReadWritePaths and confirming
      // "Read-only file system", not just trusting the flags: the running
      // task can't touch OS files outside $HOME (ProtectSystem=strict —
      // which also makes the project dir read-only unless explicitly
      // allowed back in, hence ReadWritePaths below), can't gain privileges
      // (NoNewPrivileges), and can't runaway on memory/CPU. Network stays
      // open — build tools need it (pub get, npm install, git).
      _process = await Process.start(
        'systemd-run',
        [
          '--user', '--pipe', '--wait', '--collect', '--quiet',
          '-p', 'NoNewPrivileges=yes',
          '-p', 'ProtectSystem=strict',
          '-p', 'ProtectControlGroups=yes',
          '-p', 'ProtectKernelTunables=yes',
          '-p', 'ProtectKernelModules=yes',
          '-p', 'ReadWritePaths=$absWorkdir',
          '-p', 'MemoryMax=4096M',
          '-p', 'CPUQuota=400%',
          '-p', 'WorkingDirectory=$absWorkdir',
          '--',
          parts.first,
          ...parts.skip(1),
        ],
        workingDirectory: absWorkdir,
      );

      if (task.command == 'flutter' && task.args.contains('run')) {
        HotReloadService.instance.registerActiveFlutterProcess(_process!);
      }

      _process!.stdout.transform(const SystemEncoding().decoder).listen((d) {
        for (final l in d.split('\n')) {
          if (l.trim().isEmpty) continue;
          final kind = l.contains('error') || l.contains('FAILED') ? _LogKind.error : l.contains('warn') ? _LogKind.warn : _LogKind.info;
          if (mounted) setState(() => _output.add(_LogLine(l, kind)));
        }
      });
      _process!.stderr.transform(const SystemEncoding().decoder).listen((d) {
        for (final l in d.split('\n')) {
          if (l.trim().isEmpty) continue;
          if (mounted) setState(() => _output.add(_LogLine(l, _LogKind.error)));
        }
      });

      final code = await _process!.exitCode;
      HotReloadService.instance.unregisterActiveFlutterProcess();
      if (mounted) {
        setState(() {
        _isRunning = false;
        _exitCode = code;
        _output.add(_LogLine(code == 0 ? '✓ Completed (exit 0)' : '✗ Failed (exit $code)', code == 0 ? _LogKind.success : _LogKind.error));
      });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
        _isRunning = false;
        _output.add(_LogLine('ERROR: $e', _LogKind.error));
      });
      }
    }
  }

  void _stopTask() {
    _process?.kill();
    HotReloadService.instance.unregisterActiveFlutterProcess();
    setState(() => _isRunning = false);
  }
  void _log(String msg, _LogKind kind) => setState(() => _output.add(_LogLine(msg, kind)));

  // ── Custom task CRUD ───────────────────────────────────────────────────────

  Future<void> _addOrEdit([RunTask? existing]) async {
    final result = await showDialog<RunTask>(
      context: context,
      builder: (_) => _TaskDialog(existing: existing, projectPath: widget.projectPath),
    );
    if (result == null) return;
    setState(() {
      if (existing != null) {
        final idx = _custom.indexWhere((t) => t.id == existing.id);
        if (idx >= 0) _custom[idx] = result;
      } else {
        _custom.add(result);
      }
    });
    await TaskStorage.save(_custom);
  }

  Future<void> _delete(RunTask task) async {
    setState(() => _custom.removeWhere((t) => t.id == task.id));
    await TaskStorage.save(_custom);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Header tabs
      Container(
        color: SwarmColors.bgSurface,
        child: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          labelColor: SwarmColors.accent,
          unselectedLabelColor: SwarmColors.textMuted,
          indicatorColor: SwarmColors.accent,
          indicatorWeight: 2,
          tabs: const [Tab(text: 'TASKS', height: 32), Tab(text: 'OUTPUT', height: 32)],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tab,
          children: [
            // ── Tasks list ─────────────────────────────────────
            _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 1.5, color: SwarmColors.accent))
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      // Custom tasks section
                      _SectionHeader(
                        'MY TASKS',
                        trailing: InkWell(
                          onTap: () => _addOrEdit(),
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.add_rounded, size: 15, color: SwarmColors.accent)),
                        ),
                      ),
                      if (_custom.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text('No custom tasks. Click + to add one.', style: TextStyle(fontSize: 11, color: SwarmColors.textDisabled)),
                        )
                      else
                        ..._custom.map((t) => _TaskRow(task: t, running: _running?.id == t.id && _isRunning, onRun: () { _runTask(t); _tab.animateTo(1); }, onStop: _stopTask, onEdit: () => _addOrEdit(t), onDelete: () => _delete(t))),
                      const SizedBox(height: 8),
                      const _SectionHeader('QUICK TASKS'),
                      ..._builtinTasks.map((t) => _TaskRow(task: t, running: _running?.id == t.id && _isRunning, onRun: () { _runTask(t); _tab.animateTo(1); }, onStop: _stopTask)),
                    ],
                  ),

            // ── Output pane ────────────────────────────────────
            Column(children: [
              // Status bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                color: SwarmColors.bgElevated,
                child: Row(children: [
                  if (_running != null) ...[
                    Icon(_isRunning ? Icons.circle : (_exitCode == 0 ? Icons.check_circle : Icons.cancel), size: 11, color: _isRunning ? SwarmColors.agentAmber : (_exitCode == 0 ? SwarmColors.agentEmerald : SwarmColors.agentRose)),
                    const SizedBox(width: 6),
                    Text(_running!.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: SwarmColors.textSecondary)),
                    if (_isRunning) ...[
                      const SizedBox(width: 6),
                      const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: SwarmColors.agentAmber)),
                    ],
                  ] else
                    const Text('No task running', style: TextStyle(fontSize: 11, color: SwarmColors.textMuted)),
                  const Spacer(),
                  if (_isRunning)
                    InkWell(onTap: _stopTask, child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.stop_rounded, size: 14, color: SwarmColors.agentRose)))
                  else if (_output.isNotEmpty)
                    InkWell(onTap: () => setState(() => _output.clear()), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.clear_all_rounded, size: 14, color: SwarmColors.textMuted))),
                ]),
              ),
              // Log
              Expanded(
                child: _output.isEmpty
                    ? const Center(child: Text('Run a task to see output.', style: TextStyle(color: SwarmColors.textMuted, fontSize: 12)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _output.length,
                        itemBuilder: (_, i) {
                          final line = _output[i];
                          return Text(line.text, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: line.color, height: 1.5));
                        },
                      ),
              ),
            ]),
          ],
        ),
      ),
    ]);
  }
}

// ─── Log line ─────────────────────────────────────────────────────────────────
enum _LogKind { cmd, info, warn, error, success }

class _LogLine {
  final String text;
  final _LogKind kind;
  const _LogLine(this.text, this.kind);

  Color get color => switch (kind) {
        _LogKind.cmd     => SwarmColors.agentCyan,
        _LogKind.info    => SwarmColors.textSecondary,
        _LogKind.warn    => SwarmColors.agentAmber,
        _LogKind.error   => SwarmColors.agentRose,
        _LogKind.success => SwarmColors.agentEmerald,
      };
}

// ─── Task Row ─────────────────────────────────────────────────────────────────
class _TaskRow extends StatelessWidget {
  final RunTask task;
  final bool running;
  final VoidCallback onRun, onStop;
  final VoidCallback? onEdit, onDelete;

  const _TaskRow({required this.task, required this.running, required this.onRun, required this.onStop, this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: running ? SwarmColors.agentAmber.withValues(alpha: 0.06) : Colors.transparent,
          border: const Border(bottom: BorderSide(color: SwarmColors.border, width: 0.3)),
        ),
        child: Row(children: [
          InkWell(
            onTap: running ? onStop : onRun,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                color: running ? SwarmColors.agentRose.withValues(alpha: 0.15) : SwarmColors.agentEmerald.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: running ? SwarmColors.agentRose.withValues(alpha: 0.4) : SwarmColors.agentEmerald.withValues(alpha: 0.3)),
              ),
              child: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 15, color: running ? SwarmColors.agentRose : SwarmColors.agentEmerald),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(task.name, style: const TextStyle(fontSize: 12, color: SwarmColors.textPrimary, fontWeight: FontWeight.w500)),
              Text('${task.command} ${task.args}'.trim(), style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: SwarmColors.textDisabled), overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (task.isBuiltin)
            const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.bolt_rounded, size: 12, color: SwarmColors.agentAmber))
          else ...[
            if (onEdit != null) InkWell(onTap: onEdit, borderRadius: BorderRadius.circular(3), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.edit_rounded, size: 13, color: SwarmColors.agentCyan))),
            if (onDelete != null) InkWell(onTap: onDelete, borderRadius: BorderRadius.circular(3), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.delete_outline_rounded, size: 13, color: SwarmColors.agentRose))),
          ],
        ]),
      );
}

// ─── Section header ───────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionHeader(this.title, {this.trailing});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 4),
        child: Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: SwarmColors.textMuted, letterSpacing: 1.2))),
          if (trailing != null) trailing!,
        ]),
      );
}

// ─── Task Dialog ──────────────────────────────────────────────────────────────
class _TaskDialog extends StatefulWidget {
  final RunTask? existing;
  final String? projectPath;
  const _TaskDialog({this.existing, this.projectPath});

  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  late TextEditingController _name, _cmd, _args, _workdir;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _cmd = TextEditingController(text: e?.command ?? '');
    _args = TextEditingController(text: e?.args ?? '');
    _workdir = TextEditingController(text: e?.workdir ?? widget.projectPath ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name, _cmd, _args, _workdir]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: SwarmColors.bgElevated,
        title: Text(widget.existing == null ? 'New Task' : 'Edit Task', style: const TextStyle(color: SwarmColors.textPrimary, fontSize: 14)),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _DField('Task name', _name, 'e.g. Run tests'),
            const SizedBox(height: 8),
            _DField('Command', _cmd, 'e.g. flutter'),
            const SizedBox(height: 8),
            _DField('Arguments', _args, 'e.g. test --coverage'),
            const SizedBox(height: 8),
            _DField('Working directory', _workdir, 'Leave empty for project root'),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: SwarmColors.textMuted))),
          ElevatedButton(
            onPressed: () {
              if (_name.text.trim().isEmpty || _cmd.text.trim().isEmpty) return;
              Navigator.pop(context, RunTask(
                id: widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                name: _name.text.trim(), command: _cmd.text.trim(),
                args: _args.text.trim(), workdir: _workdir.text.trim().isEmpty ? null : _workdir.text.trim(),
              ));
            },
            style: ElevatedButton.styleFrom(backgroundColor: SwarmColors.accent.withValues(alpha: 0.2), foregroundColor: SwarmColors.accent, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
            child: Text(widget.existing == null ? 'Create' : 'Save', style: const TextStyle(fontSize: 12)),
          ),
        ],
      );
}

class _DField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String hint;
  const _DField(this.label, this.ctrl, this.hint);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: SwarmColors.textMuted, fontWeight: FontWeight.bold)),
        const SizedBox(height: 3),
        TextField(
          controller: ctrl,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: SwarmColors.textPrimary),
          decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: SwarmColors.textDisabled, fontSize: 11), isDense: true, filled: true, fillColor: SwarmColors.bgPanel, border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: SwarmColors.border)), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
        ),
      ]);
}
