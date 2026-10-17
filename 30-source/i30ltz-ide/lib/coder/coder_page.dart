// ═══════════════════════════════════════════════════════════════
// I30LTZ IDE editor page (CoderPage), from the SWARM OS Apex IDE
// Full-featured code editor: file tree, syntax highlight, git,
// Android tools, search, extensions, terminal, diff, logcat.
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io' hide Platform;
import '../platform/platform.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/swarm_colors.dart';
import '../theme/swarm_text_styles.dart';
import 'editor_model.dart';
import 'code_editor_widget.dart' show saveFile;
import 'bottom_panel.dart';
import 'panels/file_explorer_panel.dart';
import 'panels/git_panel.dart';
import 'panels/search_panel.dart';
import 'panels/extensions_panel.dart';
import 'panels/device_explorer_panel.dart';
import 'panels/snippets_panel.dart';
import 'panels/keybindings_panel.dart';
import 'panels/task_runner_panel.dart';
import 'panels/accessibility_panel.dart';
import 'panels/ollama_panel.dart';
import 'accessibility.dart';
import 'split_editor.dart';
import 'intellisense/completion_provider.dart' show CompletionProvider;
import '../services/git_lens_service.dart';
import 'panels/profile_manager_panel.dart';
import '../services/workspace_state_service.dart';
import '../services/hot_reload_service.dart';
import 'widgets/hot_reload_toolbar_button.dart';

enum _SidePanel { explorer, search, git, deviceFiles, tasks, extensions, ollama, settings }

class CoderPage extends StatefulWidget {
  const CoderPage({super.key});

  @override
  State<CoderPage> createState() => _CoderPageState();
}

class _CoderPageState extends State<CoderPage> {
  // ── Workspace ───────────────────────────────────────────────
  String? _workspacePath;

  // ── Open Files ──────────────────────────────────────────────
  final List<OpenFile> _openFiles = [];
  int _activeFileIdx = -1;
  OpenFile? get _activeFile => _activeFileIdx >= 0 && _activeFileIdx < _openFiles.length ? _openFiles[_activeFileIdx] : null;

  // ── Layout ──────────────────────────────────────────────────
  _SidePanel _sidePanel = _SidePanel.explorer;
  bool _showSide = true;
  bool _showBottom = true;
  double _sideWidth = 260;
  double _bottomHeight = 240;

  // ── Split editor ────────────────────────────────────────────
  SplitDirection _splitDir = SplitDirection.none;
  int _secondaryFileIdx = -1;

  // ── Status ──────────────────────────────────────────────────
  int _cursorLine = 1, _cursorCol = 1;
  final List<String> _outputLines = [];
  final List<DiagnosticItem> _diagnostics = [];
  GitBlameInfo? _currentBlame;
  String? _gitBranch;

  @override
  void initState() {
    super.initState();
    _loadLastWorkspace();
    CompletionProvider.loadCustomSnippets();
    AccessibilitySettings.instance.load();
  }

  @override
  void dispose() {
    for (final f in _openFiles) {
      f.dispose();
    }
    super.dispose();
  }

  // ── Workspace ──────────────────────────────────────────────────────────────

