// ═══════════════════════════════════════════════════════════════
// I30LTZ RECOVERY OS — I30LTZ IDE
// Forked from the SWARM OS Apex workstation (2026-10-12; source: /mnt/Lucy/30-source/frontend, swarm commit 0e27a2a).
// Professional IDE: file tree, syntax highlight, git, terminal, extensions; AI pair programmer = Dr. I30LTZ "MAD AI"
// (local Ollama only, every suggestion needs a click).
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/swarm_colors.dart';
import '../theme/swarm_text_styles.dart';
import '../theme/lucide_compat.dart';
import '../coder/coder_page.dart';
import '../coder/panels/profile_manager_panel.dart';
import '../coder/panels/device_explorer_panel.dart';
import '../coder/panels/task_runner_panel.dart';
import '../coder/panels/extensions_panel.dart';
import '../coder/panels/ollama_panel.dart';
import '../services/workspace_state_service.dart';
import '../widgets/swarm_terminal.dart';
import 'mad_ai_panel.dart';

enum IdeView { explorer, search, git, deviceFiles, tasks, extensions, ollama, settings }

class I30ltzIde extends ConsumerStatefulWidget {
  const I30ltzIde({super.key});

  @override
  ConsumerState<I30ltzIde> createState() => _I30ltzIdeState();
}

