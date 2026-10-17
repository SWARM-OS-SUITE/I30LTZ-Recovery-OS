import 'package:flutter/material.dart';

class SyntaxToken {
  final String text;
  final Color color;
  final bool bold;
  final bool italic;
  const SyntaxToken(this.text, this.color, {this.bold = false, this.italic = false});
}

// I30LTZ IDE code theme (dark green/cyan)
class _C {
  static const keyword   = Color(0xFFBB86FC); // purple
  static const type      = Color(0xFF82AAFF); // blue
  static const string    = Color(0xFFC3E88D); // green
  static const number    = Color(0xFFF78C6C); // orange
  static const comment   = Color(0xFF546E7A); // muted
  static const func      = Color(0xFF82AAFF); // blue
  static const operator  = Color(0xFF89DDFF); // cyan
  static const punct     = Color(0xFFCDD3DE); // near-white
  static const plain     = Color(0xFFCDD3DE); // default
  static const tag       = Color(0xFFF07178); // red (HTML tags)
  static const attr      = Color(0xFFFFCB6B); // yellow
  static const special   = Color(0xFF76B900); // NVIDIA green
}

abstract class _Highlighter {
  List<TextSpan> highlight(String text);
}

class SyntaxHighlighter {
  static List<TextSpan> highlight(String text, String language) {
    final hl = _getHighlighter(language);
    return hl.highlight(text);
  }

  static _Highlighter _getHighlighter(String lang) => switch (lang) {
        'dart'       => _DartHighlighter(),
        'python'     => _PythonHighlighter(),
        'javascript' || 'typescript' => _JsHighlighter(),
        'kotlin'     => _KotlinHighlighter(),
        'java'       => _JavaHighlighter(),
        'json'       => _JsonHighlighter(),
        'yaml'       => _YamlHighlighter(),
        'shell'      => _ShellHighlighter(),
        'html'       => _HtmlHighlighter(),
        'css'        => _CssHighlighter(),
        'csharp'     => _CsharpHighlighter(),
        'markdown'   => _MarkdownHighlighter(),
        _            => _PlainHighlighter(),
      };
}

class _PlainHighlighter implements _Highlighter {
  @override
  List<TextSpan> highlight(String text) =>
      [TextSpan(text: text, style: const TextStyle(color: _C.plain))];
}

// ─── Dart ───────────────────────────────────────────────────────────────────
class _DartHighlighter implements _Highlighter {
  static const _dartKw = {
    'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case',
    'catch', 'class', 'const', 'continue', 'covariant', 'default', 'deferred',
    'do', 'dynamic', 'else', 'enum', 'export', 'extends', 'extension',
    'external', 'factory', 'false', 'final', 'finally', 'for', 'Function',
    'get', 'hide', 'if', 'implements', 'import', 'in', 'interface', 'is',
    'late', 'library', 'mixin', 'new', 'null', 'on', 'operator', 'part',
    'required', 'rethrow', 'return', 'sealed', 'set', 'show', 'static',
    'super', 'switch', 'sync', 'this', 'throw', 'true', 'try', 'typedef',
    'var', 'void', 'when', 'while', 'with', 'yield',
  };
  static const _dartTypes = {
    'bool', 'double', 'int', 'List', 'Map', 'Never', 'Null', 'num',
    'Object', 'Set', 'String', 'Symbol', 'Type',
  };

  Set<String> get kw => _dartKw;
  Set<String> get types => _dartTypes;

  @override
  List<TextSpan> highlight(String text) => _tokenize(text);