  Future<void> _loadLastWorkspace() async {
    final stateService = WorkspaceStateService.instance;
    final snapshot = await stateService.loadState();
    if (snapshot.workspacePath != null && Directory(snapshot.workspacePath!).existsSync()) {
      setState(() => _workspacePath = snapshot.workspacePath);
      _refreshGitBranch();
      for (final p in snapshot.openFilePaths) {
        if (File(p).existsSync()) {
          try {
            final content = await File(p).readAsString();
            _openFiles.add(OpenFile(path: p, content: content));
          } catch (_) {}
        }
      }
      if (_openFiles.isNotEmpty) {
        final idx = snapshot.activeFileIndex.clamp(0, _openFiles.length - 1);
        setState(() => _activeFileIdx = idx);
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString('coder_workspace');
      if (last != null && Directory(last).existsSync()) {
        setState(() => _workspacePath = last);
        _refreshGitBranch();
      }
    }
  }

  void _syncWorkspaceState() {
    WorkspaceStateService.instance.updateState(
      workspacePath: _workspacePath,
      openFilePaths: _openFiles.map((f) => f.path).toList(),
      activeFileIndex: _activeFileIdx,
      cursorLine: _cursorLine,
      cursorCol: _cursorCol,
      isSplit: _splitDir != SplitDirection.none,
    );
  }

  Future<void> _refreshGitBranch() async {
    if (_workspacePath == null) return;
    final branches = await GitLensService.instance.getBranches(cwd: _workspacePath);
    final current = branches.where((b) => b.isCurrent).firstOrNull?.name;
    if (mounted) {
      setState(() => _gitBranch = current);
    }
  }

  Future<void> _openFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path != null) {
      setState(() { _workspacePath = path; _openFiles.clear(); _activeFileIdx = -1; });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('coder_workspace', path);
      _refreshGitBranch();
      _syncWorkspaceState();
    }
  }

  // ── File Management ────────────────────────────────────────────────────────

  Future<void> _openFile(String path) async {
    final existing = _openFiles.indexWhere((f) => f.path == path);
    if (existing >= 0) {
      setState(() => _activeFileIdx = existing);
      _syncWorkspaceState();
      return;
    }
    try {
      final content = await File(path).readAsString();
      final file = OpenFile(path: path, content: content);
      setState(() { _openFiles.add(file); _activeFileIdx = _openFiles.length - 1; });
      _syncWorkspaceState();
    } catch (e) {
      _log('Error opening $path: $e');
    }
  }

  Future<void> _saveActiveFile() async {
    if (_activeFile == null) return;
    await saveFile(_activeFile!);
    setState(() {});
    _syncWorkspaceState();
    _log('Saved: ${_activeFile!.name}');
  }

  void _closeFile(int idx) {
    if (idx < 0 || idx >= _openFiles.length) return;
    _openFiles[idx].dispose();
    setState(() {
      _openFiles.removeAt(idx);
      if (_openFiles.isEmpty) {
        _activeFileIdx = -1;
      } else if (_activeFileIdx >= _openFiles.length) {
        _activeFileIdx = _openFiles.length - 1;
      }
    });
    _syncWorkspaceState();
  }

  void _log(String message) => setState(() => _outputLines.add('[${DateTime.now().toIso8601String().substring(11, 19)}] $message'));

  // ── Keyboard Shortcuts ─────────────────────────────────────────────────────

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyS) {
      _saveActiveFile();
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyB) {
      setState(() => _showSide = !_showSide);
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyJ) {
      setState(() => _showBottom = !_showBottom);
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyW) {
      _closeFile(_activeFileIdx);
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyP) {
      setState(() { _sidePanel = _SidePanel.search; _showSide = true; });
      return KeyEventResult.handled;
    }
    if (ctrl && shift && event.logicalKey == LogicalKeyboardKey.keyG) {
      setState(() { _sidePanel = _SidePanel.git; _showSide = true; });
      return KeyEventResult.handled;
    }
    if (ctrl && !shift && event.logicalKey == LogicalKeyboardKey.keyR) {
      HotReloadService.instance.hotReload(projectPath: _workspacePath);
      return KeyEventResult.handled;
    }
    if (ctrl && shift && event.logicalKey == LogicalKeyboardKey.keyR) {
      HotReloadService.instance.hotRestart(projectPath: _workspacePath);
      return KeyEventResult.handled;
    }
    if (ctrl && event.logicalKey == LogicalKeyboardKey.slash) {
      showDialog(context: context, builder: (_) => const _ShortcutOverlay());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Container(
        color: SwarmColors.bg,
        child: Column(
          children: [
            // ── Menu Bar ──────────────────────────────────────
            _MenuBar(
              workspacePath: _workspacePath,
              onOpenFolder: _openFolder,
              onSave: _activeFile != null ? _saveActiveFile : null,
              onToggleSide: () => setState(() => _showSide = !_showSide),
              onToggleBottom: () => setState(() => _showBottom = !_showBottom),
              onShowShortcuts: () => showDialog(context: context, builder: (_) => const _ShortcutOverlay()),
            ),
            // ── Main Area ─────────────────────────────────────
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Activity Bar
                  _ActivityBar(
                    active: _sidePanel,
                    onChange: (p) => setState(() {
                      if (_sidePanel == p && _showSide) {
                        _showSide = false;
                      } else {
                        _sidePanel = p;
                        _showSide = true;
                      }
                    }),
                  ),
                  // Side Panel
                  if (_showSide) ...[
                    _SidePanelContainer(
                      width: _sideWidth,
                      panel: _sidePanel,
                      workspacePath: _workspacePath,
                      activeFilePath: _activeFile?.path,
                      onFileOpen: _openFile,
                      onOpenFolder: _openFolder,
                      onResultTap: (rec) => _openFile(rec.$1).then((_) {
                        setState(() { _cursorLine = rec.$2; _cursorCol = 1; });
                      }),
                    ),
                    // Resize handle
                    _ResizeHandle(
                      onDrag: (dx) => setState(() => _sideWidth = (_sideWidth + dx).clamp(160, 480)),
                    ),
                  ],
                  // Editor + Bottom
                  Expanded(
                    child: Column(
                      children: [
                        // Editor tabs
                        if (_openFiles.isNotEmpty)
                          _TabStrip(
                            files: _openFiles,
                            activeIdx: _activeFileIdx,
                            onSelect: (i) => setState(() => _activeFileIdx = i),
                            onClose: _closeFile,
                          ),
                        // Editor or welcome
                        Expanded(
                          child: _openFiles.isEmpty
                              ? _WelcomeScreen(
                                  workspacePath: _workspacePath,
                                  onOpenFolder: _openFolder,
                                  recentFiles: const [],
                                  onOpenFile: _openFile,
                                )
                              : SplitEditor(
                                  files: _openFiles,
                                  primaryIdx: _activeFileIdx,
                                  secondaryIdx: _secondaryFileIdx >= 0 ? _secondaryFileIdx : null,
                                  direction: _splitDir,
                                  workspacePath: _workspacePath,
                                  targetLine: _cursorLine,
                                  onChanged: (_) => setState(() {}),
                                  onCursorMoved: (pos) => setState(() { _cursorLine = pos.$1; _cursorCol = pos.$2; }),
                                  onBlameUpdated: (blame) => setState(() => _currentBlame = blame),
                                  onSplitVertical: () => setState(() {
                                    _splitDir = SplitDirection.vertical;
                                    _secondaryFileIdx = (_activeFileIdx + 1) % _openFiles.length;
                                  }),
                                  onSplitHorizontal: () => setState(() {
                                    _splitDir = SplitDirection.horizontal;
                                    _secondaryFileIdx = (_activeFileIdx + 1) % _openFiles.length;
                                  }),
                                  onCloseSecondary: () => setState(() {
                                    _splitDir = SplitDirection.none;
                                    _secondaryFileIdx = -1;
                                  }),
                                ),
                        ),
                        // Bottom panel
                        if (_showBottom)
                          SizedBox(
                            height: _bottomHeight,
                            child: Column(children: [
                              // Bottom resize handle
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onVerticalDragUpdate: (d) => setState(() => _bottomHeight = (_bottomHeight - d.delta.dy).clamp(100, 600)),
                                child: Container(height: 4, color: SwarmColors.border, child: const Center(child: _ResizeDots())),
                              ),
                              Expanded(
                                child: BottomPanel(
                                  diagnostics: _diagnostics,
                                  outputLines: _outputLines,
                                  workspacePath: _workspacePath,
                                  height: _bottomHeight,
                                  onClose: () => setState(() => _showBottom = false),
                                ),
                              ),
                            ]),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Status Bar ────────────────────────────────────
            _StatusBar(
              workspacePath: _workspacePath,
              activeFile: _activeFile,
              cursorLine: _cursorLine,
              cursorCol: _cursorCol,
              errorCount: _diagnostics.where((d) => d.severity == DiagnosticSeverity.error).length,
              warnCount: _diagnostics.where((d) => d.severity == DiagnosticSeverity.warning).length,
              gitBranch: _gitBranch,
              currentBlame: _currentBlame,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Menu Bar ────────────────────────────────────────────────────────────────
class _MenuBar extends StatelessWidget {
  final String? workspacePath;
  final VoidCallback onOpenFolder, onToggleSide, onToggleBottom, onShowShortcuts;
  final VoidCallback? onSave;

  const _MenuBar({this.workspacePath, required this.onOpenFolder, required this.onToggleSide, required this.onToggleBottom, required this.onShowShortcuts, this.onSave});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: const BoxDecoration(
        color: SwarmColors.bgSurface,
        border: Border(bottom: BorderSide(color: SwarmColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        const Icon(Icons.code_rounded, size: 14, color: SwarmColors.accent),
        const SizedBox(width: 6),
        Text('I30LTZ IDE', style: SwarmTextStyles.labelSmall.copyWith(color: SwarmColors.accent, fontWeight: FontWeight.w800, letterSpacing: 1.5, fontSize: 10)),
        if (workspacePath != null) ...[
          const SizedBox(width: 8),
          Text('— ${workspacePath!.split('/').last}', style: const TextStyle(fontSize: 11, color: SwarmColors.textMuted, fontFamily: 'monospace')),
        ],
        const Spacer(),
        // ── Hot Reload & Debug Quick Actions ───────────
        HotReloadToolbarButton(projectPath: workspacePath),
        const SizedBox(width: 8),
        _MenuBtn('File', [
          _MenuItem('Open Folder…', Icons.folder_open, onOpenFolder),
          if (onSave != null) _MenuItem('Save  Ctrl+S', Icons.save, onSave!),
        ]),
        _MenuBtn('Run', [
          _MenuItem('Hot Reload  Ctrl+R', Icons.bolt_rounded, () => HotReloadService.instance.hotReload(projectPath: workspacePath)),
          _MenuItem('Hot Restart  Ctrl+Shift+R', Icons.restart_alt_rounded, () => HotReloadService.instance.hotRestart(projectPath: workspacePath)),
        ]),
        _MenuBtn('View', [
          _MenuItem('Toggle Sidebar  Ctrl+B', Icons.view_sidebar, onToggleSide),
          _MenuItem('Toggle Terminal  Ctrl+J', Icons.terminal, onToggleBottom),
          _MenuItem('Keyboard Shortcuts  Ctrl+?', Icons.keyboard_rounded, onShowShortcuts),
        ]),
      ]),
    );
  }
}

class _MenuItem {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _MenuItem(this.label, this.icon, this.onTap);
}

class _MenuBtn extends StatelessWidget {
  final String label;
  final List<_MenuItem> items;
  const _MenuBtn(this.label, this.items);

  @override
  Widget build(BuildContext context) => PopupMenuButton<_MenuItem>(
        tooltip: '',
        color: SwarmColors.bgElevated,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: const BorderSide(color: SwarmColors.border)),
        offset: const Offset(0, 28),
        itemBuilder: (_) => items
            .map((item) => PopupMenuItem<_MenuItem>(
                  value: item,
                  height: 32,
                  child: Row(children: [
                    Icon(item.icon, size: 13, color: SwarmColors.textMuted),
                    const SizedBox(width: 8),
                    Text(item.label, style: const TextStyle(fontSize: 12, color: SwarmColors.textSecondary)),
                  ]),
                ))
            .toList(),
        onSelected: (item) => item.onTap(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(label, style: const TextStyle(fontSize: 12, color: SwarmColors.textSecondary)),
        ),
      );
}

// ─── Activity Bar ────────────────────────────────────────────────────────────
class _ActivityBar extends StatelessWidget {
  final _SidePanel active;
  final ValueChanged<_SidePanel> onChange;

  const _ActivityBar({required this.active, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      decoration: const BoxDecoration(
        color: SwarmColors.bgSurface,
        border: Border(right: BorderSide(color: SwarmColors.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 4),
          _ActivityIcon(Icons.folder_open_rounded, 'Explorer (Ctrl+Shift+E)', _SidePanel.explorer, active, SwarmColors.agentCyan, onChange),
          _ActivityIcon(Icons.search_rounded, 'Search (Ctrl+P)', _SidePanel.search, active, SwarmColors.agentAmber, onChange),
          _ActivityIcon(Icons.call_split_rounded, 'Git (Ctrl+Shift+G)', _SidePanel.git, active, SwarmColors.agentOrange, onChange),
          _ActivityIcon(Icons.folder_special_rounded, 'Device Files', _SidePanel.deviceFiles, active, const Color(0xFF3DDC84), onChange),
          _ActivityIcon(Icons.play_circle_outline_rounded, 'Task Runner', _SidePanel.tasks, active, SwarmColors.agentAmber, onChange),
          _ActivityIcon(Icons.extension_rounded, 'Extensions', _SidePanel.extensions, active, SwarmColors.agentPurple, onChange),
          _ActivityIcon(Icons.psychology_rounded, 'Ollama Local Models', _SidePanel.ollama, active, const Color(0xFF78C28A), onChange),
          const Spacer(),
          _ActivityIcon(Icons.settings_rounded, 'Settings', _SidePanel.settings, active, SwarmColors.textMuted, onChange),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _ActivityIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final _SidePanel panel, active;
  final Color color;
  final ValueChanged<_SidePanel> onChange;

  const _ActivityIcon(this.icon, this.tooltip, this.panel, this.active, this.color, this.onChange);

  @override
  Widget build(BuildContext context) {
    final isActive = panel == active;
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: InkWell(
        onTap: () => onChange(panel),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: isActive ? color : Colors.transparent, width: 2)),
          ),
          child: Icon(icon, size: 20, color: isActive ? color : SwarmColors.textDisabled),
        ),
      ),
    );
  }
}

// ─── Side Panel Container ────────────────────────────────────────────────────
class _SidePanelContainer extends StatelessWidget {
  final double width;
  final _SidePanel panel;
  final String? workspacePath, activeFilePath;
  final ValueChanged<String> onFileOpen;
  final VoidCallback onOpenFolder;
  final ValueChanged<(String, int)> onResultTap;

  const _SidePanelContainer({
    required this.width,
    required this.panel,
    this.workspacePath,
    this.activeFilePath,
    required this.onFileOpen,
    required this.onOpenFolder,
    required this.onResultTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        decoration: const BoxDecoration(
          color: SwarmColors.bgSurface,
          border: Border(right: BorderSide(color: SwarmColors.border)),
        ),
        child: switch (panel) {
          _SidePanel.explorer => FileExplorerPanel(
              rootPath: workspacePath,
              onFileOpen: onFileOpen,
              activeFilePath: activeFilePath,
              onOpenFolder: onOpenFolder,
            ),
          _SidePanel.search => SearchPanel(
              rootPath: workspacePath,
              onResultTap: onResultTap,
            ),
          _SidePanel.git => GitPanel(workspacePath: workspacePath),
          _SidePanel.deviceFiles => const DeviceExplorerPanel(),
          _SidePanel.tasks => TaskRunnerPanel(projectPath: workspacePath),
          _SidePanel.extensions => const ExtensionsPanel(),
          _SidePanel.ollama => const OllamaPanel(),
          _SidePanel.settings => const _SettingsContainer(),
        },
      ),
    );
  }
}

// ─── Tab Strip ───────────────────────────────────────────────────────────────
class _TabStrip extends StatelessWidget {
  final List<OpenFile> files;
  final int activeIdx;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;

  const _TabStrip({required this.files, required this.activeIdx, required this.onSelect, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: const BoxDecoration(
        color: SwarmColors.bgSurface,
        border: Border(bottom: BorderSide(color: SwarmColors.border)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: files.length,
        itemBuilder: (_, i) => _FileTab(
          file: files[i],
          isActive: i == activeIdx,
          onSelect: () => onSelect(i),
          onClose: () => onClose(i),
        ),
      ),
    );
  }
}

class _FileTab extends StatefulWidget {
  final OpenFile file;
  final bool isActive;
  final VoidCallback onSelect, onClose;

  const _FileTab({required this.file, required this.isActive, required this.onSelect, required this.onClose});

  @override
  State<_FileTab> createState() => _FileTabState();
}

class _FileTabState extends State<_FileTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          constraints: const BoxConstraints(maxWidth: 200, minWidth: 80),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.isActive ? SwarmColors.bg : SwarmColors.bgSurface,
            border: Border(
              bottom: BorderSide(color: widget.isActive ? SwarmColors.accent : Colors.transparent, width: 1.5),
              right: const BorderSide(color: SwarmColors.border, width: 0.5),
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.file.isDirty)
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: SwarmColors.accent, shape: BoxShape.circle))
            else
              const SizedBox(width: 6),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                widget.file.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: widget.isActive ? SwarmColors.textPrimary : SwarmColors.textMuted,
                  fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (_hovered || widget.file.isDirty)
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(3),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 12, color: SwarmColors.textMuted),
                ),
              )
            else
              const SizedBox(width: 16),
          ]),
        ),
      ),
    );
  }
}

