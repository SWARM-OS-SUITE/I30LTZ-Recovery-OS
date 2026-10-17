import 'package:flutter/material.dart';
import '../theme/swarm_colors.dart';
import 'editor_model.dart';
import 'code_editor_widget.dart';

import '../services/git_lens_service.dart';

enum SplitDirection { none, vertical, horizontal }

// ─── Split Editor Layout ──────────────────────────────────────────────────────
class SplitEditor extends StatefulWidget {
  final List<OpenFile> files;
  final int primaryIdx;
  final int? secondaryIdx;
  final SplitDirection direction;
  final String? workspacePath;
  final ValueChanged<String>? onChanged;
  final ValueChanged<(int, int)>? onCursorMoved;
  final ValueChanged<GitBlameInfo?>? onBlameUpdated;
  final VoidCallback? onSplitVertical;
  final VoidCallback? onSplitHorizontal;
  final VoidCallback? onCloseSecondary;
  final int? targetLine;

  const SplitEditor({
    super.key,
    required this.files,
    required this.primaryIdx,
    this.secondaryIdx,
    this.direction = SplitDirection.none,
    this.workspacePath,
    this.onChanged,
    this.onCursorMoved,
    this.onBlameUpdated,
    this.onSplitVertical,
    this.onSplitHorizontal,
    this.onCloseSecondary,
    this.targetLine,
  });

  @override
  State<SplitEditor> createState() => _SplitEditorState();
}

class _SplitEditorState extends State<SplitEditor> {
  double _splitRatio = 0.5;
  bool _primaryFocused = true;

  OpenFile? get _primary => widget.primaryIdx >= 0 && widget.primaryIdx < widget.files.length
      ? widget.files[widget.primaryIdx]
      : null;

  OpenFile? get _secondary => widget.secondaryIdx != null &&
          widget.secondaryIdx! >= 0 &&
          widget.secondaryIdx! < widget.files.length
      ? widget.files[widget.secondaryIdx!]
      : null;

  bool get _hasSplit => _secondary != null && widget.direction != SplitDirection.none;

  @override
  Widget build(BuildContext context) {
    if (_primary == null) return _EmptyEditor();

    if (!_hasSplit) {
      return _EditorPane(file: _primary!, workspacePath: widget.workspacePath, onChanged: widget.onChanged, onCursorMoved: widget.onCursorMoved, onBlameUpdated: widget.onBlameUpdated, onSplitV: widget.onSplitVertical, onSplitH: widget.onSplitHorizontal, showSplitBtns: true, targetLine: widget.targetLine);
    }

    final isVertical = widget.direction == SplitDirection.vertical;

    Widget primary = _EditorPane(file: _primary!, workspacePath: widget.workspacePath, onChanged: widget.onChanged, onCursorMoved: widget.onCursorMoved, onBlameUpdated: widget.onBlameUpdated, isFocused: _primaryFocused, onFocus: () => setState(() => _primaryFocused = true), showSplitBtns: false, targetLine: widget.targetLine);
    Widget secondary = _EditorPane(file: _secondary!, workspacePath: widget.workspacePath, onChanged: widget.onChanged, onCursorMoved: widget.onCursorMoved, onBlameUpdated: widget.onBlameUpdated, isFocused: !_primaryFocused, onFocus: () => setState(() => _primaryFocused = false), onClose: widget.onCloseSecondary, showSplitBtns: false);

    Widget divider = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (d) {
        setState(() {
          final delta = isVertical ? d.delta.dx : d.delta.dy;
          final size = isVertical
              ? (context.findRenderObject() as RenderBox?)?.size.width ?? 800
              : (context.findRenderObject() as RenderBox?)?.size.height ?? 600;
          _splitRatio = (_splitRatio + delta / size).clamp(0.2, 0.8);
        });
      },
      child: MouseRegion(
        cursor: isVertical ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
        child: Container(
          width: isVertical ? 4 : double.infinity,
          height: isVertical ? double.infinity : 4,
          color: SwarmColors.border,
          child: Center(
            child: Container(
              width: isVertical ? 1 : 24,
              height: isVertical ? 24 : 1,
              color: SwarmColors.textDisabled,
            ),
          ),
        ),
      ),
    );