class _I30ltzIdeState extends ConsumerState<I30ltzIde> {
  IdeView _activeView = IdeView.explorer;
  bool _aiPanelOpen = true;
  bool _bottomPanelOpen = false; // the editor already has its own terminal tab
  double _sidebarWidth = 280.0;
  double _aiPanelWidth = 320.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        return Container(
          color: SwarmColors.bg,
          child: Column(
            children: [
              // Top Toolbar / Menu
              _buildMenuBar(isMobile),
              
              // Main content area
              Expanded(
                child: Row(
                  children: [
                    // Activity Bar (Icons on the left)
                    if (!isMobile) _buildActivityBar(),

                    // Sidebar Content
                    if (!isMobile && _activeView != IdeView.explorer)
                      _buildSidebar(),

                    // Center Editor Area (CoderPage)
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: isMobile && _activeView != IdeView.explorer
                                ? _buildSidebar()
                                : _buildEditorArea(),
                          ),
                          if (_bottomPanelOpen) _buildBottomPanel(),
                        ],
                      ),
                    ),

                    // Right AI Panel
                    if (!isMobile && _aiPanelOpen) ...[
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeLeftRight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragUpdate: (details) {
                            setState(() {
                              _aiPanelWidth -= details.delta.dx;
                              if (_aiPanelWidth < 200) _aiPanelWidth = 200;
                              if (_aiPanelWidth > 800) _aiPanelWidth = 800;
                            });
                          },
                          child: Container(width: 4, color: SwarmColors.border),
                        ),
                      ),
                      SizedBox(
                        width: _aiPanelWidth,
                        child: const _MadAiPanelFrame(),
                      ),
                    ],
                  ],
                ),
              ),
              
              // Mobile Bottom Navigation
              if (isMobile) _buildMobileNavBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuBar(bool isMobile) {
    return Container(
      height: 36,
      decoration: const BoxDecoration(
        color: SwarmColors.bgElevated,
        border: Border(bottom: BorderSide(color: SwarmColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Exit button (closes the IDE window)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => SystemNavigator.pop(),
              borderRadius: BorderRadius.circular(5),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: SwarmColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: SwarmColors.accent.withValues(alpha: 0.4), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.power_settings_new_rounded, size: 13, color: SwarmColors.accent),
                    const SizedBox(width: 4),
                    Text(
                      'EXIT',
                      style: SwarmTextStyles.codeSmall.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: SwarmColors.accent,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.build_circle_rounded, size: 16, color: SwarmColors.accent),
          const SizedBox(width: 8),
          Text(
            'I30LTZ IDE',
            style: SwarmTextStyles.label.copyWith(
              color: SwarmColors.textPrimary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const Spacer(),
          if (!isMobile) ...[
            _IconBtn(
              icon: LucideIcons.terminal,
              active: _bottomPanelOpen,
              onTap: () => setState(() => _bottomPanelOpen = !_bottomPanelOpen),
              tooltip: 'Toggle Terminal',
            ),
            const SizedBox(width: 8),
            _IconBtn(
              icon: LucideIcons.bot,
              active: _aiPanelOpen,
              onTap: () => setState(() => _aiPanelOpen = !_aiPanelOpen),
              tooltip: 'Toggle MAD AI (Dr. I30LTZ)',
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildActivityBar() {
    return Container(
      width: 48,
      decoration: const BoxDecoration(
        color: SwarmColors.bgElevated,
        border: Border(right: BorderSide(color: SwarmColors.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _ActivityIcon(
            icon: LucideIcons.files,
            view: IdeView.explorer,
            active: _activeView == IdeView.explorer,
            onTap: () => setState(() => _activeView = IdeView.explorer),
          ),
          _ActivityIcon(
            icon: LucideIcons.search,
            view: IdeView.search,
            active: _activeView == IdeView.search,
            onTap: () => setState(() => _activeView = IdeView.search),
          ),
          _ActivityIcon(
            icon: LucideIcons.gitBranch,
            view: IdeView.git,
            active: _activeView == IdeView.git,
            onTap: () => setState(() => _activeView = IdeView.git),
          ),
          _ActivityIcon(
            icon: LucideIcons.hardDrive,
            view: IdeView.deviceFiles,
            active: _activeView == IdeView.deviceFiles,
            onTap: () => setState(() => _activeView = IdeView.deviceFiles),
          ),
          _ActivityIcon(
            icon: LucideIcons.playCircle,
            view: IdeView.tasks,
            active: _activeView == IdeView.tasks,
            onTap: () => setState(() => _activeView = IdeView.tasks),
          ),
          _ActivityIcon(
            icon: LucideIcons.puzzle,
            view: IdeView.extensions,
            active: _activeView == IdeView.extensions,
            onTap: () => setState(() => _activeView = IdeView.extensions),
          ),
          _ActivityIcon(
            icon: LucideIcons.cpu,
            view: IdeView.ollama,
            active: _activeView == IdeView.ollama,
            onTap: () => setState(() => _activeView = IdeView.ollama),
          ),
          _ActivityIcon(
            icon: LucideIcons.settings,
            view: IdeView.settings,
            active: _activeView == IdeView.settings,
            onTap: () => setState(() => _activeView = IdeView.settings),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileNavBar() {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: SwarmColors.bgElevated,
        border: Border(top: BorderSide(color: SwarmColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ActivityIcon(icon: LucideIcons.code2, view: IdeView.explorer, active: _activeView == IdeView.explorer, onTap: () => setState(() => _activeView = IdeView.explorer)),
          _ActivityIcon(icon: LucideIcons.files, view: IdeView.explorer, active: _activeView == IdeView.explorer, onTap: () => setState(() => _activeView = IdeView.explorer)),
          _ActivityIcon(icon: LucideIcons.search, view: IdeView.search, active: _activeView == IdeView.search, onTap: () => setState(() => _activeView = IdeView.search)),
          _ActivityIcon(icon: LucideIcons.terminal, view: IdeView.tasks, active: _bottomPanelOpen, onTap: () => setState(() => _bottomPanelOpen = !_bottomPanelOpen)),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    // Real panels need the active workspace path — same persisted workspace
    // CoderPage itself loads (WorkspaceStateService), so both surfaces agree.
    final workspace = WorkspaceStateService.instance.snapshot.workspacePath;
    return Row(
      children: [
        Container(
          width: _sidebarWidth,
          decoration: const BoxDecoration(
            color: SwarmColors.bgSurface,
          ),
          child: switch (_activeView) {
            IdeView.explorer => const _CoderPageWrapper(showSidebar: true),
            IdeView.search => const _CoderPageWrapper(showSidebar: true, initialPanel: 'search'),
            IdeView.git => const _CoderPageWrapper(showSidebar: true, initialPanel: 'git'),
            IdeView.deviceFiles => const DeviceExplorerPanel(),
            IdeView.tasks => TaskRunnerPanel(projectPath: workspace),
            IdeView.extensions => const ExtensionsPanel(),
            IdeView.ollama => const OllamaPanel(),
            IdeView.settings => const ProfileManagerPanel(),
          },
        ),
        MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (details) {
              setState(() {
                _sidebarWidth += details.delta.dx;
                if (_sidebarWidth < 150) _sidebarWidth = 150;
                if (_sidebarWidth > 600) _sidebarWidth = 600;
              });
            },
            child: Container(width: 4, color: SwarmColors.border),
          ),
        ),
      ],
    );
  }

  Widget _buildEditorArea() {
    return const _CoderPageWrapper(showSidebar: false);
  }

  Widget _buildBottomPanel() {
    return Container(
      height: 220,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: SwarmColors.border)),
      ),
      child: const _IdeTerminalPanel(),
    );
  }
}

// Wrapper to embed CoderPage in I30ltzIde
class _CoderPageWrapper extends StatelessWidget {
  final bool showSidebar;
  final String? initialPanel;

  const _CoderPageWrapper({this.showSidebar = false, this.initialPanel});

  @override
  Widget build(BuildContext context) {
    return CoderPage(
      key: ValueKey('coder_${showSidebar}_${initialPanel ?? 'default'}'),
    );
  }
}

// MAD AI panel frame: header + the local-Ollama chat in mad_ai_panel.dart. Nothing here talks to a SWARM server.
class _MadAiPanelFrame extends ConsumerWidget {
  const _MadAiPanelFrame();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: SwarmColors.bgSurface,
      child: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: SwarmColors.border)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.bot, size: 16, color: SwarmColors.accent),
                const SizedBox(width: 8),
                Text('MAD AI  ·  DR. I30LTZ', style: SwarmTextStyles.label.copyWith(color: SwarmColors.accent, fontSize: 11)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: () {},
                  tooltip: 'Close AI Panel',
                ),
              ],
            ),
          ),
          // Local Ollama chat (127.0.0.1:11434); suggestions are shown, never applied without a click.
          const Expanded(child: MadAiPanel()),
        ],
      ),
    );
  }
}

// Terminal Panel for Apex — the real SwarmTerminal (multi-pane, PTY-backed,
// with copy/paste context menu), not a placeholder.
class _IdeTerminalPanel extends StatelessWidget {
  const _IdeTerminalPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF2D2D2D),
              border: Border(bottom: BorderSide(color: SwarmColors.border)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.terminal, size: 14, color: SwarmColors.accent),
                const SizedBox(width: 8),
                Text('TERMINAL', style: SwarmTextStyles.codeSmall.copyWith(color: SwarmColors.accent)),
                const Spacer(),
              ],
            ),
          ),
          const Expanded(
            child: SwarmTerminal(initialPanes: 1),
          ),
        ],
      ),
    );
  }
}