// ─── Welcome Screen ──────────────────────────────────────────────────────────
class _WelcomeScreen extends StatelessWidget {
  final String? workspacePath;
  final VoidCallback onOpenFolder;
  final List<String> recentFiles;
  final ValueChanged<String> onOpenFile;

  const _WelcomeScreen({this.workspacePath, required this.onOpenFolder, required this.recentFiles, required this.onOpenFile});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.code_rounded, size: 32, color: SwarmColors.accent),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('I30LTZ IDE', style: SwarmTextStyles.h2.copyWith(color: SwarmColors.accent, letterSpacing: 2, fontSize: 18)),
                Text('Recovery OS development environment', style: SwarmTextStyles.labelSmall.copyWith(color: SwarmColors.textMuted, fontSize: 10)),
              ]),
            ]),
            const SizedBox(height: 32),
            if (workspacePath == null) ...[
              Text('Start', style: SwarmTextStyles.bodySmall.copyWith(color: SwarmColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 10),
              _WelcomeItem(Icons.folder_open_rounded, 'Open Folder…', 'Ctrl+K Ctrl+O', SwarmColors.agentCyan, onOpenFolder),
            ],
            const SizedBox(height: 16),
            _ShortcutsCard(),
          ],
        ),
      ),
    );
  }
}

