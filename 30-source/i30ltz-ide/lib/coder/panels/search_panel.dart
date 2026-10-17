import 'dart:io';
import 'package:flutter/material.dart';
import '../../theme/swarm_colors.dart';
import '../editor_model.dart';

class SearchPanel extends StatefulWidget {
  final String? rootPath;
  final ValueChanged<(String file, int line)> onResultTap;

  const SearchPanel({super.key, this.rootPath, required this.onResultTap});

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  final _queryCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  bool _caseSensitive = false;
  bool _useRegex = false;
  bool _wholeWord = false;
  bool _showReplace = false;
  bool _searching = false;
  Map<String, List<SearchResult>> _results = {};

  @override
  void dispose() {
    _queryCtrl.dispose();
    _replaceCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (widget.rootPath == null || _queryCtrl.text.trim().isEmpty) return;
    setState(() { _searching = true; _results = {}; });

    final query = _queryCtrl.text.trim();
    final grouped = <String, List<SearchResult>>{};

    try {
      final args = ['grep', '-rn', '--include=*', '--', query, widget.rootPath!];
      if (!_caseSensitive) args.insert(1, '-i');
      if (_wholeWord) args.insert(1, '-w');
      if (_useRegex) args.insert(1, '-E');

      final result = await Process.run('grep', [
        '-rn',
        if (!_caseSensitive) '-i',
        if (_wholeWord) '-w',
        if (_useRegex) '-E',
        '--include=*.dart', '--include=*.py', '--include=*.js', '--include=*.ts',
        '--include=*.kt', '--include=*.java', '--include=*.json', '--include=*.yaml',
        '--include=*.md', '--include=*.sh', '--include=*.cs', '--include=*.html',
        '--include=*.css', '--include=*.xml', '--include=*.go', '--include=*.rs',
        '-l',
        '--',
        query,
        widget.rootPath!,
      ]);

      final files = result.stdout.toString().split('\n').where((l) => l.trim().isNotEmpty).toList();

      for (final filePath in files.take(50)) {
        final fileResult = await Process.run('grep', [
          '-n',
          if (!_caseSensitive) '-i',
          if (_wholeWord) '-w',
          if (_useRegex) '-E',
          '--',
          query,
          filePath,
        ]);
        final lines = fileResult.stdout.toString().split('\n').where((l) => l.trim().isNotEmpty);
        final resultList = <SearchResult>[];
        for (final line in lines.take(20)) {
          final colonIdx = line.indexOf(':');
          if (colonIdx < 0) continue;
          final lineNum = int.tryParse(line.substring(0, colonIdx)) ?? 0;
          final lineText = line.substring(colonIdx + 1);
          final matchStart = _caseSensitive
              ? lineText.indexOf(query)
              : lineText.toLowerCase().indexOf(query.toLowerCase());
          resultList.add(SearchResult(
            file: filePath,
            line: lineNum,
            lineText: lineText,
            matchStart: matchStart < 0 ? 0 : matchStart,
            matchEnd: matchStart < 0 ? query.length : matchStart + query.length,
          ));
        }
        if (resultList.isNotEmpty) {
          grouped[filePath] = resultList;
        }
      }
    } catch (_) {}

    if (mounted) setState(() { _results = grouped; _searching = false; });
  }

  int get _totalMatches => _results.values.fold(0, (acc, r) => acc + r.length);

