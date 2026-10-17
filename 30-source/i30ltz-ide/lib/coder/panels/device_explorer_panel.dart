import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../theme/swarm_colors.dart';
import '../editor_model.dart';

// ─── ADB File Entry ──────────────────────────────────────────────────────────
class _AdbEntry {
  final String name;
  final bool isDir;
  final String size;
  final String perms;

  const _AdbEntry({required this.name, required this.isDir, required this.size, required this.perms});

  static _AdbEntry? fromLsLine(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return null;
    final perms = parts[0];
    final isDir = perms.startsWith('d');
    final name = parts.last;
    if (name == '.' || name == '..') return null;
    final size = parts.length >= 5 ? parts[4] : '-';
    return _AdbEntry(name: name, isDir: isDir, size: size, perms: perms);
  }
}

// ─── Device File Explorer Panel ──────────────────────────────────────────────
class DeviceExplorerPanel extends StatefulWidget {
  const DeviceExplorerPanel({super.key});

  @override
  State<DeviceExplorerPanel> createState() => _DeviceExplorerPanelState();
}

class _DeviceExplorerPanelState extends State<DeviceExplorerPanel> {
  List<AndroidDevice> _devices = [];
  AndroidDevice? _selected;
  String _currentPath = '/sdcard';
  List<_AdbEntry> _entries = [];
  List<String> _breadcrumbs = ['/sdcard'];
  bool _loading = false;
  String? _status;
  String? _preview;
  String? _previewName;

  @override
  void initState() {
    super.initState();
    _refreshDevices();
  }

  // ── ADB helpers ─────────────────────────────────────────────────────────────

  Future<ProcessResult> _adb(List<String> args) =>
      Process.run('adb', _selected != null ? ['-s', _selected!.id, ...args] : args);

