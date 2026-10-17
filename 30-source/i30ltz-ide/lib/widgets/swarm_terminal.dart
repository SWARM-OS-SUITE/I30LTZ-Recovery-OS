// ═══════════════════════════════════════════════════════════════════
// I30LTZ IDE terminal (from SWARM TERMINAL v2)
// Full bash terminal: 4-pane split, ANSI color, animated loading bars,
// copy/paste/cut buttons, right-click context menu, Enter button,
// command history, mouse & controller support.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io' hide Platform;
import '../platform/platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ───────────────────────────────────────────
// ANSI COLOR PARSER
// ───────────────────────────────────────────

class AnsiSpan {
  final String text;
  final Color color;
  final Color? bgColor;
  final bool bold;
  final bool italic;
  final bool underline;

  const AnsiSpan({
    required this.text,
    this.color = const Color(0xFFCCCCCC),
    this.bgColor,
    this.bold = false,
    this.italic = false,
    this.underline = false,
  });
}

class AnsiParser {
  static const Map<int, Color> _fg = {
    30: Color(0xFF2E2E3E), 31: Color(0xFFFF6B6B), 32: Color(0xFF51CF66),
    33: Color(0xFFFFD43B), 34: Color(0xFF74C0FC), 35: Color(0xFFDA77F2),
    36: Color(0xFF66D9E8), 37: Color(0xFFCCCCCC), 90: Color(0xFF666666),
    91: Color(0xFFFF8787), 92: Color(0xFF69DB7C), 93: Color(0xFFFFEC99),
    94: Color(0xFFA5D8FF), 95: Color(0xFFE599F7), 96: Color(0xFF99E9F2),
    97: Color(0xFFFFFFFF),
  };

  static const Map<int, Color> _bg = {
    40: Color(0xFF1A1A2E), 41: Color(0xFF5C2B29), 42: Color(0xFF345920),
    43: Color(0xFF635D19), 44: Color(0xFF2D555E), 45: Color(0xFF42275E),
    46: Color(0xFF16504B), 47: Color(0xFF3C3F43),
  };

  static List<AnsiSpan> parse(String text) {
    final spans = <AnsiSpan>[];
    final re = RegExp(r'\x1B\[([0-9;]*)m');
    Color c = const Color(0xFFCCCCCC);
    Color? bg;
    bool b = false, i = false, u = false;
    int last = 0;

    for (final m in re.allMatches(text)) {
      if (m.start > last) {
        final seg = text.substring(last, m.start);
        if (seg.isNotEmpty) spans.add(AnsiSpan(text: seg, color: c, bgColor: bg, bold: b, italic: i, underline: u));
      }
      for (final code in (m.group(1) ?? '').split(';').map((s) => int.tryParse(s))) {
        if (code == null) continue;
        if (code == 0) { c = const Color(0xFFCCCCCC); bg = null; b = false; i = false; u = false; }
        else if (code == 1) { b = true; }
        else if (code == 3) { i = true; }
        else if (code == 4) { u = true; }
        else if (_fg.containsKey(code)) { c = _fg[code]!; }
        else if (_bg.containsKey(code)) { bg = _bg[code]!; }
      }
      last = m.end;
    }
    if (last < text.length) {
      spans.add(AnsiSpan(text: text.substring(last), color: c, bgColor: bg, bold: b, italic: i, underline: u));
    }
    if (spans.isEmpty && text.isNotEmpty) spans.add(AnsiSpan(text: text));
    return spans;
  }

  static String strip(String text) => text.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
}

// ───────────────────────────────────────────
// TERMINAL LINE
// ───────────────────────────────────────────

class TermLine {
  final String raw;
  final List<AnsiSpan> spans;
  final bool isCmd;
  final bool isErr;
  TermLine(this.raw, {this.isCmd = false, this.isErr = false}) : spans = AnsiParser.parse(raw);
}

// ───────────────────────────────────────────
// TERMINAL PANE STATE
// ───────────────────────────────────────────

class TPane {
  final String id;
  String title;
  final List<TermLine> lines = [];
  final List<String> history = [];
  int histIdx = -1;
  Process? proc;
  String cwd;
  bool busy = false;
  // Output after the last newline — prompts like "[sudo] password for x: "
  // never end in one, so they're shown as a live last line.
  String partial = '';
  bool partialShown = false;
  // True while the running command is asking for a password: input is hidden.
  bool wantsSecret = false;
  final ScrollController scroll = ScrollController();
  final TextEditingController input = TextEditingController();
  final FocusNode focus = FocusNode();

