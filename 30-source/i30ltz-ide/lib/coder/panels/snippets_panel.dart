import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/swarm_colors.dart';

// ─── Snippet Model ────────────────────────────────────────────────────────────
class CustomSnippet {
  String trigger;
  String label;
  String body;
  String description;
  String language; // 'any', 'dart', 'python', 'javascript', 'kotlin'

  CustomSnippet({required this.trigger, required this.label, required this.body, this.description = '', this.language = 'any'});

  Map<String, dynamic> toJson() => {'trigger': trigger, 'label': label, 'body': body, 'description': description, 'language': language};
  factory CustomSnippet.fromJson(Map<String, dynamic> j) => CustomSnippet(trigger: j['trigger'] ?? '', label: j['label'] ?? '', body: j['body'] ?? '', description: j['description'] ?? '', language: j['language'] ?? 'any');
}

// ─── Snippet Storage ─────────────────────────────────────────────────────────
class SnippetStorage {
  static const _key = 'ide_custom_snippets';

  static Future<List<CustomSnippet>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => CustomSnippet.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<CustomSnippet> snippets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(snippets.map((s) => s.toJson()).toList()));
  }
}

// ─── Built-in snippets (read-only reference) ──────────────────────────────────
const _builtinSnippets = [
  ('dart', 'stless',    'StatelessWidget class scaffold'),
  ('dart', 'stful',     'StatefulWidget class scaffold'),
  ('dart', 'build',     'build() override'),
  ('dart', 'initstate', 'initState() override'),
  ('dart', 'dispose',   'dispose() override'),
  ('dart', 'setState',  'setState(() { })'),
  ('dart', 'asyncfn',   'async function'),
  ('dart', 'tryCatch',  'try/catch block'),
  ('dart', 'ifnull',    'null coalescing ??'),
  ('dart', 'print',     "print('…')"),
  ('dart', 'override',  '@override method'),
];

// ─── Snippets Panel ───────────────────────────────────────────────────────────
class SnippetsPanel extends StatefulWidget {
  const SnippetsPanel({super.key});

  @override
  State<SnippetsPanel> createState() => _SnippetsPanelState();
}

class _SnippetsPanelState extends State<SnippetsPanel> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<CustomSnippet> _custom = [];
  bool _loading = true;
  CustomSnippet? _editing;
  bool _isNew = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadSnippets();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSnippets() async {
    final snippets = await SnippetStorage.load();
    setState(() { _custom = snippets; _loading = false; });
  }

  Future<void> _save() async {
    await SnippetStorage.save(_custom);
  }

  void _startNew() {
    setState(() {
      _isNew = true;
      _editing = CustomSnippet(trigger: '', label: '', body: '', description: '', language: 'any');
    });
  }

  void _startEdit(CustomSnippet s) {
    setState(() { _isNew = false; _editing = CustomSnippet(trigger: s.trigger, label: s.label, body: s.body, description: s.description, language: s.language); });
  }

  void _cancelEdit() => setState(() => _editing = null);

  Future<void> _commitEdit(CustomSnippet updated) async {
    setState(() {
      if (_isNew) {
        _custom.add(updated);
      } else {
        final idx = _custom.indexWhere((s) => s.trigger == _editing!.trigger && s.language == _editing!.language);
        if (idx >= 0) _custom[idx] = updated;
      }
      _editing = null;
    });
    await _save();
  }

  Future<void> _delete(CustomSnippet s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: SwarmColors.bgElevated,
        title: const Text('Delete snippet?', style: TextStyle(color: SwarmColors.textPrimary, fontSize: 14)),
        content: Text('Delete "${s.trigger}" (${s.label})?', style: const TextStyle(color: SwarmColors.textSecondary, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: SwarmColors.textMuted))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: SwarmColors.agentRose))),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _custom.removeWhere((x) => x.trigger == s.trigger && x.language == s.language));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    if (_editing != null) {
      return _SnippetEditor(
        snippet: _editing!,
        isNew: _isNew,
        onCancel: _cancelEdit,
        onSave: _commitEdit,
      );
    }

    return Column(children: [
      Container(
        color: SwarmColors.bgSurface,
        child: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          labelColor: SwarmColors.accent,
          unselectedLabelColor: SwarmColors.textMuted,
          indicatorColor: SwarmColors.accent,
          indicatorWeight: 2,
          tabs: const [Tab(text: 'MY SNIPPETS', height: 32), Tab(text: 'BUILT-IN', height: 32)],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tabCtrl,
          children: [
            // ── Custom snippets tab ──────────────────────────
            _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 1.5, color: SwarmColors.accent))
                : Column(children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(children: [
                        const Expanded(child: Text('Custom snippets are available in\nall editors via autocompletion.', style: TextStyle(fontSize: 10, color: SwarmColors.textMuted))),
                        ElevatedButton.icon(
                          onPressed: _startNew,
                          icon: const Icon(Icons.add, size: 13),
                          label: const Text('New', style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(backgroundColor: SwarmColors.accent.withValues(alpha: 0.15), foregroundColor: SwarmColors.accent, side: BorderSide(color: SwarmColors.accent.withValues(alpha: 0.4)), elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
                        ),
                      ]),
                    ),
                    if (_custom.isEmpty)
                      const Expanded(child: Center(child: Text('No custom snippets yet.\nClick New to create one.', textAlign: TextAlign.center, style: TextStyle(color: SwarmColors.textMuted, fontSize: 12))))
                    else
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: _custom.length,
                          itemBuilder: (_, i) => _SnippetRow(
                            snippet: _custom[i],
                            onEdit: () => _startEdit(_custom[i]),
                            onDelete: () => _delete(_custom[i]),
                          ),
                        ),
                      ),
                  ]),

            // ── Built-in snippets tab ────────────────────────
            ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: _builtinSnippets.map((s) => _BuiltinRow(lang: s.$1, trigger: s.$2, desc: s.$3)).toList(),
            ),
          ],
        ),
      ),
    ]);
  }
}