  List<TextSpan> _tokenize(String src) {
    final kw_ = kw;
    final types_ = types;
    final spans = <TextSpan>[];
    int i = 0;
    while (i < src.length) {
      if (i + 1 < src.length && src[i] == '/' && src[i + 1] == '/') {
        final end = src.indexOf('\n', i);
        final comment = end == -1 ? src.substring(i) : src.substring(i, end);
        spans.add(TextSpan(text: comment, style: const TextStyle(color: _C.comment, fontStyle: FontStyle.italic)));
        i = end == -1 ? src.length : end;
        continue;
      }
      if (i + 1 < src.length && src[i] == '/' && src[i + 1] == '*') {
        final end = src.indexOf('*/', i + 2);
        final comment = end == -1 ? src.substring(i) : src.substring(i, end + 2);
        spans.add(TextSpan(text: comment, style: const TextStyle(color: _C.comment, fontStyle: FontStyle.italic)));
        i = end == -1 ? src.length : end + 2;
        continue;
      }
      if (src[i] == '"' || src[i] == "'") {
        final q = src[i];
        int j = i + 1;
        while (j < src.length && src[j] != q) {
          if (src[j] == '\\') j++;
          j++;
        }
        spans.add(TextSpan(text: src.substring(i, j + 1 > src.length ? src.length : j + 1), style: const TextStyle(color: _C.string)));
        i = j + 1 > src.length ? src.length : j + 1;
        continue;
      }
      if (_isDigit(src[i]) || (src[i] == '-' && i + 1 < src.length && _isDigit(src[i + 1]))) {
        int j = i + 1;
        while (j < src.length && (_isDigit(src[j]) || src[j] == '.' || src[j] == 'x' || src[j] == 'e')) {
          j++;
        }
        spans.add(TextSpan(text: src.substring(i, j), style: const TextStyle(color: _C.number)));
        i = j;
        continue;
      }
      if (_isLetter(src[i]) || src[i] == '_') {
        int j = i + 1;
        while (j < src.length && (_isLetter(src[j]) || _isDigit(src[j]) || src[j] == '_')) {
          j++;
        }
        final word = src.substring(i, j);
        Color c;
        if (kw_.contains(word)) {
          c = _C.keyword;
        } else if (types_.contains(word)) {
          c = _C.type;
        } else if (j < src.length && src[j] == '(') {
          c = _C.func;
        } else {
          c = _C.plain;
        }
        spans.add(TextSpan(text: word, style: TextStyle(color: c, fontWeight: kw_.contains(word) ? FontWeight.bold : null)));
        i = j;
        continue;
      }
      final ch = src[i];
      final opColor = '+-*/%=<>&|^~!?:'.contains(ch) ? _C.operator : _C.punct;
      spans.add(TextSpan(text: ch, style: TextStyle(color: opColor)));
      i++;
    }
    return spans;
  }

  bool _isDigit(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;
  bool _isLetter(String c) =>
      (c.compareTo('a') >= 0 && c.compareTo('z') <= 0) ||
      (c.compareTo('A') >= 0 && c.compareTo('Z') <= 0) ||
      c == '_' || c == r'$';
}

// ─── Python ─────────────────────────────────────────────────────────────────
class _PythonHighlighter extends _DartHighlighter {
  static const _pyKw = {
    'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue',
    'def', 'del', 'elif', 'else', 'except', 'False', 'finally', 'for',
    'from', 'global', 'if', 'import', 'in', 'is', 'lambda', 'None',
    'nonlocal', 'not', 'or', 'pass', 'raise', 'return', 'True', 'try',
    'while', 'with', 'yield',
  };
  static const _pyTypes = {'bool', 'bytes', 'dict', 'float', 'int', 'list', 'set', 'str', 'tuple'};
  @override Set<String> get kw => _pyKw;
  @override Set<String> get types => _pyTypes;
}

// ─── JS/TS ──────────────────────────────────────────────────────────────────
class _JsHighlighter extends _DartHighlighter {
  static const _jsKw = {
    'abstract', 'arguments', 'async', 'await', 'break', 'case', 'catch',
    'class', 'const', 'continue', 'debugger', 'default', 'delete', 'do',
    'else', 'enum', 'export', 'extends', 'false', 'finally', 'for',
    'from', 'function', 'if', 'implements', 'import', 'in', 'instanceof',
    'interface', 'let', 'new', 'null', 'of', 'package', 'private',
    'protected', 'public', 'return', 'static', 'super', 'switch', 'this',
    'throw', 'true', 'try', 'type', 'typeof', 'undefined', 'var', 'void',
    'while', 'with', 'yield',
  };
  @override Set<String> get kw => _jsKw;
}

// ─── Kotlin ─────────────────────────────────────────────────────────────────
class _KotlinHighlighter extends _DartHighlighter {
  static const _ktKw = {
    'abstract', 'actual', 'as', 'break', 'by', 'catch', 'class', 'companion',
    'const', 'constructor', 'continue', 'crossinline', 'data', 'do', 'dynamic',
    'else', 'enum', 'expect', 'external', 'false', 'final', 'finally', 'for',
    'fun', 'get', 'if', 'import', 'in', 'infix', 'init', 'inline', 'inner',
    'interface', 'internal', 'is', 'it', 'lateinit', 'noinline', 'null',
    'object', 'open', 'operator', 'out', 'override', 'package', 'private',
    'protected', 'public', 'reified', 'return', 'sealed', 'set', 'super',
    'suspend', 'tailrec', 'this', 'throw', 'true', 'try', 'typealias',
    'typeof', 'val', 'var', 'vararg', 'when', 'where', 'while',
  };
  @override Set<String> get kw => _ktKw;
}

// ─── Java ───────────────────────────────────────────────────────────────────
class _JavaHighlighter extends _DartHighlighter {
  static const _javaKw = {
    'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char',
    'class', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum',
    'extends', 'false', 'final', 'finally', 'float', 'for', 'goto', 'if',
    'implements', 'import', 'instanceof', 'int', 'interface', 'long', 'native',
    'new', 'null', 'package', 'private', 'protected', 'public', 'return',
    'short', 'static', 'strictfp', 'super', 'switch', 'synchronized', 'this',
    'throw', 'throws', 'transient', 'true', 'try', 'var', 'void', 'volatile', 'while',
  };
  @override Set<String> get kw => _javaKw;
}

// ─── C# ─────────────────────────────────────────────────────────────────────
class _CsharpHighlighter extends _DartHighlighter {
  static const _csKw = {
    'abstract', 'as', 'async', 'await', 'base', 'bool', 'break', 'byte',
    'case', 'catch', 'char', 'checked', 'class', 'const', 'continue',
    'decimal', 'default', 'delegate', 'do', 'double', 'else', 'enum',
    'event', 'explicit', 'extern', 'false', 'finally', 'fixed', 'float',
    'for', 'foreach', 'goto', 'if', 'implicit', 'in', 'int', 'interface',
    'internal', 'is', 'lock', 'long', 'namespace', 'new', 'null', 'object',
    'operator', 'out', 'override', 'params', 'private', 'protected', 'public',
    'readonly', 'ref', 'return', 'sbyte', 'sealed', 'short', 'sizeof',
    'stackalloc', 'static', 'string', 'struct', 'switch', 'this', 'throw',
    'true', 'try', 'typeof', 'uint', 'ulong', 'unchecked', 'unsafe', 'ushort',
    'using', 'virtual', 'void', 'volatile', 'while', 'var', 'dynamic',
  };
  @override Set<String> get kw => _csKw;
}

// ─── JSON ───────────────────────────────────────────────────────────────────
class _JsonHighlighter implements _Highlighter {
  @override
  List<TextSpan> highlight(String text) {
    final spans = <TextSpan>[];
    final re = RegExp(r'"((?:[^"\\]|\\.)*)"\s*:|"((?:[^"\\]|\\.)*)"|(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)|true|false|null|[{}[\],:]');
    int last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start), style: const TextStyle(color: _C.plain)));
      final matched = m.group(0)!;
      Color c;
      if (m.group(1) != null) {
        c = _C.attr;
      } else if (m.group(2) != null) {
        c = _C.string;
      } else if (m.group(3) != null) {
        c = _C.number;
      } else if (matched == 'true' || matched == 'false') {
        c = _C.keyword;
      } else if (matched == 'null') {
        c = _C.type;
      } else {
        c = _C.punct;
      }
      spans.add(TextSpan(text: matched, style: TextStyle(color: c)));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last), style: const TextStyle(color: _C.plain)));
    return spans;
  }
}