class _WelcomeItem extends StatelessWidget {
  final IconData icon;
  final String label, shortcut;
  final Color color;
  final VoidCallback onTap;

  const _WelcomeItem(this.icon, this.label, this.shortcut, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 13, color: color)),
            const Spacer(),
            Text(shortcut, style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: SwarmColors.textDisabled)),
          ]),
        ),
      );
}

class _ShortcutsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const shortcuts = [
      ('Ctrl+S', 'Save file'),
      ('Ctrl+B', 'Toggle sidebar'),
      ('Ctrl+J', 'Toggle terminal'),
      ('Ctrl+W', 'Close tab'),
      ('Ctrl+P', 'Quick open / search'),
      ('Ctrl+Shift+G', 'Open Git panel'),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: SwarmColors.bgElevated, borderRadius: BorderRadius.circular(8), border: Border.all(color: SwarmColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Keyboard Shortcuts', style: SwarmTextStyles.labelSmall.copyWith(color: SwarmColors.textMuted, fontSize: 10, letterSpacing: 1)),
          const SizedBox(height: 8),
          ...shortcuts.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: SwarmColors.bgPanel, borderRadius: BorderRadius.circular(3), border: Border.all(color: SwarmColors.border)),
                    child: Text(s.$1, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: SwarmColors.textSecondary)),
                  ),
                  const SizedBox(width: 10),
                  Text(s.$2, style: const TextStyle(fontSize: 12, color: SwarmColors.textMuted)),
                ]),
              )),
        ],
      ),
    );
  }
}