// ─── Custom snippet row ───────────────────────────────────────────────────────
class _SnippetRow extends StatefulWidget {
  final CustomSnippet snippet;
  final VoidCallback onEdit, onDelete;
  const _SnippetRow({required this.snippet, required this.onEdit, required this.onDelete});

  @override
  State<_SnippetRow> createState() => _SnippetRowState();
}

class _SnippetRowState extends State<_SnippetRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.snippet;
    final langColor = _langColor(s.language);
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SwarmColors.border, width: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 14, color: SwarmColors.textDisabled),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: langColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3), border: Border.all(color: langColor.withValues(alpha: 0.4))),
                child: Text(s.language, style: TextStyle(fontSize: 9, color: langColor, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Text(s.trigger, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: SwarmColors.accent, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Expanded(child: Text(s.label, style: const TextStyle(fontSize: 11, color: SwarmColors.textSecondary), overflow: TextOverflow.ellipsis)),
              InkWell(onTap: widget.onEdit, borderRadius: BorderRadius.circular(3), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.edit_rounded, size: 13, color: SwarmColors.agentCyan))),
              InkWell(onTap: widget.onDelete, borderRadius: BorderRadius.circular(3), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.delete_outline_rounded, size: 13, color: SwarmColors.agentRose))),
            ]),
          ),
        ),
        if (_expanded)
          Container(
            margin: const EdgeInsets.fromLTRB(28, 0, 10, 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: SwarmColors.bgPanel, borderRadius: BorderRadius.circular(4), border: Border.all(color: SwarmColors.border)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (s.description.isNotEmpty)
                Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(s.description, style: const TextStyle(fontSize: 10, color: SwarmColors.textMuted))),
              SelectableText(s.body, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: SwarmColors.textSecondary)),
            ]),
          ),
      ]),
    );
  }

  Color _langColor(String l) => switch (l) {
        'dart'       => const Color(0xFF82AAFF),
        'python'     => SwarmColors.agentAmber,
        'javascript' => const Color(0xFFFFCB6B),
        'kotlin'     => SwarmColors.agentOrange,
        _            => SwarmColors.textMuted,
      };
}

// ─── Built-in row ─────────────────────────────────────────────────────────────
class _BuiltinRow extends StatelessWidget {
  final String lang, trigger, desc;
  const _BuiltinRow({required this.lang, required this.trigger, required this.desc});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: const Color(0xFF82AAFF).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(3), border: Border.all(color: const Color(0xFF82AAFF).withValues(alpha: 0.3))),
            child: const Text('dart', style: TextStyle(fontSize: 9, color: Color(0xFF82AAFF), fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: Text(trigger, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: SwarmColors.accent, fontWeight: FontWeight.bold))),
          Expanded(child: Text(desc, style: const TextStyle(fontSize: 11, color: SwarmColors.textMuted))),
          const Icon(Icons.lock_outline_rounded, size: 11, color: SwarmColors.textDisabled),
        ]),
      );
}

// ─── Snippet Editor form ──────────────────────────────────────────────────────
class _SnippetEditor extends StatefulWidget {
  final CustomSnippet snippet;
  final bool isNew;
  final VoidCallback onCancel;
  final ValueChanged<CustomSnippet> onSave;

  const _SnippetEditor({required this.snippet, required this.isNew, required this.onCancel, required this.onSave});

  @override
  State<_SnippetEditor> createState() => _SnippetEditorState();
}

