import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/swarm_colors.dart';

// ─── Keybinding entry ─────────────────────────────────────────────────────────
class KeyBinding {
  final String id;
  final String category;
  final String description;
  final String defaultKey;
  String currentKey;
  bool isCustom;

  KeyBinding({
    required this.id,
    required this.category,
    required this.description,
    required this.defaultKey,
    String? currentKey,
    this.isCustom = false,
  }) : currentKey = currentKey ?? defaultKey;

  Map<String, String> toJson() => {'id': id, 'key': currentKey};
}

// ─── Default bindings ─────────────────────────────────────────────────────────
final _defaultBindings = [
  KeyBinding(id: 'file.save',         category: 'File',       description: 'Save file',              defaultKey: 'Ctrl+S'),
  KeyBinding(id: 'file.close',        category: 'File',       description: 'Close tab',              defaultKey: 'Ctrl+W'),
  KeyBinding(id: 'file.openFolder',   category: 'File',       description: 'Open folder',            defaultKey: 'Ctrl+K Ctrl+O'),
  KeyBinding(id: 'view.sidebar',      category: 'View',       description: 'Toggle sidebar',         defaultKey: 'Ctrl+B'),
  KeyBinding(id: 'view.terminal',     category: 'View',       description: 'Toggle terminal',        defaultKey: 'Ctrl+J'),
  KeyBinding(id: 'view.shortcuts',    category: 'View',       description: 'Keyboard shortcut overlay', defaultKey: 'Ctrl+/'),
  KeyBinding(id: 'nav.search',        category: 'Navigation', description: 'Quick open / search',    defaultKey: 'Ctrl+P'),
  KeyBinding(id: 'nav.git',           category: 'Navigation', description: 'Open Git panel',         defaultKey: 'Ctrl+Shift+G'),
  KeyBinding(id: 'nav.definition',    category: 'Navigation', description: 'Go to definition',       defaultKey: 'F12'),
  KeyBinding(id: 'editor.tab',        category: 'Editor',     description: 'Insert 2 spaces',        defaultKey: 'Tab'),
  KeyBinding(id: 'editor.completion', category: 'Editor',     description: 'Accept completion',      defaultKey: 'Enter / Tab'),
  KeyBinding(id: 'editor.dismiss',    category: 'Editor',     description: 'Dismiss completion',     defaultKey: 'Escape'),
  KeyBinding(id: 'panel.explorer',    category: 'Panels',     description: 'Focus Explorer',         defaultKey: 'Ctrl+Shift+E'),
  KeyBinding(id: 'panel.search',      category: 'Panels',     description: 'Focus Search',           defaultKey: 'Ctrl+P'),
];

// ─── Storage ──────────────────────────────────────────────────────────────────
class KeybindingStorage {
  static const _key = 'ide_keybindings';

  static Future<Map<String, String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(List<KeyBinding> bindings) async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, String>{};
    for (final b in bindings) {
      if (b.isCustom) map[b.id] = b.currentKey;
    }
    await prefs.setString(_key, jsonEncode(map));
  }
}

// ─── Keybindings Panel ────────────────────────────────────────────────────────
class KeybindingsPanel extends StatefulWidget {
  const KeybindingsPanel({super.key});

  @override
  State<KeybindingsPanel> createState() => _KeybindingsPanelState();
}