// ─── Resize Handle ───────────────────────────────────────────────────────────
class _ResizeHandle extends StatelessWidget {
  final ValueChanged<double> onDrag;
  const _ResizeHandle({required this.onDrag});

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: Container(width: 4, color: SwarmColors.border),
        ),
      );
}

class _ResizeDots extends StatelessWidget {
  const _ResizeDots();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (_) => Container(
          width: 3, height: 3, margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: const BoxDecoration(color: SwarmColors.textDisabled, shape: BoxShape.circle),
        )),
      );
}

// ─── Settings Container (tabbed) ─────────────────────────────────────────────
class _SettingsContainer extends StatefulWidget {
  const _SettingsContainer();

  @override
  State<_SettingsContainer> createState() => _SettingsContainerState();
}

class _SettingsContainerState extends State<_SettingsContainer> with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
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
            tabs: const [
              Tab(text: 'EDITOR', height: 32),
              Tab(text: 'PROFILES', height: 32),
              Tab(text: 'SNIPPETS', height: 32),
              Tab(text: 'KEYBINDINGS', height: 32),
              Tab(text: 'ACCESSIBILITY', height: 32),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: const [
              _SettingsPane(),
              ProfileManagerPanel(),
              SnippetsPanel(),
              KeybindingsPanel(),
              AccessibilityPanel(),
            ],
          ),
        ),
      ]);
}