    return LayoutBuilder(builder: (context, constraints) {
      final total = isVertical ? constraints.maxWidth : constraints.maxHeight;
      final primarySize = total * _splitRatio;
      final secondarySize = total * (1 - _splitRatio) - 4;

      if (isVertical) {
        return Row(children: [
          SizedBox(width: primarySize, child: primary),
          divider,
          SizedBox(width: secondarySize, child: secondary),
        ]);
      } else {
        return Column(children: [
          SizedBox(height: primarySize, child: primary),
          divider,
          SizedBox(height: secondarySize, child: secondary),
        ]);
      }
    });
  }
}

// ─── Single Editor Pane ───────────────────────────────────────────────────────
class _EditorPane extends StatelessWidget {
  final OpenFile file;
  final String? workspacePath;
  final ValueChanged<String>? onChanged;
  final ValueChanged<(int, int)>? onCursorMoved;
  final ValueChanged<GitBlameInfo?>? onBlameUpdated;
  final bool? isFocused;
  final VoidCallback? onFocus;
  final VoidCallback? onClose;
  final VoidCallback? onSplitV;
  final VoidCallback? onSplitH;
  final bool showSplitBtns;
  final int? targetLine;

  const _EditorPane({
    required this.file,
    this.workspacePath,
    this.onChanged,
    this.onCursorMoved,
    this.onBlameUpdated,
    this.isFocused,
    this.onFocus,
    this.onClose,
    this.onSplitV,
    this.onSplitH,
    required this.showSplitBtns,
    this.targetLine,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onFocus,
      child: Column(
        children: [
          _PaneHeader(file: file, isFocused: isFocused ?? true, onClose: onClose, onSplitV: onSplitV, onSplitH: onSplitH, showSplitBtns: showSplitBtns),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: isFocused == true ? Border.all(color: SwarmColors.accent.withValues(alpha: 0.3), width: 1) : null,
              ),
              child: CodeEditorWidget(
                file: file,
                workspacePath: workspacePath,
                onChanged: onChanged,
                onCursorMoved: onCursorMoved,
                onBlameUpdated: onBlameUpdated,
                targetLine: targetLine,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaneHeader extends StatelessWidget {
  final OpenFile file;
  final bool isFocused;
  final VoidCallback? onClose, onSplitV, onSplitH;
  final bool showSplitBtns;

  const _PaneHeader({required this.file, required this.isFocused, this.onClose, this.onSplitV, this.onSplitH, required this.showSplitBtns});

  @override
  Widget build(BuildContext context) => Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: isFocused ? SwarmColors.bgElevated : SwarmColors.bgSurface,
          border: const Border(bottom: BorderSide(color: SwarmColors.border)),
        ),
        child: Row(children: [
          if (file.isDirty) Container(width: 6, height: 6, decoration: const BoxDecoration(color: SwarmColors.accent, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(file.name, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: isFocused ? SwarmColors.textPrimary : SwarmColors.textMuted, fontWeight: isFocused ? FontWeight.w600 : FontWeight.normal)),
          const Spacer(),
          if (showSplitBtns) ...[
            _HeaderBtn(Icons.vertical_split, 'Split Right', onSplitV),
            _HeaderBtn(Icons.horizontal_split, 'Split Down', onSplitH),
          ],
          if (onClose != null) _HeaderBtn(Icons.close, 'Close', onClose),
        ]),
      );
}

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _HeaderBtn(this.icon, this.tooltip, this.onTap);

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(3),
          child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, size: 13, color: SwarmColors.textMuted)),
        ),
      );
}

class _EmptyEditor extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Center(child: Text('No file open', style: TextStyle(color: SwarmColors.textMuted, fontSize: 12)));
}