// ─── YAML ───────────────────────────────────────────────────────────────────
class _YamlHighlighter implements _Highlighter {
  @override
  List<TextSpan> highlight(String text) {
    final lines = text.split('\n');
    final spans = <TextSpan>[];
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (i > 0) spans.add(const TextSpan(text: '\n'));
      if (line.trimLeft().startsWith('#')) {
        spans.add(TextSpan(text: line, style: const TextStyle(color: _C.comment, fontStyle: FontStyle.italic)));
        continue;
      }
      final colonIdx = line.indexOf(':');
      if (colonIdx > 0) {
        spans.add(TextSpan(text: line.substring(0, colonIdx), style: const TextStyle(color: _C.attr)));
        spans.add(TextSpan(text: ':${line.substring(colonIdx + 1)}', style: const TextStyle(color: _C.plain)));
      } else {
        spans.add(TextSpan(text: line, style: const TextStyle(color: _C.plain)));
      }
    }
    return spans;
  }
}

// ─── Shell ──────────────────────────────────────────────────────────────────
class _ShellHighlighter implements _Highlighter {
  @override
  List<TextSpan> highlight(String text) {
    final lines = text.split('\n');
    final spans = <TextSpan>[];
    const cmds = {'echo', 'cd', 'ls', 'cp', 'mv', 'rm', 'mkdir', 'chmod', 'chown', 'grep', 'find', 'sed', 'awk', 'curl', 'wget', 'git', 'sudo', 'apt', 'pacman', 'pip', 'npm', 'yarn'};
    for (int i = 0; i < lines.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: '\n'));
      final line = lines[i];
      if (line.trimLeft().startsWith('#')) {
        spans.add(TextSpan(text: line, style: const TextStyle(color: _C.comment, fontStyle: FontStyle.italic)));
        continue;
      }
      final parts = line.split(' ');
      if (parts.isNotEmpty && cmds.contains(parts[0])) {
        spans.add(TextSpan(text: parts[0], style: const TextStyle(color: _C.keyword, fontWeight: FontWeight.bold)));
        if (parts.length > 1) spans.add(TextSpan(text: ' ${parts.sublist(1).join(' ')}', style: const TextStyle(color: _C.plain)));
      } else {
        spans.add(TextSpan(text: line, style: const TextStyle(color: _C.plain)));
      }
    }
    return spans;
  }
}