class _SnippetEditorState extends State<_SnippetEditor> {
  late TextEditingController _trigger, _label, _body, _desc;
  String _language = 'any';
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.snippet;
    _trigger = TextEditingController(text: s.trigger);
    _label = TextEditingController(text: s.label);
    _body = TextEditingController(text: s.body);
    _desc = TextEditingController(text: s.description);
    _language = s.language;
  }

  @override
  void dispose() {
    for (final c in [_trigger, _label, _body, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (_trigger.text.trim().isEmpty) { setState(() => _error = 'Trigger is required'); return; }
    if (_label.text.trim().isEmpty) { setState(() => _error = 'Label is required'); return; }
    if (_body.text.trim().isEmpty) { setState(() => _error = 'Body is required'); return; }
    widget.onSave(CustomSnippet(trigger: _trigger.text.trim(), label: _label.text.trim(), body: _body.text, description: _desc.text.trim(), language: _language));
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            InkWell(onTap: widget.onCancel, borderRadius: BorderRadius.circular(4), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.arrow_back_ios_new_rounded, size: 13, color: SwarmColors.agentCyan))),
            const SizedBox(width: 8),
            Text(widget.isNew ? 'New Snippet' : 'Edit Snippet', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: SwarmColors.textPrimary)),
          ]),
          const SizedBox(height: 12),
          const _Label('Trigger (autocompletion keyword)'),
          _Input(_trigger, 'e.g. fetchJson'),
          const SizedBox(height: 8),
          const _Label('Label (display name)'),
          _Input(_label, 'e.g. Fetch JSON from URL'),
          const SizedBox(height: 8),
          const _Label('Language'),
          DropdownButtonHideUnderline(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(color: SwarmColors.bgElevated, borderRadius: BorderRadius.circular(4), border: Border.all(color: SwarmColors.border)),
              child: DropdownButton<String>(
                value: _language,
                dropdownColor: SwarmColors.bgElevated,
                style: const TextStyle(fontSize: 12, color: SwarmColors.textSecondary),
                items: const [
                  DropdownMenuItem(value: 'any', child: Text('Any language')),
                  DropdownMenuItem(value: 'dart', child: Text('Dart')),
                  DropdownMenuItem(value: 'python', child: Text('Python')),
                  DropdownMenuItem(value: 'javascript', child: Text('JavaScript / TypeScript')),
                  DropdownMenuItem(value: 'kotlin', child: Text('Kotlin')),
                ],
                onChanged: (v) => setState(() => _language = v!),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const _Label('Description (optional)'),
          _Input(_desc, 'Short description shown in completion popup'),
          const SizedBox(height: 8),
          const _Label('Body'),
          Container(
            height: 180,
            decoration: BoxDecoration(color: SwarmColors.bgElevated, borderRadius: BorderRadius.circular(4), border: Border.all(color: SwarmColors.border)),
            child: TextField(
              controller: _body,
              maxLines: null,
              expands: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: SwarmColors.textPrimary),
              decoration: const InputDecoration(hintText: 'Snippet body…\nUse \${1:placeholder} for tab stops', hintStyle: TextStyle(color: SwarmColors.textDisabled, fontSize: 11), border: InputBorder.none, contentPadding: EdgeInsets.all(8)),
            ),
          ),
          const SizedBox(height: 4),
          const Text(r'Tip: Use ${1:name} for tab stops, $0 for final cursor position.', style: TextStyle(fontSize: 10, color: SwarmColors.textDisabled)),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(fontSize: 11, color: SwarmColors.agentRose)),
            const SizedBox(height: 8),
          ],
          Row(children: [
            Expanded(child: ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(backgroundColor: SwarmColors.accent.withValues(alpha: 0.2), foregroundColor: SwarmColors.accent, side: BorderSide(color: SwarmColors.accent.withValues(alpha: 0.5)), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
              child: Text(widget.isNew ? 'Create Snippet' : 'Save Changes', style: const TextStyle(fontSize: 12)),
            )),
            const SizedBox(width: 8),
            TextButton(onPressed: widget.onCancel, child: const Text('Cancel', style: TextStyle(fontSize: 12, color: SwarmColors.textMuted))),
          ]),
        ]),
      );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: const TextStyle(fontSize: 10, color: SwarmColors.textMuted, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
      );
}

class _Input extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  const _Input(this.ctrl, this.hint);

  @override
  Widget build(BuildContext context) => TextField(
        controller: ctrl,
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: SwarmColors.textPrimary),
        decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: SwarmColors.textDisabled, fontSize: 11), isDense: true, filled: true, fillColor: SwarmColors.bgElevated, border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: SwarmColors.border)), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
      );
}