  Future<void> _replaceAll() async {
    final query = _queryCtrl.text;
    final replacement = _replaceCtrl.text;
    if (query.isEmpty || _results.isEmpty) return;

    int replaced = 0;
    for (final filePath in _results.keys) {
      try {
        final file = File(filePath);
        var content = await file.readAsString();
        final original = content;
        if (_useRegex) {
          content = content.replaceAll(
            RegExp(query, caseSensitive: _caseSensitive),
            replacement,
          );
        } else if (_caseSensitive) {
          content = content.replaceAll(query, replacement);
        } else {
          content = content.replaceAll(
            RegExp(RegExp.escape(query), caseSensitive: false),
            replacement,
          );
        }
        if (content != original) {
          await file.writeAsString(content);
          replaced++;
        }
      } catch (_) {}
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Replaced in $replaced file${replaced == 1 ? '' : 's'}'),
        duration: const Duration(seconds: 2),
      ));
      _search();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header / inputs
        Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SwarmColors.border))),
          child: Column(children: [
            // Search field
            Row(children: [
              Expanded(
                child: _SearchField(
                  controller: _queryCtrl,
                  hint: 'Search',
                  onSubmit: (_) => _search(),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    _ToggleBtn('Aa', _caseSensitive, () => setState(() => _caseSensitive = !_caseSensitive), 'Case sensitive'),
                    _ToggleBtn(r'\b', _wholeWord, () => setState(() => _wholeWord = !_wholeWord), 'Whole word'),
                    _ToggleBtn('.*', _useRegex, () => setState(() => _useRegex = !_useRegex), 'Use regex'),
                  ]),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: _searching ? null : _search,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: SwarmColors.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4), border: Border.all(color: SwarmColors.accent.withValues(alpha: 0.4))),
                  child: _searching
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: SwarmColors.accent))
                      : const Icon(Icons.search, size: 14, color: SwarmColors.accent),
                ),
              ),
            ]),
            // Replace toggle / field
            const SizedBox(height: 6),
            Row(children: [
              InkWell(onTap: () => setState(() => _showReplace = !_showReplace), child: Icon(_showReplace ? Icons.expand_less : Icons.expand_more, size: 14, color: SwarmColors.textMuted)),
              const SizedBox(width: 6),
              Text('Replace', style: TextStyle(fontSize: 11, color: _showReplace ? SwarmColors.textSecondary : SwarmColors.textMuted)),
            ]),
            if (_showReplace) ...[
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: _SearchField(controller: _replaceCtrl, hint: 'Replace', onSubmit: null)),
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Replace All',
                  child: InkWell(
                    onTap: _replaceAll,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(color: SwarmColors.agentAmber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4), border: Border.all(color: SwarmColors.agentAmber.withValues(alpha: 0.4))),
                      child: const Text('All', style: TextStyle(fontSize: 10, color: SwarmColors.agentAmber, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ]),
            ],
          ]),
        ),
        // Results summary
        if (_results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(children: [
              Text('$_totalMatches result${_totalMatches == 1 ? '' : 's'} in ${_results.length} file${_results.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 10, color: SwarmColors.textMuted)),
            ]),
          ),
        // Results
        Expanded(
          child: _results.isEmpty
              ? Center(child: Text(
                  widget.rootPath == null ? 'No folder open' : _searching ? 'Searching...' : 'Type to search',
                  style: const TextStyle(fontSize: 12, color: SwarmColors.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final file = _results.keys.elementAt(i);
                    final hits = _results[file]!;
                    return _FileResults(
                      file: file,
                      rootPath: widget.rootPath ?? '',
                      results: hits,
                      query: _queryCtrl.text,
                      caseSensitive: _caseSensitive,
                      onTap: (r) => widget.onResultTap((r.file, r.line)),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onSubmit;
  final Widget? trailing;

  const _SearchField({required this.controller, required this.hint, required this.onSubmit, this.trailing});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        onSubmitted: onSubmit,
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: SwarmColors.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: SwarmColors.textDisabled, fontSize: 12),
          isDense: true,
          filled: true,
          fillColor: SwarmColors.bgElevated,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: SwarmColors.border)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          suffixIcon: trailing,
        ),
      );
}

class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final String tooltip;
  const _ToggleBtn(this.label, this.active, this.onTap, this.tooltip);

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(3),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: active ? SwarmColors.accent.withValues(alpha: 0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(label, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: active ? SwarmColors.accent : SwarmColors.textMuted, fontWeight: FontWeight.bold)),
          ),
        ),
      );
}

class _FileResults extends StatefulWidget {
  final String file, rootPath, query;
  final List<SearchResult> results;
  final bool caseSensitive;
  final ValueChanged<SearchResult> onTap;

  const _FileResults({required this.file, required this.rootPath, required this.results, required this.query, required this.caseSensitive, required this.onTap});

  @override
  State<_FileResults> createState() => _FileResultsState();
}

class _FileResultsState extends State<_FileResults> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final relPath = widget.file.startsWith(widget.rootPath)
        ? widget.file.substring(widget.rootPath.length + 1)
        : widget.file;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: SwarmColors.bgElevated,
          child: Row(children: [
            Icon(_expanded ? Icons.expand_more : Icons.chevron_right, size: 13, color: SwarmColors.textMuted),
            const SizedBox(width: 4),
            Expanded(child: Text(relPath, style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: SwarmColors.textSecondary, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
            Text('${widget.results.length}', style: const TextStyle(fontSize: 10, color: SwarmColors.textMuted)),
          ]),
        ),
      ),
      if (_expanded)
        ...widget.results.map((r) => _ResultRow(result: r, query: widget.query, caseSensitive: widget.caseSensitive, onTap: widget.onTap)),
    ]);
  }
}

class _ResultRow extends StatefulWidget {
  final SearchResult result;
  final String query;
  final bool caseSensitive;
  final ValueChanged<SearchResult> onTap;

  const _ResultRow({required this.result, required this.query, required this.caseSensitive, required this.onTap});

  @override
  State<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<_ResultRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.result.lineText.trim();
    final q = widget.query;
    final idx = widget.caseSensitive ? text.indexOf(q) : text.toLowerCase().indexOf(q.toLowerCase());

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.onTap(widget.result),
        child: Container(
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(color: _hovered ? SwarmColors.bgHover : Colors.transparent),
          child: Row(children: [
            SizedBox(width: 36, child: Text('${widget.result.line}', style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: SwarmColors.textDisabled), textAlign: TextAlign.right)),
            const SizedBox(width: 8),
            Expanded(
              child: idx >= 0
                  ? RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: SwarmColors.textSecondary), children: [
                        TextSpan(text: text.substring(0, idx)),
                        TextSpan(text: text.substring(idx, idx + q.length), style: const TextStyle(color: SwarmColors.accent, backgroundColor: Color(0x2276B900), fontWeight: FontWeight.bold)),
                        TextSpan(text: text.substring(idx + q.length)),
                      ]),
                    )
                  : Text(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: SwarmColors.textSecondary), overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      ),
    );
  }
}