// ─── HTML ───────────────────────────────────────────────────────────────────
class _HtmlHighlighter implements _Highlighter {
  @override
  List<TextSpan> highlight(String text) {
    final spans = <TextSpan>[];
    final re = RegExp(r'<!--[\s\S]*?-->|<(/?\w+)([^>]*)>|"[^"]*"|&\w+;');
    int last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start), style: const TextStyle(color: _C.plain)));
      final matched = m.group(0)!;
      if (matched.startsWith('<!--')) {
        spans.add(TextSpan(text: matched, style: const TextStyle(color: _C.comment, fontStyle: FontStyle.italic)));
      } else if (m.group(1) != null) {
        spans.add(const TextSpan(text: '<', style: TextStyle(color: _C.punct)));
        spans.add(TextSpan(text: m.group(1)!, style: const TextStyle(color: _C.tag)));
        if (m.group(2)!.isNotEmpty) spans.add(TextSpan(text: m.group(2)!, style: const TextStyle(color: _C.attr)));
        spans.add(const TextSpan(text: '>', style: TextStyle(color: _C.punct)));
      } else if (matched.startsWith('"')) {
        spans.add(TextSpan(text: matched, style: const TextStyle(color: _C.string)));
      } else {
        spans.add(TextSpan(text: matched, style: const TextStyle(color: _C.special)));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last), style: const TextStyle(color: _C.plain)));
    return spans;
  }
}

// ─── CSS ────────────────────────────────────────────────────────────────────
class _CssHighlighter implements _Highlighter {
  @override
  List<TextSpan> highlight(String text) {
    final spans = <TextSpan>[];
    final re = RegExp(r'''/\*[\s\S]*?\*/|([a-zA-Z-]+)\s*:|#[0-9a-fA-F]{3,6}|\d+(?:px|em|rem|%|vh|vw|pt|s|ms)?|"[^"]*"''');
    int last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start), style: const TextStyle(color: _C.plain)));
      final matched = m.group(0)!;
      if (matched.startsWith('/*')) {
        spans.add(TextSpan(text: matched, style: const TextStyle(color: _C.comment)));
      } else if (m.group(1) != null) {
        spans.add(TextSpan(text: matched, style: const TextStyle(color: _C.attr)));
      } else if (matched.startsWith('#')) {
        spans.add(TextSpan(text: matched, style: const TextStyle(color: _C.string)));
      } else if (matched.startsWith('"') || matched.startsWith("'")) {
        spans.add(TextSpan(text: matched, style: const TextStyle(color: _C.string)));
      } else {
        spans.add(TextSpan(text: matched, style: const TextStyle(color: _C.number)));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last), style: const TextStyle(color: _C.plain)));
    return spans;
  }
}

// ─── Markdown ───────────────────────────────────────────────────────────────
class _MarkdownHighlighter implements _Highlighter {
  @override
  List<TextSpan> highlight(String text) {
    final lines = text.split('\n');
    final spans = <TextSpan>[];
    for (int i = 0; i < lines.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: '\n'));
      final line = lines[i];
      if (line.startsWith('# ')) {
        spans.add(TextSpan(text: line, style: const TextStyle(color: _C.keyword, fontWeight: FontWeight.bold, fontSize: 18)));
      } else if (line.startsWith('## ')) {
        spans.add(TextSpan(text: line, style: const TextStyle(color: _C.type, fontWeight: FontWeight.bold, fontSize: 16)));
      } else if (line.startsWith('### ')) {
        spans.add(TextSpan(text: line, style: const TextStyle(color: _C.func, fontWeight: FontWeight.bold)));
      } else if (line.startsWith('> ')) {
        spans.add(TextSpan(text: line, style: const TextStyle(color: _C.comment, fontStyle: FontStyle.italic)));
      } else if (line.startsWith('- ') || line.startsWith('* ') || RegExp(r'^\d+\. ').hasMatch(line)) {
        spans.add(TextSpan(text: line, style: const TextStyle(color: _C.plain)));
      } else if (line.startsWith('```')) {
        spans.add(TextSpan(text: line, style: const TextStyle(color: _C.string)));
      } else {
        spans.add(TextSpan(text: line, style: const TextStyle(color: _C.plain)));
      }
    }
    return spans;
  }
}
