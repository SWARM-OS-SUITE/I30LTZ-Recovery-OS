import '../platform/platform.dart';
import 'package:flutter/material.dart';
import '../theme/swarm_colors.dart';
import '../widgets/swarm_terminal.dart';
import 'editor_model.dart';

enum BottomTab { terminal, problems, output, logcat }

class BottomPanel extends StatefulWidget {
  final List<DiagnosticItem> diagnostics;
  final List<String> outputLines;
  final String? workspacePath;
  final double height;
  final VoidCallback? onClose;

  const BottomPanel({
    super.key,
    this.diagnostics = const [],
    this.outputLines = const [],
    this.workspacePath,
    this.height = 240,
    this.onClose,
  });

  @override
  State<BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends State<BottomPanel> {
  BottomTab _activeTab = BottomTab.terminal;

  int get _errorCount => widget.diagnostics.where((d) => d.severity == DiagnosticSeverity.error).length;
  int get _warnCount => widget.diagnostics.where((d) => d.severity == DiagnosticSeverity.warning).length;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: SwarmColors.bgSurface,
        border: Border(top: BorderSide(color: SwarmColors.border, width: 1)),
      ),
      child: Column(
        children: [
          // Tab bar
          _TabBar(
            active: _activeTab,
            errorCount: _errorCount,
            warnCount: _warnCount,
            onTab: (t) => setState(() => _activeTab = t),
            onClose: widget.onClose,
          ),
          // Content
          Expanded(child: _content()),
        ],
      ),
    );
  }

  Widget _content() => switch (_activeTab) {
        BottomTab.terminal  => SwarmTerminal(startDirectory: widget.workspacePath ?? Platform.environment['HOME'] ?? '/'),
        BottomTab.problems  => _ProblemsPane(diagnostics: widget.diagnostics),
        BottomTab.output    => _OutputPane(lines: widget.outputLines),
        BottomTab.logcat    => _LogcatHint(),
      };
}

class _TabBar extends StatelessWidget {
  final BottomTab active;
  final int errorCount, warnCount;
  final ValueChanged<BottomTab> onTab;
  final VoidCallback? onClose;

  const _TabBar({required this.active, required this.errorCount, required this.warnCount, required this.onTab, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: const BoxDecoration(
        color: SwarmColors.bgSurface,
        border: Border(bottom: BorderSide(color: SwarmColors.border)),
      ),
      child: Row(
        children: [
          _Tab('TERMINAL', BottomTab.terminal, active, Icons.terminal, SwarmColors.agentCyan, null, onTab),
          _Tab('PROBLEMS', BottomTab.problems, active, Icons.error_outline, SwarmColors.agentRose, errorCount + warnCount, onTab),
          _Tab('OUTPUT', BottomTab.output, active, Icons.list_alt_rounded, SwarmColors.agentAmber, null, onTab),
          _Tab('LOGCAT', BottomTab.logcat, active, Icons.phone_android, SwarmColors.agentEmerald, null, onTab),
          const Spacer(),
          if (onClose != null)
            Tooltip(
              message: 'Hide Panel',
              child: InkWell(
                onTap: onClose,
                child: const Padding(padding: EdgeInsets.all(7), child: Icon(Icons.keyboard_arrow_down, size: 14, color: SwarmColors.textMuted)),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final BottomTab tab, active;
  final IconData icon;
  final Color color;
  final int? badge;
  final ValueChanged<BottomTab> onTab;

  const _Tab(this.label, this.tab, this.active, this.icon, this.color, this.badge, this.onTab);

  @override
  Widget build(BuildContext context) {
    final isActive = tab == active;
    return InkWell(
      onTap: () => onTab(tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: isActive ? color : Colors.transparent, width: 2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: isActive ? color : SwarmColors.textMuted),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.6, color: isActive ? color : SwarmColors.textMuted)),
          if (badge != null && badge! > 0) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
              child: Text('$badge', style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold)),
            ),
          ],
        ]),
      ),
    );
  }
}

// ─── Problems Pane ─────────────────────────────────────────────────────────
class _ProblemsPane extends StatelessWidget {
  final List<DiagnosticItem> diagnostics;
  const _ProblemsPane({required this.diagnostics});

  @override
  Widget build(BuildContext context) {
    if (diagnostics.isEmpty) {
      return const Center(child: Text('No problems detected', style: TextStyle(color: SwarmColors.textMuted, fontSize: 12)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: diagnostics.length,
      itemBuilder: (_, i) => _ProblemRow(item: diagnostics[i]),
    );
  }
}

class _ProblemRow extends StatelessWidget {
  final DiagnosticItem item;
  const _ProblemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (item.severity) {
      DiagnosticSeverity.error   => (Icons.error_rounded, SwarmColors.agentRose),
      DiagnosticSeverity.warning => (Icons.warning_amber_rounded, SwarmColors.agentAmber),
      DiagnosticSeverity.info    => (Icons.info_outline_rounded, SwarmColors.agentSky),
      DiagnosticSeverity.hint    => (Icons.lightbulb_outline_rounded, SwarmColors.agentEmerald),
    };

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(item.message, style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: SwarmColors.textSecondary), overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Text('${item.file.split('/').last}:${item.line}:${item.col}', style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: SwarmColors.textMuted)),
      ]),
    );
  }
}

// ─── Output Pane ───────────────────────────────────────────────────────────
class _OutputPane extends StatefulWidget {
  final List<String> lines;
  const _OutputPane({required this.lines});

  @override
  State<_OutputPane> createState() => _OutputPaneState();
}

class _OutputPaneState extends State<_OutputPane> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_OutputPane old) {
    super.didUpdateWidget(old);
    if (widget.lines.length != old.lines.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lines.isEmpty) {
      return const Center(child: Text('No output', style: TextStyle(color: SwarmColors.textMuted, fontSize: 12)));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(8),
      itemCount: widget.lines.length,
      itemBuilder: (_, i) {
        final line = widget.lines[i];
        Color c = SwarmColors.textSecondary;
        if (line.startsWith('ERROR') || line.startsWith('✗')) c = SwarmColors.agentRose;
        if (line.startsWith('WARNING')) c = SwarmColors.agentAmber;
        if (line.startsWith('✓') || line.startsWith('SUCCESS')) c = SwarmColors.agentEmerald;
        return Text(line, style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: c));
      },
    );
  }
}

// ─── Logcat hint (directs user to Android panel) ───────────────────────────
class _LogcatHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.phone_android, size: 32, color: SwarmColors.textDisabled),
          SizedBox(height: 8),
          Text('Open the Android panel to start Logcat', style: TextStyle(color: SwarmColors.textMuted, fontSize: 12)),
          SizedBox(height: 4),
          Text('(Activity Bar → Android icon)', style: TextStyle(color: SwarmColors.textDisabled, fontSize: 11)),
        ]),
      );
}