  TPane(this.id, this.title, this.cwd);

  void dispose() {
    proc?.kill();
    scroll.dispose();
    input.dispose();
    focus.dispose();
  }
}

// ═══════════════════════════════════════════════════════════
// TERMINAL WIDGET
// ═══════════════════════════════════════════════════════════

class SwarmTerminal extends StatefulWidget {
  final int initialPanes;
  final String? startDirectory;

  const SwarmTerminal({super.key, this.initialPanes = 1, this.startDirectory});

  @override
  State<SwarmTerminal> createState() => _SwarmTerminalState();
}

class _SwarmTerminalState extends State<SwarmTerminal> with SingleTickerProviderStateMixin {
  final List<TPane> _p = [];
  int _active = 0;
  int _layout = 1;
  bool _toolbar = true;
  late final AnimationController _anim;
  final Map<String, Timer> _progressTimers = {};
  final Map<String, double> _progress = {};
  String _clip = '';

  // Personalized text size — bigger by default than the original cramped
  // 10-12.5px, and remembered per-user so it doesn't reset every launch.
  static const _kFontScaleKey = 'swarm_terminal_font_scale';
  double _fontScale = 1.35;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
    for (int i = 0; i < widget.initialPanes.clamp(1, 4); i++) {
      _addPane();
    }
    _loadFontScale();
  }

  Future<void> _loadFontScale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_kFontScaleKey);
      if (saved != null && mounted) setState(() => _fontScale = saved);
    } catch (_) {}
  }

  Future<void> _adjustFontScale(double delta) async {
    setState(() => _fontScale = (_fontScale + delta).clamp(0.8, 2.2));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kFontScaleKey, _fontScale);
    } catch (_) {}
  }

  @override
  void dispose() {
    _anim.dispose();
    for (final t in _progressTimers.values) {
      t.cancel();
    }
    for (final p in _p) {
      p.dispose();
    }
    super.dispose();
  }

  void _addPane() {
    if (_p.length >= 4) return;
    final idx = _p.length;
    final home = widget.startDirectory ?? Platform.environment['HOME'] ?? '/';
    final pane = TPane('p${idx}_${DateTime.now().millisecondsSinceEpoch}', 'bash ${idx + 1}', home);

    pane.lines.addAll([
      TermLine('\x1B[36m┌─────────────────────────────────────────┐\x1B[0m'),
      TermLine('\x1B[36m│\x1B[0m \x1B[1;95m⚡ I30LTZ Terminal\x1B[0m \x1B[90m· pane ${idx + 1}\x1B[0m               \x1B[36m│\x1B[0m'),
      TermLine('\x1B[36m│\x1B[0m \x1B[90mBash · ANSI color · Multi-pane\x1B[0m         \x1B[36m│\x1B[0m'),
      TermLine('\x1B[36m└─────────────────────────────────────────┘\x1B[0m'),
      TermLine(''),
    ]);
    setState(() => _p.add(pane));
  }

  void _removePane(int i) {
    if (_p.length <= 1) return;
    _p[i].dispose();
    setState(() {
      _p.removeAt(i);
      if (_active >= _p.length) _active = _p.length - 1;
    });
  }

  void _cycleLayout() => setState(() {
    if (_layout == 1 && _p.length >= 2) {
      _layout = 2;
    } else if (_layout == 2 && _p.length >= 4) { _layout = 4; }
    else { _layout = 1; }
  });

  // ─── Execute ───
  Future<void> _exec(TPane pane, String cmd) async {
    final c = cmd.trim();
    if (c.isEmpty) return;

    if (pane.history.isEmpty || pane.history.last != c) pane.history.add(c);
    pane.histIdx = pane.history.length;

    // A command is already running — this line is input for it (answers,
    // sudo passwords), not a new command.
    if (pane.busy && pane.proc != null) {
      _sendInput(pane, cmd);
      return;
    }

    setState(() => pane.lines.add(TermLine(
      '\x1B[1;32m${_shortDir(pane.cwd)}\x1B[0m \x1B[1;36m❯\x1B[0m \x1B[97m$c\x1B[0m',
      isCmd: true,
    )));

    // Builtins
    if (c == 'clear' || c == 'cls') { setState(() => pane.lines.clear()); return; }
    if (c == 'cd' || c.startsWith('cd ')) { _cd(pane, c == 'cd' ? '~' : c.substring(3).trim()); return; }
    if (c == 'exit' || c == 'quit') { _removePane(_p.indexOf(pane)); return; }
    if (c == 'newtab' || c == 'split') { _addPane(); return; }
    if (c == 'layout') { _cycleLayout(); return; }
    if (c == 'help') { _showHelp(pane); return; }

    setState(() => pane.busy = true);
    _startProgress(pane.id);

    try {
      // `script` runs the command on a real pseudo-terminal. The old
      // `tmux new-session` wrapper had no TTY to attach to, so every command
      // died with "open terminal failed: not a terminal", and sudo couldn't
      // prompt. -q quiet, -e keep the exit code, -f flush as output arrives.
      pane.proc = await Process.start('script', ['-qefc', c, '/dev/null'],
        workingDirectory: pane.cwd,
        environment: {...Platform.environment, 'TERM': 'xterm-256color', 'COLUMNS': '200', 'LINES': '50'},
      );

      pane.proc!.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen((chunk) {
        if (mounted) setState(() { _emit(pane, chunk); _scrollEnd(pane); });
      });
      pane.proc!.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((chunk) {
        if (mounted) setState(() { _emit(pane, chunk, err: true); _scrollEnd(pane); });
      });

      final code = await pane.proc!.exitCode;
      if (mounted) {
        setState(() {
        _emit(pane, '\n');
        pane.wantsSecret = false;
        pane.proc = null;
        pane.busy = false;
        _stopProgress(pane.id);
        if (code != 0) pane.lines.add(TermLine('\x1B[90m⏎ exit \x1B[31m$code\x1B[0m'));
        _scrollEnd(pane);
      });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
        pane.busy = false;
        _stopProgress(pane.id);
        pane.lines.add(TermLine('\x1B[1;31m✗ $e\x1B[0m', isErr: true));
        _scrollEnd(pane);
      });
      }
    }
  }

  // Terminal control sequences that aren't colors (cursor moves, bracketed
  // paste, window titles) would show up as junk text — drop them.
  static final _nonColorEscapes = RegExp(r'\x1B\[[0-9;?]*[A-Za-ln-z]|\x1B\][^\x07]*(\x07|\x1B\\)|\x1B[()][A-Z0-9]|\x1B[=>]');

  void _emit(TPane pane, String chunk, {bool err = false}) {
    final text = pane.partial + chunk.replaceAll('\r\n', '\n').replaceAll('\r', '').replaceAll(_nonColorEscapes, '');
    final parts = text.split('\n');
    if (pane.partialShown) {
      pane.lines.removeLast();
      pane.partialShown = false;
    }
    for (final line in parts.sublist(0, parts.length - 1)) {
      pane.lines.add(err ? TermLine('\x1B[31m$line\x1B[0m', isErr: true) : TermLine(line));
    }
    pane.partial = parts.last;
    if (pane.partial.isNotEmpty) {
      pane.lines.add(TermLine(pane.partial));
      pane.partialShown = true;
    }
    pane.wantsSecret = RegExp(r'pass(word|phrase)[^:\n]*:\s*$', caseSensitive: false).hasMatch(pane.partial);
  }

  void _sendInput(TPane pane, String text) {
    final secret = pane.wantsSecret;
    pane.proc!.stdin.writeln(text);
    setState(() {
      // Echo what was typed onto the prompt line (masked for passwords).
      _emit(pane, '${secret ? '•' * text.length : text}\n');
      pane.wantsSecret = false;
      _scrollEnd(pane);
    });
  }

  void _cd(TPane pane, String target) {
    String nd;
    if (target == '~') {
      nd = Platform.environment['HOME'] ?? '/';
    } else if (target == '..') { nd = Directory(pane.cwd).parent.path; }
    else if (target.startsWith('/')) { nd = target; }
    else { nd = '${pane.cwd}/$target'; }

    final d = Directory(nd);
    if (d.existsSync()) {
      pane.cwd = d.resolveSymbolicLinksSync();
      setState(() => pane.lines.add(TermLine('\x1B[90m→ ${pane.cwd}\x1B[0m')));
    } else {
      setState(() => pane.lines.add(TermLine('\x1B[31mcd: $target: No such directory\x1B[0m', isErr: true)));
    }
  }

  void _showHelp(TPane pane) {
    setState(() {
      pane.lines.addAll([
        TermLine('\x1B[1;36m── I30LTZ Terminal Commands ──\x1B[0m'),
        TermLine('  \x1B[33mclear\x1B[0m        Clear screen'),
        TermLine('  \x1B[33mcd <dir>\x1B[0m     Change directory'),
        TermLine('  \x1B[33mnewtab\x1B[0m       Open new pane'),
        TermLine('  \x1B[33mlayout\x1B[0m       Cycle 1→2→4 pane view'),
        TermLine('  \x1B[33mexit\x1B[0m         Close pane'),
        TermLine('  \x1B[33mhelp\x1B[0m         This help'),
        TermLine(''),
        TermLine('\x1B[1;36m── Toolbar ──\x1B[0m'),
        TermLine('  \x1B[34mCopy\x1B[0m  \x1B[32mPaste\x1B[0m  \x1B[33mCut\x1B[0m  \x1B[31mKill\x1B[0m  \x1B[90m↑↓ History\x1B[0m'),
        TermLine('  Right-click for context menu'),
        TermLine('  \x1B[36mENTER\x1B[0m button or keyboard to run'),
        TermLine(''),
      ]);
    });
  }

  void _kill(TPane pane) {
    pane.proc?.kill(ProcessSignal.sigint);
    setState(() {
      pane.busy = false;
      _stopProgress(pane.id);
      pane.lines.add(TermLine('\x1B[33m^C\x1B[0m'));
    });
  }

  // ─── Progress Bar ───
  void _startProgress(String id) {
    _progress[id] = 0;
    _progressTimers[id]?.cancel();
    _progressTimers[id] = Timer.periodic(const Duration(milliseconds: 40), (_) {
      if (mounted && _progress.containsKey(id)) {
        setState(() => _progress[id] = (_progress[id]! + 0.008) % 1.0);
      }
    });
  }

  void _stopProgress(String id) {
    _progressTimers[id]?.cancel();
    _progressTimers.remove(id);
    _progress.remove(id);
  }

  void _scrollEnd(TPane pane) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (pane.scroll.hasClients) {
        pane.scroll.jumpTo(pane.scroll.position.maxScrollExtent);
      }
    });
  }

  // ─── Clipboard ───
  void _copy(TPane pane) {
    final last20 = pane.lines.reversed.take(20).toList().reversed;
    final text = last20.map((l) => AnsiParser.strip(l.raw)).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    _clip = text;
    _toast('Copied');
  }

  void _paste(TPane pane) async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) {
      pane.input.text += d!.text!;
      pane.input.selection = TextSelection.fromPosition(TextPosition(offset: pane.input.text.length));
    }
  }

  void _cut(TPane pane) {
    final s = pane.input.selection;
    if (s.isValid && s.start != s.end) {
      _clip = pane.input.text.substring(s.start, s.end);
      Clipboard.setData(ClipboardData(text: _clip));
      pane.input.text = pane.input.text.replaceRange(s.start, s.end, '');
      _toast('Cut');
    }
  }

  void _histUp(TPane pane) {
    if (pane.history.isNotEmpty && pane.histIdx > 0) {
      pane.histIdx--;
      pane.input.text = pane.history[pane.histIdx];
      pane.input.selection = TextSelection.fromPosition(TextPosition(offset: pane.input.text.length));
    }
  }

  void _histDown(TPane pane) {
    if (pane.histIdx < pane.history.length - 1) {
      pane.histIdx++;
      pane.input.text = pane.history[pane.histIdx];
      pane.input.selection = TextSelection.fromPosition(TextPosition(offset: pane.input.text.length));
    } else {
      pane.histIdx = pane.history.length;
      pane.input.clear();
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 11)),
      duration: const Duration(milliseconds: 800),
      backgroundColor: const Color(0xFF2A2A5A),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(12),
    ));
  }

  String _shortDir(String d) {
    final h = Platform.environment['HOME'] ?? '';
    if (h.isNotEmpty && d.startsWith(h)) return '~${d.substring(h.length)}';
    final pts = d.split('/');
    if (pts.length > 3) return '…/${pts[pts.length - 2]}/${pts.last}';
    return d;
  }

  // ═══════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF080816),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [_topBar(), Expanded(child: _paneLayout())]),
    );
  }

  // ─── Tab Bar ───
  Widget _topBar() {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF10102A), Color(0xFF181840)]),
        border: Border(bottom: BorderSide(color: Color(0xFF28285A))),
      ),
      child: Row(children: [
        // Tabs
        ..._p.asMap().entries.map((e) {
          final i = e.key; final pane = e.value; final act = i == _active;
          return GestureDetector(
            onTap: () => setState(() => _active = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              margin: const EdgeInsets.only(right: 2, top: 5, bottom: 5),
              decoration: BoxDecoration(
                color: act ? const Color(0xFF28285A) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: act ? Border.all(color: const Color(0xFF00D4FF).withValues(alpha: 0.4)) : null,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _dot(pane.busy ? const Color(0xFF51CF66) : (act ? const Color(0xFF00D4FF) : const Color(0xFF333355))),
                const SizedBox(width: 5),
                Text(pane.title, style: TextStyle(
                  color: act ? Colors.white : Colors.white30,
                  fontSize: 11, fontWeight: act ? FontWeight.w600 : FontWeight.w400,
                )),
                if (_p.length > 1) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _removePane(i),
                    child: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.15), size: 12),
                  ),
                ],
              ]),
            ),
          );
        }),
        const Spacer(),
        _tbtn(
          _layout == 1 ? Icons.crop_square : (_layout == 2 ? Icons.vertical_split : Icons.grid_view),
          _cycleLayout,
        ),
        if (_p.length < 4) _tbtn(Icons.add, _addPane),
        _tbtn(_toolbar ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, () => setState(() => _toolbar = !_toolbar)),
      ]),
    );
  }

  Widget _dot(Color c) => Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

  Widget _tbtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: Icon(icon, color: Colors.white30, size: 16)),
  );

  // ─── Layout ───
  Widget _paneLayout() {
    if (_layout == 1) return _singlePane(_p[_active], _active);
    if (_layout == 2) {
      final b = (_active + 1) % _p.length;
      return Row(children: [
        Expanded(child: _singlePane(_p[_active], _active)),
        Container(width: 2, color: const Color(0xFF28285A)),
        Expanded(child: _singlePane(_p[b], b)),
      ]);
    }
    while (_p.length < 4) {
      _addPane();
    }
    return Column(children: [
      Expanded(child: Row(children: [
        Expanded(child: _singlePane(_p[0], 0)),
        Container(width: 2, color: const Color(0xFF28285A)),
        Expanded(child: _singlePane(_p[1], 1)),
      ])),
      Container(height: 2, color: const Color(0xFF28285A)),
      Expanded(child: Row(children: [
        Expanded(child: _singlePane(_p[2], 2)),
        Container(width: 2, color: const Color(0xFF28285A)),
        Expanded(child: _singlePane(_p[3], 3)),
      ])),
    ]);
  }

  // ─── Single Pane ───
  Widget _singlePane(TPane pane, int idx) {
    final act = idx == _active;
    return GestureDetector(
      onTap: () => setState(() => _active = idx),
      onSecondaryTapUp: (d) => _ctxMenu(d.globalPosition, pane),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A18),
          border: act && _layout > 1 ? Border.all(color: const Color(0xFF00D4FF).withValues(alpha: 0.15)) : null,
        ),
        child: Column(children: [
          // Progress bar
          if (pane.busy) _loadingBar(pane),
          // Output
          Expanded(child: ListView.builder(
            controller: pane.scroll,
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
            itemCount: pane.lines.length,
            itemBuilder: (_, i) => _line(pane.lines[i]),
          )),
          // Toolbar
          if (_toolbar) _toolRow(pane),
          // Input
          _inputRow(pane),
        ]),
      ),
    );
  }

  // ─── Loading Bar ───
  Widget _loadingBar(TPane pane) {
    return SizedBox(
      height: 3,
      child: CustomPaint(
        painter: _GlowBarPainter(_progress[pane.id] ?? 0, _anim),
        size: Size.infinite,
      ),
    );
  }

  // ─── Line ───
  Widget _line(TermLine l) {
    final fs = (_layout == 4 ? 13.0 : (_layout == 2 ? 15.0 : 17.0)) * _fontScale;
    return Padding(
      padding: const EdgeInsets.only(bottom: 0.5),
      child: SelectableText.rich(TextSpan(
        children: l.spans.map((s) => TextSpan(
          text: s.text,
          style: TextStyle(
            color: s.color,
            backgroundColor: s.bgColor,
            fontWeight: s.bold ? FontWeight.w700 : FontWeight.w400,
            fontStyle: s.italic ? FontStyle.italic : FontStyle.normal,
            decoration: s.underline ? TextDecoration.underline : null,
            fontFamily: 'monospace',
            fontSize: fs,
            height: 1.35,
            letterSpacing: 0.2,
          ),
        )).toList(),
      )),
    );
  }

  // ─── Toolbar ───
  Widget _toolRow(TPane pane) {
    final compact = _layout >= 2;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F24),
        border: Border(top: BorderSide(color: Color(0xFF222250))),
      ),
      child: Row(children: [
        _tb('Copy', Icons.copy, const Color(0xFF74C0FC), () => _copy(pane), compact),
        _tb('Paste', Icons.paste, const Color(0xFF51CF66), () => _paste(pane), compact),
        _tb('Cut', Icons.content_cut, const Color(0xFFFFD43B), () => _cut(pane), compact),
        _divider(),
        _tb('Clear', Icons.layers_clear, const Color(0xFF888888), () => setState(() => pane.lines.clear()), compact),
        if (pane.busy) _tb('Kill', Icons.stop_circle_outlined, const Color(0xFFFF6B6B), () => _kill(pane), compact),
        _divider(),
        _tb('A-', Icons.text_decrease, const Color(0xFFDA77F2), () => _adjustFontScale(-0.1), compact),
        _tb('A+', Icons.text_increase, const Color(0xFFDA77F2), () => _adjustFontScale(0.1), compact),
        const Spacer(),
        _tb('^C', Icons.cancel_outlined, const Color(0xFFFF8787), () { if (pane.busy) _kill(pane); }, compact),
        _tb('Tab', Icons.keyboard_tab, const Color(0xFF777799), () { pane.input.text += '\t'; }, compact),
        _tb('↑', Icons.keyboard_arrow_up, const Color(0xFF777799), () => _histUp(pane), compact),
        _tb('↓', Icons.keyboard_arrow_down, const Color(0xFF777799), () => _histDown(pane), compact),
      ]),
    );
  }

  Widget _tb(String label, IconData icon, Color c, VoidCallback onTap, bool compact) {
    return Tooltip(message: label, child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 7, vertical: 3),
        margin: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: c.withValues(alpha: 0.15)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: c.withValues(alpha: 0.9), size: compact ? 11 : 13),
          if (!compact) ...[const SizedBox(width: 3), Text(label, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w600))],
        ]),
      ),
    ));
  }

  Widget _divider() => Container(width: 1, height: 18, color: const Color(0xFF222250), margin: const EdgeInsets.symmetric(horizontal: 4));

  // ─── Input Row ───
  Widget _inputRow(TPane pane) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 3, 6, 7),
      decoration: const BoxDecoration(
        color: Color(0xFF0C0C1E),
        border: Border(top: BorderSide(color: Color(0xFF1A1A3A))),
      ),
      child: Row(children: [
        // Prompt
        Text(_shortDir(pane.cwd), style: TextStyle(color: const Color(0xFF5B8DEF), fontSize: 13 * _fontScale, fontFamily: 'monospace')),
        Text(pane.busy ? ' ◉ ' : ' ❯ ', style: TextStyle(
          color: pane.busy ? const Color(0xFF51CF66) : const Color(0xFF00D4FF),
          fontSize: 15 * _fontScale, fontWeight: FontWeight.w800, fontFamily: 'monospace',
        )),
        // Input field
        Expanded(child: KeyboardListener(
          focusNode: FocusNode(),
          onKeyEvent: (ev) {
            if (ev is KeyDownEvent) {
              if (ev.logicalKey == LogicalKeyboardKey.arrowUp) _histUp(pane);
              if (ev.logicalKey == LogicalKeyboardKey.arrowDown) _histDown(pane);
              if (HardwareKeyboard.instance.isControlPressed) {
                if (ev.logicalKey == LogicalKeyboardKey.keyC && pane.busy) _kill(pane);
                if (ev.logicalKey == LogicalKeyboardKey.keyL) setState(() => pane.lines.clear());
              }
            }
          },
          child: TextField(
            controller: pane.input,
            focusNode: pane.focus,
            style: TextStyle(color: Colors.white, fontSize: 15 * _fontScale, fontFamily: 'monospace', letterSpacing: 0.3),
            decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
            cursorColor: const Color(0xFF00D4FF),
            cursorWidth: 8,
            cursorHeight: 14,
            obscureText: pane.wantsSecret,
            onSubmitted: (cmd) {
              _exec(pane, cmd);
              pane.input.clear();
              pane.focus.requestFocus();
            },
          ),
        )),
        // ENTER button
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () {
            _exec(pane, pane.input.text);
            pane.input.clear();
            pane.focus.requestFocus();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF00D4FF), Color(0xFF0088BB)]),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [BoxShadow(color: const Color(0xFF00D4FF).withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.keyboard_return, color: Color(0xFF080816), size: 13),
              SizedBox(width: 4),
              Text('ENTER', style: TextStyle(color: Color(0xFF080816), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ─── Right-Click Context Menu ───
  void _ctxMenu(Offset pos, TPane pane) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      color: const Color(0xFF181840),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 16,
      items: [
        _mi('Copy', Icons.copy, 'copy', const Color(0xFF74C0FC)),
        _mi('Paste', Icons.paste, 'paste', const Color(0xFF51CF66)),
        _mi('Cut', Icons.content_cut, 'cut', const Color(0xFFFFD43B)),
        const PopupMenuDivider(),
        _mi('Clear', Icons.layers_clear, 'clear', const Color(0xFF888888)),
        _mi('Select All', Icons.select_all, 'selectall', const Color(0xFF888888)),
        const PopupMenuDivider(),
        _mi('Bigger Text', Icons.text_increase, 'bigger', const Color(0xFFDA77F2)),
        _mi('Smaller Text', Icons.text_decrease, 'smaller', const Color(0xFFDA77F2)),
        const PopupMenuDivider(),
        _mi('New Pane', Icons.add_box_outlined, 'new', const Color(0xFF00D4FF)),
        _mi('Split View', Icons.vertical_split, 'split', const Color(0xFF00D4FF)),
        _mi('Quad View', Icons.grid_view, 'quad', const Color(0xFF00D4FF)),
        if (pane.busy) ...[
          const PopupMenuDivider(),
          _mi('Kill Process', Icons.stop_circle, 'kill', const Color(0xFFFF6B6B)),
        ],
      ],
    ).then((v) {
      if (v == null) return;
      switch (v) {
        case 'copy': _copy(pane);
        case 'paste': _paste(pane);
        case 'cut': _cut(pane);
        case 'clear': setState(() => pane.lines.clear());
        case 'selectall': pane.input.selection = TextSelection(baseOffset: 0, extentOffset: pane.input.text.length);
        case 'bigger': _adjustFontScale(0.1);
        case 'smaller': _adjustFontScale(-0.1);
        case 'new': _addPane();
        case 'split': setState(() => _layout = 2); while (_p.length < 2) {
          _addPane();
        }
        case 'quad': setState(() => _layout = 4); while (_p.length < 4) {
          _addPane();
        }
        case 'kill': _kill(pane);
      }
    });
  }

  PopupMenuItem<String> _mi(String label, IconData icon, String val, Color c) => PopupMenuItem(
    value: val, height: 34,
    child: Row(children: [
      Icon(icon, color: c, size: 15),
      const SizedBox(width: 10),
      Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
    ]),
  );
}

// ─── Custom Painter for Glowing Loading Bar ───
class _GlowBarPainter extends CustomPainter {
  final double progress;
  final Animation<double> anim;

  _GlowBarPainter(this.progress, this.anim) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final barW = w * 0.25;
    final t = (anim.value + progress) % 1.0;
    final x = t * (w + barW) - barW;

    final rect = Rect.fromLTWH(x, 0, barW, size.height);
    final gradient = LinearGradient(colors: [
      const Color(0xFF00D4FF).withValues(alpha: 0.0),
      const Color(0xFF00D4FF),
      const Color(0xFF51CF66),
      const Color(0xFFDA77F2),
      const Color(0xFFDA77F2).withValues(alpha: 0.0),
    ]);
    final paint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);

    // Glow
    final glowPaint = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(x, -2, barW, size.height + 4))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, -1, barW, size.height + 2), const Radius.circular(2)), glowPaint);
  }

  @override
  bool shouldRepaint(covariant _GlowBarPainter old) => true;
}