  Future<void> _refreshDevices() async {
    setState(() => _loading = true);
    try {
      final r = await Process.run('adb', ['devices', '-l']);
      final lines = r.stdout.toString().split('\n').skip(1).where((l) => l.trim().isNotEmpty && !l.contains('List of'));
      final devices = <AndroidDevice>[];
      for (final line in lines) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 2 && parts[1] == 'device') {
          final attrs = line;
          final model = RegExp(r'model:(\S+)').firstMatch(attrs)?.group(1) ?? 'Unknown';
          devices.add(AndroidDevice(id: parts[0], name: model, state: 'device', isEmulator: parts[0].startsWith('emulator')));
        }
      }
      setState(() {
        _devices = devices;
        _selected ??= devices.isNotEmpty ? devices.first : null;
        _loading = false;
      });
      if (_selected != null) await _listDir(_currentPath);
    } catch (e) {
      setState(() { _loading = false; _status = 'ERROR: adb not found or not in PATH'; });
    }
  }

  Future<void> _listDir(String path) async {
    if (_selected == null) return;
    setState(() { _loading = true; _entries = []; _preview = null; });
    try {
      final r = await _adb(['shell', 'ls', '-la', path]);
      final lines = r.stdout.toString().split('\n').where((l) => l.trim().isNotEmpty && !l.startsWith('total'));
      final entries = lines.map(_AdbEntry.fromLsLine).whereType<_AdbEntry>().toList();
      entries.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.compareTo(b.name);
      });
      setState(() {
        _entries = entries;
        _currentPath = path;
        _breadcrumbs = _pathToBreadcrumbs(path);
        _loading = false;
        _status = '${entries.where((e) => e.isDir).length} dirs, ${entries.where((e) => !e.isDir).length} files';
      });
    } catch (e) {
      setState(() { _loading = false; _status = 'ERROR: $e'; });
    }
  }

  List<String> _pathToBreadcrumbs(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    final crumbs = <String>['/'];
    var cum = '';
    for (final p in parts) {
      cum += '/$p';
      crumbs.add(cum);
    }
    return crumbs;
  }

  void _navigate(String path) => _listDir(path);

  void _navigateUp() {
    final idx = _currentPath.lastIndexOf('/');
    if (idx <= 0) return;
    _navigate(_currentPath.substring(0, idx));
  }

  // ── Pull file ────────────────────────────────────────────────────────────────

  Future<void> _pullFile(_AdbEntry entry) async {
    final remote = '$_currentPath/${entry.name}';
    final dest = await FilePicker.getDirectoryPath();
    if (dest == null) return;
    final local = '$dest/${entry.name}';
    setState(() { _status = 'Pulling ${entry.name}…'; _loading = true; });
    final r = await _adb(['pull', remote, local]);
    setState(() {
      _loading = false;
      _status = r.exitCode == 0 ? '✓ Pulled to $local' : 'ERROR: ${r.stderr}';
    });
  }

  // ── Push file ────────────────────────────────────────────────────────────────

  Future<void> _pushFile() async {
    final result = await FilePicker.pickFile(type: FileType.any);
    if (result?.path == null) return;
    final localPath = result!.path!;
    final remoteDest = '$_currentPath/${result.name}';
    setState(() { _status = 'Pushing ${result.name}…'; _loading = true; });
    final r = await _adb(['push', localPath, remoteDest]);
    setState(() {
      _loading = false;
      _status = r.exitCode == 0 ? '✓ Pushed to $remoteDest' : 'ERROR: ${r.stderr}';
    });
    if (r.exitCode == 0) await _listDir(_currentPath);
  }

  // ── Delete ────────────────────────────────────────────────────────────────────

  Future<void> _deleteEntry(_AdbEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: SwarmColors.bgElevated,
        title: const Text('Delete?', style: TextStyle(color: SwarmColors.textPrimary, fontSize: 14)),
        content: Text('Delete ${entry.name} from device?', style: const TextStyle(color: SwarmColors.textSecondary, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: SwarmColors.textMuted))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: SwarmColors.agentRose))),
        ],
      ),
    );
    if (confirm != true) return;
    final remote = '$_currentPath/${entry.name}';
    final r = await _adb(['shell', entry.isDir ? 'rm -r' : 'rm', remote]);
    setState(() => _status = r.exitCode == 0 ? '✓ Deleted $remote' : 'ERROR: ${r.stderr}');
    await _listDir(_currentPath);
  }

  // ── Preview text file ─────────────────────────────────────────────────────────

  Future<void> _previewFile(_AdbEntry entry) async {
    if (entry.isDir) { _navigate('$_currentPath/${entry.name}'); return; }
    final ext = entry.name.split('.').last.toLowerCase();
    const textExts = ['txt', 'log', 'json', 'xml', 'gradle', 'kt', 'java', 'dart', 'py', 'js', 'ts', 'md', 'yaml', 'yml', 'sh', 'csv'];
    if (!textExts.contains(ext)) {
      setState(() { _previewName = null; _preview = '(Binary file — pull to view locally)'; });
      return;
    }
    final r = await _adb(['shell', 'cat', '$_currentPath/${entry.name}']);
    setState(() {
      _previewName = entry.name;
      _preview = r.exitCode == 0 ? r.stdout.toString() : 'ERROR: ${r.stderr}';
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Header ─────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SwarmColors.border))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.phone_android_rounded, size: 13, color: SwarmColors.agentEmerald),
            const SizedBox(width: 6),
            const Text('DEVICE FILES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: SwarmColors.textMuted, letterSpacing: 1)),
            const Spacer(),
            _IconBtn(Icons.refresh, 'Refresh', _refreshDevices),
            _IconBtn(Icons.upload_file_rounded, 'Push File', _pushFile),
          ]),
          const SizedBox(height: 6),
          // Device selector
          if (_devices.isEmpty)
            const Text('No devices connected', style: TextStyle(fontSize: 11, color: SwarmColors.agentRose))
          else
            DropdownButtonHideUnderline(
              child: DropdownButton<AndroidDevice>(
                value: _selected,
                isExpanded: true,
                dropdownColor: SwarmColors.bgElevated,
                style: const TextStyle(fontSize: 11, color: SwarmColors.textSecondary, fontFamily: 'monospace'),
                items: _devices.map((d) => DropdownMenuItem(value: d, child: Text('${d.name}  [${d.id}]'))).toList(),
                onChanged: (d) { setState(() => _selected = d); if (d != null) _listDir(_currentPath); },
              ),
            ),
        ]),
      ),

      // ── Breadcrumb bar ──────────────────────────────────────
      Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: const BoxDecoration(color: SwarmColors.bgElevated, border: Border(bottom: BorderSide(color: SwarmColors.border))),
        child: Row(children: [
          InkWell(onTap: _navigateUp, child: const Icon(Icons.arrow_back_ios_new_rounded, size: 12, color: SwarmColors.textMuted)),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var i = 0; i < _breadcrumbs.length; i++) ...[
                  if (i > 0) const Text(' / ', style: TextStyle(fontSize: 10, color: SwarmColors.textDisabled)),
                  InkWell(
                    onTap: () => _navigate(_breadcrumbs[i]),
                    child: Text(
                      _breadcrumbs[i] == '/' ? '/' : _breadcrumbs[i].split('/').last,
                      style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: i == _breadcrumbs.length - 1 ? SwarmColors.textPrimary : SwarmColors.agentCyan),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ]),
      ),

      // ── Status strip ────────────────────────────────────────
      if (_status != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          color: SwarmColors.bgPanel,
          child: Row(children: [
            Expanded(child: Text(_status!, style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: _status!.startsWith('ERROR') ? SwarmColors.agentRose : _status!.startsWith('✓') ? SwarmColors.agentEmerald : SwarmColors.textMuted), overflow: TextOverflow.ellipsis)),
          ]),
        ),

      // ── File list + preview ──────────────────────────────────
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 1.5, color: SwarmColors.agentEmerald))
            : _selected == null
                ? const Center(child: Text('Connect an Android device\nand enable USB debugging', textAlign: TextAlign.center, style: TextStyle(color: SwarmColors.textMuted, fontSize: 12)))
                : _preview != null
                    ? _PreviewPane(name: _previewName, content: _preview!, onBack: () => setState(() { _preview = null; _previewName = null; }))
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: _entries.length,
                        itemExtent: 34,
                        itemBuilder: (_, i) => _FileRow(
                          entry: _entries[i],
                          onTap: () => _previewFile(_entries[i]),
                          onPull: () => _pullFile(_entries[i]),
                          onDelete: () => _deleteEntry(_entries[i]),
                        ),
                      ),
      ),
    ]);
  }
}

