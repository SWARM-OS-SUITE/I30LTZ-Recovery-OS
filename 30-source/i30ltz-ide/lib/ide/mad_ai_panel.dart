// I30LTZ IDE: Dr. I30LTZ "MAD AI" chat panel.
// Talks ONLY to the local Ollama on 127.0.0.1:11434 (Recovery OS rule: local-first, 7B max, no cloud).
// The AI proposes; it never edits, runs or installs anything by itself. Code blocks have a Copy button,
// and pasting is the user's own action.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../theme/swarm_colors.dart';
import '../theme/swarm_text_styles.dart';

const _ollama = 'http://127.0.0.1:11434';
const _preferredModels = ['qwen2.5:7b', 'qwen2.5-coder:7b', 'mistral:7b', 'mistral'];

const _systemPrompt = 'You are Dr. I30LTZ ("MAD AI"), the coding and recovery assistant inside I30LTZ Recovery OS. '
    'The user is on a rescue machine, often repairing or recovering data from a broken PC. '
    'Be concise and concrete. Put code in fenced blocks. For any command that changes a disk, partition, '
    'filesystem or file, explain the effect first and warn about data loss. Never claim you ran anything: '
    'you only propose, the user decides.';

class _Msg {
  final String role; // user | assistant
  String text;
  _Msg(this.role, this.text);
}

class MadAiPanel extends StatefulWidget {
  const MadAiPanel({super.key});

  @override
  State<MadAiPanel> createState() => _MadAiPanelState();
}

