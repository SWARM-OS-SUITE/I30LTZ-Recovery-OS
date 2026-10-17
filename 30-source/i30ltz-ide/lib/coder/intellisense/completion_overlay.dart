import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/swarm_colors.dart';
import 'completion_provider.dart';

// ─── Completion Overlay Controller ───────────────────────────────────────────
class CompletionController {
  final OverlayState overlay;
  OverlayEntry? _entry;

  CompletionController(this.overlay);

  void show({
    required List<CompletionItem> items,
    required Offset position,
    required ValueChanged<CompletionItem> onAccept,
    required VoidCallback onDismiss,
  }) {
    dismiss();
    if (items.isEmpty) return;
    _entry = OverlayEntry(builder: (_) => _CompletionPopup(
      items: items,
      position: position,
      onAccept: (item) { dismiss(); onAccept(item); },
      onDismiss: () { dismiss(); onDismiss(); },
    ));
    overlay.insert(_entry!);
  }

  void dismiss() {
    _entry?.remove();
    _entry = null;
  }

  bool get isOpen => _entry != null;
}

// ─── Popup Widget ─────────────────────────────────────────────────────────────
class _CompletionPopup extends StatefulWidget {
  final List<CompletionItem> items;
  final Offset position;
  final ValueChanged<CompletionItem> onAccept;
  final VoidCallback onDismiss;

  const _CompletionPopup({
    required this.items,
    required this.position,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  State<_CompletionPopup> createState() => _CompletionPopupState();
}

class _CompletionPopupState extends State<_CompletionPopup> {
  int _selectedIdx = 0;
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode()..requestFocus();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    const popupWidth = 320.0;
    const itemHeight = 28.0;
    final popupHeight = (widget.items.length * itemHeight).clamp(0.0, 240.0);

    // Flip up if too close to bottom
    double top = widget.position.dy + 4;
    if (top + popupHeight > screen.height - 20) top = widget.position.dy - popupHeight - 4;

    double left = widget.position.dx;
    if (left + popupWidth > screen.width - 8) left = screen.width - popupWidth - 8;

    return Stack(children: [
      // Dismiss barrier
      Positioned.fill(child: GestureDetector(onTap: widget.onDismiss, behavior: HitTestBehavior.translucent)),
      // Popup
      Positioned(
        top: top,
        left: left,
        width: popupWidth,
        child: KeyboardListener(
          focusNode: _focus,
          onKeyEvent: (event) {
            if (event is! KeyDownEvent) return;
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              setState(() => _selectedIdx = (_selectedIdx + 1) % widget.items.length);
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              setState(() => _selectedIdx = (_selectedIdx - 1 + widget.items.length) % widget.items.length);
            } else if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.tab) {
              widget.onAccept(widget.items[_selectedIdx]);
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              widget.onDismiss();
            }
          },
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: BoxConstraints(maxHeight: popupHeight),
              decoration: BoxDecoration(
                color: SwarmColors.bgElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: SwarmColors.border),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 3),
                shrinkWrap: true,
                itemCount: widget.items.length,
                itemExtent: itemHeight,
                itemBuilder: (_, i) => _CompletionRow(
                  item: widget.items[i],
                  isSelected: i == _selectedIdx,
                  onTap: () => widget.onAccept(widget.items[i]),
                  onHover: () => setState(() => _selectedIdx = i),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _CompletionRow extends StatelessWidget {
  final CompletionItem item;
  final bool isSelected;
  final VoidCallback onTap, onHover;

  const _CompletionRow({required this.item, required this.isSelected, required this.onTap, required this.onHover});

  Color get _kindColor => switch (item.kind) {
        CompletionKind.keyword  => const Color(0xFFBB86FC),
        CompletionKind.type     => const Color(0xFF82AAFF),
        CompletionKind.function => const Color(0xFF82AAFF),
        CompletionKind.snippet  => SwarmColors.accent,
        CompletionKind.variable => const Color(0xFFC3E88D),
        CompletionKind.field    => const Color(0xFFF78C6C),
        CompletionKind.property => const Color(0xFFFFCB6B),
        CompletionKind.module   => const Color(0xFF06B6D4),
      };

  String get _kindLabel => switch (item.kind) {
        CompletionKind.keyword  => 'kw',
        CompletionKind.type     => 'ty',
        CompletionKind.function => 'fn',
        CompletionKind.snippet  => '⬡',
        CompletionKind.variable => 'v',
        CompletionKind.field    => 'f',
        CompletionKind.property => 'p',
        CompletionKind.module   => 'm',
      };

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => onHover(),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: isSelected ? SwarmColors.accent.withValues(alpha: 0.15) : Colors.transparent,
            child: Row(children: [
              Container(
                width: 20, height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: _kindColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)),
                child: Text(_kindLabel, style: TextStyle(fontSize: 9, color: _kindColor, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(item.label, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: isSelected ? SwarmColors.textPrimary : SwarmColors.textSecondary, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal), overflow: TextOverflow.ellipsis),
              ),
              if (item.detail != null)
                Text(item.detail!, style: const TextStyle(fontSize: 10, color: SwarmColors.textDisabled), overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      );
}

// ─── Hover Doc Tooltip ───────────────────────────────────────────────────────
class HoverDocTooltip extends StatelessWidget {
  final String symbol;
  final String documentation;
  final Offset position;

  const HoverDocTooltip({super.key, required this.symbol, required this.documentation, required this.position});

  @override
  Widget build(BuildContext context) => Positioned(
        left: position.dx,
        top: position.dy - 72,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1332),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: SwarmColors.agentCyan.withValues(alpha: 0.4)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 8)],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(symbol, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: SwarmColors.agentCyan, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(documentation, style: const TextStyle(fontSize: 11.5, color: SwarmColors.textSecondary)),
            ]),
          ),
        ),
      );
}
