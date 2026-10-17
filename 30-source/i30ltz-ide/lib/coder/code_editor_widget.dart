import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/swarm_colors.dart';
import 'editor_model.dart';
import 'syntax_highlighter.dart';
import 'intellisense/completion_provider.dart';
import 'intellisense/completion_overlay.dart';
import 'folding.dart';
import 'accessibility.dart';
import '../services/git_lens_service.dart';

// ─── Syntax-highlighting TextEditingController ───────────────────────────────
class _SyntaxController extends TextEditingController {
  String language;
  _SyntaxController(String text, {required this.language}) : super(text: text);

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final spans = SyntaxHighlighter.highlight(text, language);
    return TextSpan(style: style, children: spans);
  }
}

// ─── Main Code Editor ─────────────────────────────────────────────────────────
class CodeEditorWidget extends StatefulWidget {
  final OpenFile file;
  final String? workspacePath;
  final ValueChanged<String>? onChanged;
  final ValueChanged<(int line, int col)>? onCursorMoved;
  final ValueChanged<GitBlameInfo?>? onBlameUpdated;
  final int? targetLine;

  const CodeEditorWidget({
    super.key,
    required this.file,
    this.workspacePath,
    this.onChanged,
    this.onCursorMoved,
    this.onBlameUpdated,
    this.targetLine,
  });

  @override
  State<CodeEditorWidget> createState() => _CodeEditorWidgetState();
}

class _CodeEditorWidgetState extends State<CodeEditorWidget> {
  late _SyntaxController _controller;
  late ScrollController _vertScroll;
  late ScrollController _lineScroll;
  late FocusNode _focusNode;
  late CompletionController _completionCtrl;
  final _provider = CompletionProvider();

  // Hover state
  String? _hoverSymbol;
  String? _hoverDoc;
  Offset _hoverPos = Offset.zero;

  // Folding
  final _foldManager = FoldManager();
  List<FoldRegion> _foldRegions = [];

  // GitLens State
  Map<int, GitGutterMarker> _gutterMarkers = {};
  Map<int, GitBlameInfo> _blameInfo = {};
  GitBlameInfo? _currentLineBlame;
  int _currentCursorLine = 1;
  final bool _showGitLens = true;

  // Layout key for cursor position calculation
  final _editorKey = GlobalKey();

  // Dynamic from AccessibilitySettings
  double get _fontSize => AccessibilitySettings.instance.fontSize;
  double get _lineHeight => AccessibilitySettings.instance.lineHeight;
  static const _lineNumWidth = 52.0;

  @override
  void initState() {
    super.initState();
    _controller = _SyntaxController(widget.file.content, language: widget.file.language ?? 'plain');
    _vertScroll = ScrollController();
    _lineScroll = ScrollController();
    _focusNode = FocusNode();
    _controller.addListener(_onTextChanged);
    _foldRegions = FoldManager.detectRegions(widget.file.content);
    AccessibilitySettings.instance.addListener(_onA11yChanged);
    _vertScroll.addListener(() {
      if (_lineScroll.hasClients) _lineScroll.jumpTo(_vertScroll.offset);
    });
    _loadGitLensData();
  }

  @override
  void didUpdateWidget(CodeEditorWidget old) {
    super.didUpdateWidget(old);
    if (old.file.path != widget.file.path) {
      _completionCtrl.dismiss();
      _controller.removeListener(_onTextChanged);
      _controller.dispose();
      _controller = _SyntaxController(widget.file.content, language: widget.file.language ?? 'plain');
      _controller.addListener(_onTextChanged);
      _loadGitLensData();
    }
    if (widget.targetLine != null && widget.targetLine != old.targetLine) {
      _scrollToLine(widget.targetLine!);
    }
  }