class _MadAiPanelState extends State<MadAiPanel> {
  final _msgs = <_Msg>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  http.Client? _client;
  List<String> _models = [];
  String? _model;
  bool _busy = false;
  String? _offline; // human-readable reason when Ollama is unreachable

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  @override
  void dispose() {
    _client?.close();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadModels() async {
    try {
      final r = await http.get(Uri.parse('$_ollama/api/tags')).timeout(const Duration(seconds: 4));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final names = ((jsonDecode(r.body)['models'] as List?) ?? [])
          .map((m) => (m as Map)['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _models = names;
        _model = names.isEmpty
            ? null
            : (_preferredModels.firstWhere(names.contains, orElse: () => names.first));
        _offline = names.isEmpty ? 'Ollama is running but no model is installed. Pull one in the Ollama panel.' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _offline = 'Ollama is not running on this machine (127.0.0.1:11434). Start it with: ollama serve');
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy || _model == null) return;
    _input.clear();
    final reply = _Msg('assistant', '');
    setState(() {
      _msgs.add(_Msg('user', text));
      _msgs.add(reply);
      _busy = true;
    });
    _toBottom();

    final client = _client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse('$_ollama/api/chat'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'model': _model,
          'stream': true,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            for (final m in _msgs.where((m) => m != reply)) {'role': m.role, 'content': m.text},
          ],
        });
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw Exception('Ollama answered HTTP ${res.statusCode}');
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        final j = jsonDecode(line) as Map<String, dynamic>;
        final piece = (j['message'] as Map?)?['content']?.toString() ?? '';
        if (piece.isNotEmpty && mounted) {
          setState(() => reply.text += piece);
          _toBottom();
        }
      }
      if (reply.text.isEmpty && mounted) setState(() => reply.text = '(no answer)');
    } catch (e) {
      if (mounted) {
        setState(() => reply.text += '${reply.text.isEmpty ? '' : '\n\n'}MAD AI is unreachable: $e');
      }
    } finally {
      client.close();
      if (mounted) {
        setState(() => _busy = false);
        _focus.requestFocus();
      }
    }
  }

  void _stop() {
    _client?.close();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _header(),
      if (_offline != null) _banner(_offline!),
      Expanded(
        child: _msgs.isEmpty
            ? _empty()
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                itemCount: _msgs.length,
                itemBuilder: (_, i) => _bubble(_msgs[i], busy: _busy && i == _msgs.length - 1),
              ),
      ),
      _composer(),
    ]);
  }

  Widget _header() => Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SwarmColors.border))),
        child: Row(children: [
          Expanded(
            child: _models.isEmpty
                ? Text('no model', style: SwarmTextStyles.codeSmall)
                : DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _model,
                      isDense: true,
                      isExpanded: true,
                      dropdownColor: SwarmColors.bgElevated,
                      style: SwarmTextStyles.codeSmall.copyWith(color: SwarmColors.accent),
                      items: [for (final m in _models) DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis))],
                      onChanged: _busy ? null : (v) => setState(() => _model = v),
                    ),
                  ),
          ),
          IconButton(
            tooltip: 'Refresh models',
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            onPressed: _busy ? null : _loadModels,
            icon: const Icon(Icons.refresh_rounded, color: SwarmColors.textMuted),
          ),
          IconButton(
            tooltip: 'Clear chat',
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            onPressed: _busy || _msgs.isEmpty ? null : () => setState(_msgs.clear),
            icon: const Icon(Icons.delete_sweep_rounded, color: SwarmColors.textMuted),
          ),
        ]),
      );

  Widget _banner(String text) => Container(
        width: double.infinity,
        color: SwarmColors.statusIdle.withValues(alpha: 0.12),
        padding: const EdgeInsets.all(10),
        child: Text(text, style: SwarmTextStyles.codeSmall.copyWith(color: SwarmColors.statusIdle)),
      );

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.bolt_rounded, size: 40, color: SwarmColors.accent),
            const SizedBox(height: 10),
            Text('DR. I30LTZ  ·  MAD AI', style: SwarmTextStyles.label.copyWith(color: SwarmColors.accent)),
            const SizedBox(height: 8),
            Text(
              'Local AI pair programmer. Ask about your code, a broken disk or a script.\n'
              'It only suggests; nothing runs or changes without your click.',
              textAlign: TextAlign.center,
              style: SwarmTextStyles.codeSmall,
            ),
          ]),
        ),
      );

  Widget _bubble(_Msg m, {required bool busy}) {
    final mine = m.role == 'user';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: mine ? SwarmColors.accent.withValues(alpha: 0.12) : SwarmColors.bgPanel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: mine ? SwarmColors.accent.withValues(alpha: 0.35) : SwarmColors.border),
        ),
        child: mine
            ? SelectableText(m.text, style: SwarmTextStyles.code.copyWith(fontSize: 12.5))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ..._blocks(m.text),
                if (busy && m.text.isEmpty) Text('Dr. I30LTZ is thinking…', style: SwarmTextStyles.codeSmall),
              ]),
      ),
    );
  }

  /// Splits an answer into prose and fenced code blocks; code blocks get a Copy button.
  List<Widget> _blocks(String text) {
    final out = <Widget>[];
    final parts = text.split('```');
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (i.isEven) {
        if (part.trim().isNotEmpty) out.add(SelectableText(part.trim(), style: SwarmTextStyles.code.copyWith(fontSize: 12.5, height: 1.5)));
      } else {
        final nl = part.indexOf('\n');
        final lang = nl > 0 ? part.substring(0, nl).trim() : '';
        final code = (nl >= 0 ? part.substring(nl + 1) : part).trimRight();
        out.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: SwarmColors.bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: SwarmColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.only(left: 8),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SwarmColors.border))),
              child: Row(children: [
                Text(lang.isEmpty ? 'code' : lang, style: SwarmTextStyles.codeSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      duration: Duration(seconds: 2),
                      content: Text('Copied. Paste it where you want it; nothing was applied.'),
                    ));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 13),
                  label: const Text('Copy'),
                  style: TextButton.styleFrom(foregroundColor: SwarmColors.accent, visualDensity: VisualDensity.compact),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: SelectableText(code, style: SwarmTextStyles.code.copyWith(fontSize: 12)),
            ),
          ]),
        ));
      }
    }
    return out;
  }

  Widget _composer() => Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: SwarmColors.border))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter, control: true): _send,
              },
              child: TextField(
                controller: _input,
                focusNode: _focus,
                enabled: _model != null,
                minLines: 1,
                maxLines: 6,
                style: SwarmTextStyles.code.copyWith(fontSize: 12.5),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _model == null ? 'MAD AI is offline' : 'Ask Dr. I30LTZ…  (Ctrl+Enter to send)',
                  hintStyle: SwarmTextStyles.codeSmall,
                  filled: true,
                  fillColor: SwarmColors.bgSurface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: SwarmColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: SwarmColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: SwarmColors.accent)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _busy
              ? IconButton.filled(
                  onPressed: _stop,
                  tooltip: 'Stop',
                  style: IconButton.styleFrom(backgroundColor: SwarmColors.statusCritical),
                  icon: const Icon(Icons.stop_rounded, size: 18),
                )
              : IconButton.filled(
                  onPressed: _model == null ? null : _send,
                  tooltip: 'Send',
                  style: IconButton.styleFrom(backgroundColor: SwarmColors.accent, foregroundColor: Colors.black),
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                ),
        ]),
      );
}