// ─── Settings Pane ───────────────────────────────────────────────────────────
class _SettingsPane extends StatelessWidget {
  const _SettingsPane();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _SectionHeader('Appearance'),
          const _SettingRow('Theme', 'Cyber Dark (default)'),
          const _SettingRow('Font Size', '13.5px'),
          const _SettingRow('Font Family', 'monospace'),
          const _SettingRow('Line Height', '20px'),
          const SizedBox(height: 16),
          const _SectionHeader('Editor'),
          const _SettingRow('Word Wrap', 'Off'),
          const _SettingRow('Tab Size', '2 spaces'),
          const _SettingRow('Auto Save', 'Off'),
          const _SettingRow('Format on Save', 'Off'),
          const SizedBox(height: 16),
          const _SectionHeader('Terminal'),
          _SettingRow('Shell', Platform.environment['SHELL'] ?? '/bin/bash'),
          const _SettingRow('Font Size', '12px'),
          const SizedBox(height: 16),
          const _SectionHeader('Android SDK'),
          _SettingRow('ANDROID_HOME', Platform.environment['ANDROID_HOME'] ?? 'Not set'),
          _SettingRow('FLUTTER_ROOT', Platform.environment['FLUTTER_ROOT'] ?? 'Not set'),
        ]),
      );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(title, style: const TextStyle(fontSize: 10, color: SwarmColors.textMuted, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
      );
}