  void _scrollToLine(int line) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_vertScroll.hasClients) return;
      final offset = ((line - 1) * _lineHeight).clamp(0.0, _vertScroll.position.maxScrollExtent);
      _vertScroll.animateTo(offset, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  Future<void> _loadGitLensData() async {
    final path = widget.file.path;
    final cwd = widget.workspacePath;
    final gutter = await GitLensService.instance.getGutterDiff(path, cwd: cwd);
    final blame = await GitLensService.instance.getBlameForFile(path, cwd: cwd);
    if (mounted) {
      setState(() {
        _gutterMarkers = gutter;
        _blameInfo = blame;
        _currentLineBlame = blame[_currentCursorLine];
      });
      widget.onBlameUpdated?.call(_currentLineBlame);
    }
  }

  void _updateLineBlame(int line) {
    _currentCursorLine = line;
    final b = _blameInfo[line];
    if (b != _currentLineBlame) {
      setState(() => _currentLineBlame = b);
      widget.onBlameUpdated?.call(b);
    }
  }

  void _onA11yChanged() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    AccessibilitySettings.instance.removeListener(_onA11yChanged);
    _completionCtrl.dismiss();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _vertScroll.dispose();
    _lineScroll.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final overlay = Overlay.of(context);
    _completionCtrl = CompletionController(overlay);
  }

  // ── Text changes ─────────────────────────────────────────────────────────

  void _onTextChanged() {
    final pos = _controller.selection.baseOffset;
    if (pos >= 0 && pos <= _controller.text.length) {
      final before = _controller.text.substring(0, pos);
      final line = '\n'.allMatches(before).length;
      final col = before.length - (before.lastIndexOf('\n') + 1);
      widget.onCursorMoved?.call((line + 1, col + 1));
      _updateLineBlame(line + 1);
    }

    if (widget.file.content != _controller.text) {
      widget.file.content = _controller.text;
      widget.file.isDirty = true;
      widget.onChanged?.call(_controller.text);
      _foldRegions = FoldManager.detectRegions(_controller.text);
      if (pos >= 0 && pos <= _controller.text.length) {
        final before = _controller.text.substring(0, pos);
        _triggerCompletion(before, pos);
      }
    }
    if (mounted) setState(() {});
  }

  void _toggleFold(int displayLine) {
    setState(() {
      if (_foldManager.isFolded(displayLine)) {
        // Unfold
        final newText = _foldManager.unfold(_controller.text, displayLine);
        _controller.value = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: _controller.selection.baseOffset.clamp(0, newText.length)));
      } else {
        // Fold
        final region = FoldManager.regionStartingAt(_foldRegions, displayLine);
        if (region == null) return;
        final newText = _foldManager.fold(_controller.text, region);
        if (newText != _controller.text) {
          _controller.value = TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: _controller.selection.baseOffset.clamp(0, newText.length)));
        }
      }
      _foldRegions = FoldManager.detectRegions(_controller.text);
    });
  }

  void _triggerCompletion(String before, int pos) {
    // Extract the current word prefix being typed
    final wordMatch = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*$').firstMatch(before);
    if (wordMatch == null || wordMatch.group(0)!.isEmpty) {
      _completionCtrl.dismiss();
      return;
    }
    final prefix = wordMatch.group(0)!;
    final items = _provider.getCompletions(widget.file, prefix, _controller.text);
    if (items.isEmpty) { _completionCtrl.dismiss(); return; }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cursorOffset = _estimateCursorOffset(pos, before);
      _completionCtrl.show(
        items: items,
        position: cursorOffset,
        onAccept: (item) => _acceptCompletion(item, prefix),
        onDismiss: () => _focusNode.requestFocus(),
      );
    });
  }

  void _acceptCompletion(CompletionItem item, String currentPrefix) {
    final pos = _controller.selection.baseOffset;
    if (pos < 0) return;
    final text = _controller.text;
    final before = text.substring(0, pos - currentPrefix.length);
    final after = text.substring(pos);
    final newText = before + item.insertText + after;
    final newPos = before.length + item.insertText.length;
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newPos),
    );
    _focusNode.requestFocus();
  }

  Offset _estimateCursorOffset(int pos, String before) {
    final lines = before.split('\n');
    final lineNum = lines.length - 1;
    final col = lines.last.length;
    // Approximate: each char ~8.1px wide, each line 20px tall
    final renderBox = _editorKey.currentContext?.findRenderObject() as RenderBox?;
    final editorOrigin = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    return Offset(
      editorOrigin.dx + _lineNumWidth + 12 + col * 8.1,
      editorOrigin.dy + 8 + (lineNum + 1) * _lineHeight - _vertScroll.offset,
    );
  }

  // ── Hover on mouse hover ─────────────────────────────────────────────────

  void _onHover(PointerHoverEvent event) {
    final pos = event.localPosition;
    final col = ((pos.dx - _lineNumWidth - 12) / 8.1).round();
    final line = ((pos.dy + _vertScroll.offset - 8) / _lineHeight).floor();
    final lines = _controller.text.split('\n');
    if (line < 0 || line >= lines.length) { _clearHover(); return; }
    final lineText = lines[line];
    if (col < 0 || col >= lineText.length) { _clearHover(); return; }
    // Extract word at hover point
    int start = col, end = col;
    while (start > 0 && _isWordChar(lineText[start - 1])) {
      start--;
    }
    while (end < lineText.length && _isWordChar(lineText[end])) {
      end++;
    }
    if (start == end) { _clearHover(); return; }
    final word = lineText.substring(start, end);
    final doc = HoverProvider.getHover(word);
    if (doc != null && word != _hoverSymbol) {
      setState(() { _hoverSymbol = word; _hoverDoc = doc; _hoverPos = event.position; });
    } else if (doc == null) {
      _clearHover();
    }
  }

  void _clearHover() {
    if (_hoverSymbol != null) setState(() { _hoverSymbol = null; _hoverDoc = null; });
  }

  bool _isWordChar(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || (code >= 48 && code <= 57) || c == '_';
  }

  // ── Keyboard shortcuts ───────────────────────────────────────────────────

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;

    // Ctrl+Click / F12 → go-to-definition
    if (ctrl && event.logicalKey == LogicalKeyboardKey.f12 ||
        event.logicalKey == LogicalKeyboardKey.f12) {
      _goToDefinition();
      return KeyEventResult.handled;
    }
    // Tab completion when popup is open is handled in overlay
    // Tab → insert spaces
    if (event.logicalKey == LogicalKeyboardKey.tab && !_completionCtrl.isOpen) {
      final pos = _controller.selection.baseOffset;
      if (pos >= 0) {
        final text = _controller.text;
        _controller.value = TextEditingValue(
          text: '${text.substring(0, pos)}  ${text.substring(pos)}',
          selection: TextSelection.collapsed(offset: pos + 2),
        );
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _goToDefinition() async {
    final pos = _controller.selection.baseOffset;
    if (pos < 0) return;
    final before = _controller.text.substring(0, pos);
    final wordMatch = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*$').firstMatch(before);
    if (wordMatch == null) return;
    final symbol = wordMatch.group(0)!;
    final result = await DefinitionProvider.findDefinition(symbol, widget.workspacePath);
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Definition: ${result.$1.split('/').last}:${result.$2}'),
        duration: const Duration(seconds: 3),
        backgroundColor: SwarmColors.bgElevated,
        action: SnackBarAction(label: 'OPEN', textColor: SwarmColors.accent, onPressed: () {}),
      ));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  int get _lineCount => _controller.text.split('\n').length;

  Widget _buildLineNumbers() {
    final regionStarts = {for (final r in _foldRegions) r.startLine};
    return SizedBox(
      width: _lineNumWidth,
      child: ListView.builder(
        controller: _lineScroll,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8),
        itemCount: _lineCount,
        itemExtent: _lineHeight,
        itemBuilder: (_, i) {
          final lineNum = i + 1;
          final isFolded = _foldManager.isFolded(i);
          final isFoldable = regionStarts.contains(i) && !isFolded;
          final hasChevron = isFolded || isFoldable;
          final gutter = _gutterMarkers[lineNum];

          Color? gutterColor;
          if (gutter != null) {
            switch (gutter.type) {
              case GitGutterType.added:
                gutterColor = SwarmColors.agentEmerald;
                break;
              case GitGutterType.modified:
                gutterColor = SwarmColors.agentCyan;
                break;
              case GitGutterType.deleted:
                gutterColor = SwarmColors.agentRose;
                break;
            }
          }

          return Row(children: [
            Container(
              width: 3,
              height: _lineHeight,
              color: gutterColor ?? Colors.transparent,
            ),
            const SizedBox(width: 2),
            SizedBox(
              width: 14,
              child: hasChevron
                  ? GestureDetector(
                      onTap: () => _toggleFold(i),
                      child: Icon(isFolded ? Icons.chevron_right : Icons.expand_more, size: 12, color: SwarmColors.textDisabled),
                    )
                  : null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text('${i + 1}', textAlign: TextAlign.right, style: TextStyle(fontFamily: 'monospace', fontSize: _fontSize - 1.5, height: 1.0, color: isFolded ? SwarmColors.agentAmber.withValues(alpha: 0.7) : SwarmColors.textDisabled)),
              ),
            ),
          ]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          key: _editorKey,
          color: SwarmColors.bg,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Line numbers
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF0F0C1F),
                  border: Border(right: BorderSide(color: SwarmColors.border, width: 1)),
                ),
                child: _buildLineNumbers(),
              ),
              // Code area
              Expanded(
                child: MouseRegion(
                  onHover: _onHover,
                  onExit: (_) => _clearHover(),
                  child: Focus(
                    onKeyEvent: _handleKey,
                    child: Scrollbar(
                      controller: _vertScroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _vertScroll,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: IntrinsicWidth(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              maxLines: null,
                              expands: false,
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.fromLTRB(12, 8, 12, 8),
                                isDense: true,
                              ),
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: _fontSize,
                                height: _lineHeight / _fontSize,
                                color: SwarmColors.textPrimary,
                                letterSpacing: 0.3,
                              ),
                              cursorColor: SwarmColors.accent,
                              cursorWidth: 1.5,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Hover doc tooltip
        if (_hoverSymbol != null && _hoverDoc != null)
          HoverDocTooltip(symbol: _hoverSymbol!, documentation: _hoverDoc!, position: _hoverPos),

        // GitLens In-Editor Blame Capsule
        if (_showGitLens && _currentLineBlame != null)
          Positioned(
            top: 8,
            right: 20,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showBlameDetailsModal(_currentLineBlame!),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xEE161B26),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: SwarmColors.border),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.commit_rounded, size: 12, color: SwarmColors.agentCyan),
                      const SizedBox(width: 5),
                      Text(
                        _currentLineBlame!.inlineAnnotation,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: SwarmColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.info_outline, size: 10, color: SwarmColors.textMuted),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showBlameDetailsModal(GitBlameInfo blame) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F141F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: SwarmColors.border),
        ),
        title: Row(
          children: [
            const Icon(Icons.history_edu_rounded, size: 18, color: SwarmColors.agentCyan),
            const SizedBox(width: 8),
            const Text(
              'GitLens Commit Inspector',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: SwarmColors.textMuted),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B26),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: SwarmColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: SwarmColors.agentCyan.withValues(alpha: 0.2),
                          child: Text(
                            blame.author.isNotEmpty ? blame.author[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: SwarmColors.agentCyan),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(blame.author, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 12)),
                        if (blame.authorMail.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text('<${blame.authorMail}>', style: const TextStyle(fontSize: 11, color: SwarmColors.textMuted)),
                        ],
                        const Spacer(),
                        Text(blame.timeAgo, style: const TextStyle(fontSize: 11, color: SwarmColors.agentEmerald)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      blame.summary,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: SwarmColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text('Commit: ${blame.shortHash}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: SwarmColors.agentCyan)),
                        const Spacer(),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: blame.hash));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Commit hash copied to clipboard'), duration: Duration(seconds: 2)),
                            );
                          },
                          child: const Row(
                            children: [
                              Icon(Icons.copy, size: 12, color: SwarmColors.textMuted),
                              SizedBox(width: 4),
                              Text('Copy SHA', style: TextStyle(fontSize: 10.5, color: SwarmColors.textMuted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      final diff = await GitLensService.instance.getCommitDiff(blame.hash, cwd: widget.workspacePath);
                      if (context.mounted) {
                        _showCommitDiffDialog(blame.shortHash, diff);
                      }
                    },
                    icon: const Icon(Icons.compare, size: 14, color: SwarmColors.agentCyan),
                    label: const Text('View Full Diff', style: TextStyle(fontSize: 12, color: SwarmColors.agentCyan)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCommitDiffDialog(String shortHash, String diff) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F141F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: SwarmColors.border),
        ),
        title: Row(
          children: [
            const Icon(Icons.compare_arrows, size: 18, color: SwarmColors.agentCyan),
            const SizedBox(width: 8),
            Text('Commit Diff [$shortHash]', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: SwarmColors.textMuted),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
        content: SizedBox(
          width: 700,
          height: 480,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF080B12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: SwarmColors.border),
            ),
            child: SingleChildScrollView(
              child: SelectableText.rich(
                TextSpan(
                  children: diff.split('\n').map((line) {
                    Color c = SwarmColors.textSecondary;
                    if (line.startsWith('+')) c = SwarmColors.agentEmerald;
                    if (line.startsWith('-')) c = SwarmColors.agentRose;
                    if (line.startsWith('@@')) c = SwarmColors.agentCyan;
                    if (line.startsWith('diff') || line.startsWith('index') || line.startsWith('+++') || line.startsWith('---')) c = SwarmColors.textMuted;
                    return TextSpan(
                      text: '$line\n',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: c),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Save helper ─────────────────────────────────────────────────────────────
Future<void> saveFile(OpenFile file) async {
  try {
    await File(file.path).writeAsString(file.content);
    file.isDirty = false;
  } catch (_) {}
}