class _KeybindingsPanelState extends State<KeybindingsPanel> {
  late List<KeyBinding> _bindings;
  bool _loading = true;
  String? _recordingId;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bindings = _defaultBindings.map((b) => KeyBinding(
      id: b.id, category: b.category, description: b.description, defaultKey: b.defaultKey,
    )).toList();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await KeybindingStorage.load();
    setState(() {
      for (final b in _bindings) {
        if (saved.containsKey(b.id)) {
          b.currentKey = saved[b.id]!;
          b.isCustom = b.currentKey != b.defaultKey;
        }
      }
      _loading = false;
    });
  }

  void _startRecording(String id) => setState(() => _recordingId = id);
  void _cancelRecording() => setState(() => _recordingId = null);

  void _recordKey(String id, KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;
    final k = event.logicalKey;

    // Don't record modifier-only presses
    if (k == LogicalKeyboardKey.control || k == LogicalKeyboardKey.controlLeft || k == LogicalKeyboardKey.controlRight ||
        k == LogicalKeyboardKey.shift || k == LogicalKeyboardKey.shiftLeft || k == LogicalKeyboardKey.shiftRight ||
        k == LogicalKeyboardKey.alt || k == LogicalKeyboardKey.altLeft || k == LogicalKeyboardKey.altRight) {
      return;
    }

    final parts = <String>[
      if (ctrl) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      _keyLabel(k),
    ];
    final combo = parts.join('+');

    setState(() {
      final binding = _bindings.firstWhere((b) => b.id == id);
      binding.currentKey = combo;
      binding.isCustom = combo != binding.defaultKey;
      _recordingId = null;
    });
    KeybindingStorage.save(_bindings);
  }

  String _keyLabel(LogicalKeyboardKey k) {
    final label = k.keyLabel;
    if (label.isNotEmpty) return label;
    if (k == LogicalKeyboardKey.slash) return '/';
    if (k == LogicalKeyboardKey.f12) return 'F12';
    if (k == LogicalKeyboardKey.tab) return 'Tab';
    if (k == LogicalKeyboardKey.escape) return 'Escape';
    if (k == LogicalKeyboardKey.enter) return 'Enter';
    if (k == LogicalKeyboardKey.space) return 'Space';
    return k.debugName ?? '?';
  }

  void _reset(String id) {
    setState(() {
      final b = _bindings.firstWhere((b) => b.id == id);
      b.currentKey = b.defaultKey;
      b.isCustom = false;
    });
    KeybindingStorage.save(_bindings);
  }

  void _resetAll() {
    setState(() {
      for (final b in _bindings) { b.currentKey = b.defaultKey; b.isCustom = false; }
    });
    KeybindingStorage.save(_bindings);
  }

  List<KeyBinding> get _filtered {
    if (_searchQuery.isEmpty) return _bindings;
    final q = _searchQuery.toLowerCase();
    return _bindings.where((b) => b.description.toLowerCase().contains(q) || b.currentKey.toLowerCase().contains(q) || b.category.toLowerCase().contains(q)).toList();
  }

  Map<String, List<KeyBinding>> get _grouped {
    final m = <String, List<KeyBinding>>{};
    for (final b in _filtered) {
      (m[b.category] ??= []).add(b);
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(strokeWidth: 1.5, color: SwarmColors.accent));

    return Column(children: [
      // Search + reset bar
      Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SwarmColors.border))),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(fontSize: 12, color: SwarmColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search keybindings…',
                hintStyle: const TextStyle(fontSize: 11, color: SwarmColors.textDisabled),
                prefixIcon: const Icon(Icons.search_rounded, size: 14, color: SwarmColors.textMuted),
                isDense: true, filled: true, fillColor: SwarmColors.bgElevated,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: SwarmColors.border)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Reset all to defaults',
            child: InkWell(
              onTap: _resetAll,
              borderRadius: BorderRadius.circular(4),
              child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.restart_alt_rounded, size: 16, color: SwarmColors.agentAmber)),
            ),
          ),
        ]),
      ),
      // Note
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        color: SwarmColors.bgPanel,
        child: const Text('Custom bindings are saved and loaded on next launch.', style: TextStyle(fontSize: 10, color: SwarmColors.textDisabled)),
      ),
      // Binding list
      Expanded(
        child: KeyboardListener(
          focusNode: FocusNode()..requestFocus(),
          onKeyEvent: _recordingId != null ? (e) => _recordKey(_recordingId!, e) : null,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final entry in _grouped.entries) ...[
                _CategoryHeader(entry.key),
                for (final b in entry.value)
                  _BindingRow(
                    binding: b,
                    isRecording: _recordingId == b.id,
                    onRecord: () => _startRecording(b.id),
                    onCancel: _cancelRecording,
                    onReset: b.isCustom ? () => _reset(b.id) : null,
                  ),
              ],
            ],
          ),
        ),
      ),
    ]);
  }
}

class _CategoryHeader extends StatelessWidget {
  final String title;
  const _CategoryHeader(this.title);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
        child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: SwarmColors.accent, letterSpacing: 1.2)),
      );
}

class _BindingRow extends StatelessWidget {
  final KeyBinding binding;
  final bool isRecording;
  final VoidCallback onRecord, onCancel;
  final VoidCallback? onReset;

  const _BindingRow({required this.binding, required this.isRecording, required this.onRecord, required this.onCancel, this.onReset});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isRecording ? SwarmColors.accent.withValues(alpha: 0.06) : Colors.transparent,
          border: const Border(bottom: BorderSide(color: SwarmColors.border, width: 0.3)),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(binding.description, style: const TextStyle(fontSize: 12, color: SwarmColors.textSecondary)),
              if (binding.isCustom)
                Text('default: ${binding.defaultKey}', style: const TextStyle(fontSize: 10, color: SwarmColors.textDisabled, fontFamily: 'monospace')),
            ]),
          ),
          const SizedBox(width: 8),
          if (isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: SwarmColors.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4), border: Border.all(color: SwarmColors.accent)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 4, height: 4, child: DecoratedBox(decoration: BoxDecoration(color: SwarmColors.accent, shape: BoxShape.circle))),
                const SizedBox(width: 6),
                const Text('Press a key…', style: TextStyle(fontSize: 11, color: SwarmColors.accent)),
                const SizedBox(width: 8),
                InkWell(onTap: onCancel, child: const Icon(Icons.close, size: 13, color: SwarmColors.textMuted)),
              ]),
            )
          else
            _KeyChip(binding.currentKey, binding.isCustom),
          const SizedBox(width: 6),
          InkWell(
            onTap: onRecord,
            borderRadius: BorderRadius.circular(3),
            child: const Tooltip(message: 'Change shortcut', child: Padding(padding: EdgeInsets.all(4), child: Icon(Icons.edit_rounded, size: 13, color: SwarmColors.agentCyan))),
          ),
          if (onReset != null)
            InkWell(
              onTap: onReset,
              borderRadius: BorderRadius.circular(3),
              child: const Tooltip(message: 'Reset to default', child: Padding(padding: EdgeInsets.all(4), child: Icon(Icons.restart_alt_rounded, size: 13, color: SwarmColors.agentAmber))),
            )
          else
            const SizedBox(width: 21),
        ]),
      );
}

class _KeyChip extends StatelessWidget {
  final String label;
  final bool isCustom;
  const _KeyChip(this.label, this.isCustom);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isCustom ? SwarmColors.agentAmber.withValues(alpha: 0.1) : SwarmColors.bgPanel,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isCustom ? SwarmColors.agentAmber.withValues(alpha: 0.5) : SwarmColors.border),
        ),
        child: Text(label, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: isCustom ? SwarmColors.agentAmber : SwarmColors.textSecondary)),
      );
}