class _SettingRow extends StatelessWidget {
  final String label, value;
  const _SettingRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 12, color: SwarmColors.textSecondary))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: SwarmColors.textMuted))),
        ]),
      );
}

// ─── Keyboard Shortcut Overlay ───────────────────────────────────────────────
class _ShortcutOverlay extends StatelessWidget {
  const _ShortcutOverlay();

  static const _sections = [
    ('File', [
      ('Ctrl+S',         'Save active file'),
      ('Ctrl+W',         'Close active tab'),
      ('Ctrl+K Ctrl+O',  'Open folder'),
    ]),
    ('Run & Debug', [
      ('Ctrl+R',         'Hot Reload application changes'),
      ('Ctrl+Shift+R',   'Hot Restart application session'),
    ]),
    ('View', [
      ('Ctrl+B',         'Toggle sidebar'),
      ('Ctrl+J',         'Toggle terminal panel'),
      ('Ctrl+/',         'Show this shortcut overlay'),
    ]),
    ('Navigation', [
      ('Ctrl+P',         'Quick open / search panel'),
      ('Ctrl+Shift+G',   'Open Git panel'),
      ('F12',            'Go to definition'),
    ]),
    ('Editor', [
      ('Tab',            'Insert 2 spaces'),
      ('↑ / ↓',          'Navigate completion list'),
      ('Enter / Tab',    'Accept completion'),
      ('Escape',         'Dismiss completion popup'),
    ]),
    ('Split Editor', [
      ('Split Right btn',  'Split editor vertically'),
      ('Split Down btn',   'Split editor horizontally'),
      ('Close btn',        'Close secondary pane'),
    ]),
    ('Git', [
      ('Stage All',      'git add -A'),
      ('Commit',         'git commit with message'),
      ('Pull / Push',    'git pull / push'),
    ]),
    ('Android', [
      ('Build APK',      'gradle assembleDebug/Release or flutter build apk'),
      ('Build AAB',      'gradle bundleRelease or flutter build appbundle'),
      ('Logcat',         'Stream adb logcat with filters'),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(32),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 600),
        decoration: BoxDecoration(
          color: SwarmColors.bgSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SwarmColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 24, spreadRadius: 2)],
        ),
        child: Column(children: [
          // Header
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: SwarmColors.bgElevated,
              borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
              border: Border(bottom: BorderSide(color: SwarmColors.border)),
            ),
            child: Row(children: [
              const Icon(Icons.keyboard_rounded, size: 16, color: SwarmColors.accent),
              const SizedBox(width: 10),
              const Text('Keyboard Shortcuts', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: SwarmColors.textPrimary, letterSpacing: 0.5)),
              const Spacer(),
              InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(4),
                child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.close, size: 16, color: SwarmColors.textMuted)),
              ),
            ]),
          ),
          // Grid of sections
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: _sections.map((section) => SizedBox(
                  width: 340,
                  child: _ShortcutSection(title: section.$1, rows: section.$2),
                )).toList(),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ShortcutSection extends StatelessWidget {
  final String title;
  final List<(String, String)> rows;
  const _ShortcutSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SwarmColors.bgElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: SwarmColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: SwarmColors.accent, letterSpacing: 1)),
          const SizedBox(height: 8),
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: SwarmColors.bgPanel,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: SwarmColors.border),
                    ),
                    child: Text(r.$1, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: SwarmColors.textSecondary)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(r.$2, style: const TextStyle(fontSize: 12, color: SwarmColors.textMuted))),
                ]),
              )),
        ]),
      );
}