// ─── Sub-Panels ─────────────────────────────────────────────────────────────
// All activity-bar views now render the REAL panels from lib/coder/panels/
// (DeviceExplorerPanel, TaskRunnerPanel, ExtensionsPanel,
// OllamaPanel) — the placeholder stubs that used to live here were deleted
// 2026-09-21. They duplicated the coder panels with every action a no-op.

// ─── Small Components ────────────────────────────────────────────────────────

class _IconBtn extends StatefulWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String tooltip;

  const _IconBtn({required this.icon, required this.active, required this.onTap, required this.tooltip});

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (v) => setState(() => _hovered = v),
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: widget.active 
                ? SwarmColors.accent.withValues(alpha: 0.15) 
                : _hovered ? SwarmColors.bgHover : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            widget.icon,
            size: 14,
            color: widget.active ? SwarmColors.accent : SwarmColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ActivityIcon extends StatefulWidget {
  final IconData icon;
  final IdeView view;
  final bool active;
  final VoidCallback onTap;

  const _ActivityIcon({required this.icon, required this.view, required this.active, required this.onTap});

  @override
  State<_ActivityIcon> createState() => _ActivityIconState();
}

class _ActivityIconState extends State<_ActivityIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: widget.onTap,
        onHover: (v) => setState(() => _hovered = v),
        borderRadius: BorderRadius.circular(8),
        focusColor: SwarmColors.accent.withValues(alpha: 0.3),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: widget.active ? SwarmColors.accent : Colors.transparent,
                width: 2,
              )
            ),
          ),
          child: Icon(
            widget.icon,
            size: 22,
            color: widget.active ? SwarmColors.textPrimary : _hovered ? SwarmColors.textSecondary : SwarmColors.textMuted,
          ),
        ),
      ),
    );
  }
}