// ─── File Row ─────────────────────────────────────────────────────────────────
class _FileRow extends StatefulWidget {
  final _AdbEntry entry;
  final VoidCallback onTap, onPull, onDelete;

  const _FileRow({required this.entry, required this.onTap, required this.onPull, required this.onDelete});

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final ext = e.name.contains('.') ? e.name.split('.').last.toLowerCase() : '';
    final color = e.isDir ? SwarmColors.agentAmber : _extColor(ext);
    final icon = e.isDir ? Icons.folder_rounded : _extIcon(ext);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hovered ? SwarmColors.bgElevated : Colors.transparent,
            border: const Border(bottom: BorderSide(color: SwarmColors.border, width: 0.3)),
          ),
          child: Row(children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(e.name, style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: e.isDir ? SwarmColors.textPrimary : SwarmColors.textSecondary), overflow: TextOverflow.ellipsis)),
            if (!e.isDir) Text(e.size, style: const TextStyle(fontSize: 10, color: SwarmColors.textDisabled, fontFamily: 'monospace')),
            if (_hovered) ...[
              const SizedBox(width: 4),
              _RowBtn(Icons.download_rounded, 'Pull', SwarmColors.agentCyan, widget.onPull),
              _RowBtn(Icons.delete_outline_rounded, 'Delete', SwarmColors.agentRose, widget.onDelete),
            ],
          ]),
        ),
      ),
    );
  }

  Color _extColor(String ext) => switch (ext) {
        'apk' || 'aab'        => SwarmColors.agentEmerald,
        'dart' || 'kt' || 'java' => const Color(0xFF82AAFF),
        'json' || 'yaml'      => SwarmColors.agentAmber,
        'png' || 'jpg' || 'gif' => SwarmColors.agentPurple,
        'mp4' || 'mkv'        => SwarmColors.agentOrange,
        _                     => SwarmColors.textMuted,
      };

  IconData _extIcon(String ext) => switch (ext) {
        'apk' || 'aab'          => Icons.android_rounded,
        'png' || 'jpg' || 'gif' => Icons.image_rounded,
        'mp4' || 'mkv' || 'avi' => Icons.movie_rounded,
        'json'                  => Icons.data_object_rounded,
        'txt' || 'log' || 'md'  => Icons.article_rounded,
        _                       => Icons.insert_drive_file_rounded,
      };
}

class _RowBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  const _RowBtn(this.icon, this.tooltip, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(3),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), child: Icon(icon, size: 13, color: color)),
        ),
      );
}

// ─── Preview Pane ─────────────────────────────────────────────────────────────
class _PreviewPane extends StatelessWidget {
  final String? name;
  final String content;
  final VoidCallback onBack;

  const _PreviewPane({this.name, required this.content, required this.onBack});

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: SwarmColors.bgElevated,
          child: Row(children: [
            InkWell(onTap: onBack, child: const Icon(Icons.arrow_back_ios_new_rounded, size: 12, color: SwarmColors.agentCyan)),
            const SizedBox(width: 8),
            Expanded(child: Text(name ?? 'Preview', style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: SwarmColors.textSecondary))),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: SelectableText(content, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: SwarmColors.textSecondary, height: 1.5)),
          ),
        ),
      ]);
}

// ─── Shared icon button ───────────────────────────────────────────────────────
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconBtn(this.icon, this.tooltip, this.onTap);

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(padding: const EdgeInsets.all(5), child: Icon(icon, size: 14, color: SwarmColors.textMuted)),
        ),
      );
}