// ─── Status Bar ──────────────────────────────────────────────────────────────
class _StatusBar extends StatelessWidget {
  final String? workspacePath;
  final OpenFile? activeFile;
  final int cursorLine, cursorCol, errorCount, warnCount;
  final String? gitBranch;
  final GitBlameInfo? currentBlame;

  const _StatusBar({
    this.workspacePath,
    this.activeFile,
    required this.cursorLine,
    required this.cursorCol,
    required this.errorCount,
    required this.warnCount,
    this.gitBranch,
    this.currentBlame,
  });

  @override
  Widget build(BuildContext context) {
    final stateService = WorkspaceStateService.instance;
    final isOnline = stateService.isOnline;

    return Container(
      height: 22,
      decoration: const BoxDecoration(
        color: Color(0xFF0A0816),
        border: Border(top: BorderSide(color: SwarmColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(children: [
        // Workspace / Git branch
        const Icon(Icons.code_rounded, size: 12, color: SwarmColors.accent),
        const SizedBox(width: 5),
        Text(workspacePath?.split('/').last ?? 'No folder', style: const TextStyle(fontSize: 10.5, color: SwarmColors.accent, fontWeight: FontWeight.w600)),
        if (gitBranch != null) ...[
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.call_split_rounded, size: 11, color: SwarmColors.agentCyan),
              const SizedBox(width: 4),
              Text(gitBranch!, style: const TextStyle(fontSize: 10.5, color: SwarmColors.agentCyan, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
        const SizedBox(width: 6),
        // Hot Reload Quick Button
        const HotReloadToolbarButton(compact: true),
        const SizedBox(width: 14),
        if (errorCount > 0) ...[
          const Icon(Icons.error_outline, size: 11, color: SwarmColors.agentRose),
          const SizedBox(width: 3),
          Text('$errorCount', style: const TextStyle(fontSize: 10, color: SwarmColors.agentRose)),
          const SizedBox(width: 8),
        ],
        if (warnCount > 0) ...[
          const Icon(Icons.warning_amber_rounded, size: 11, color: SwarmColors.agentAmber),
          const SizedBox(width: 3),
          Text('$warnCount', style: const TextStyle(fontSize: 10, color: SwarmColors.agentAmber)),
        ],
        if (currentBlame != null) ...[
          const SizedBox(width: 10),
          const Icon(Icons.commit_rounded, size: 11, color: SwarmColors.textMuted),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              currentBlame!.inlineAnnotation,
              style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: SwarmColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        const Spacer(),
        // Offline / Local-First Status Pill
        InkWell(
          onTap: () => stateService.toggleOfflineMode(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: isOnline ? SwarmColors.agentEmerald.withAlpha(20) : SwarmColors.agentAmber.withAlpha(25),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: isOnline ? SwarmColors.agentEmerald.withAlpha(80) : SwarmColors.agentAmber.withAlpha(90)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded, size: 10, color: isOnline ? SwarmColors.agentEmerald : SwarmColors.agentAmber),
                const SizedBox(width: 4),
                Text(
                  isOnline ? 'ONLINE' : 'LOCAL-FIRST',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isOnline ? SwarmColors.agentEmerald : SwarmColors.agentAmber),
                ),
              ],
            ),
          ),
        ),
        if (activeFile != null) ...[
          Text(activeFile!.language?.toUpperCase() ?? 'PLAIN', style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: SwarmColors.textMuted)),
          const SizedBox(width: 14),
          Text('Ln $cursorLine, Col $cursorCol', style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: SwarmColors.textMuted)),
          const SizedBox(width: 14),
          const Text('UTF-8', style: TextStyle(fontSize: 10, color: SwarmColors.textMuted)),
          const SizedBox(width: 14),
          const Text('LF', style: TextStyle(fontSize: 10, color: SwarmColors.textMuted)),
          const SizedBox(width: 14),
          Text(activeFile!.isDirty ? '● Unsaved' : '✓ Saved', style: TextStyle(fontSize: 10, color: activeFile!.isDirty ? SwarmColors.agentAmber : SwarmColors.agentEmerald)),
        ],
      ]),
    );
  }
}
