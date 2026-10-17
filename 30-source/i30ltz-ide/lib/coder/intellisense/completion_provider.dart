import 'dart:io';
import '../editor_model.dart';
import '../panels/snippets_panel.dart';

// ─── Completion Item ─────────────────────────────────────────────────────────
class CompletionItem {
  final String label;
  final CompletionKind kind;
  final String? detail;
  final String? documentation;
  final String insertText;

  const CompletionItem({
    required this.label,
    required this.kind,
    this.detail,
    this.documentation,
    String? insertText,
  }) : insertText = insertText ?? label;
}

enum CompletionKind { keyword, type, function, variable, snippet, field, property, module }

// ─── Provider ────────────────────────────────────────────────────────────────
class CompletionProvider {
  static const _dartKw = [
    'abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case',
    'catch', 'class', 'const', 'continue', 'covariant', 'default', 'do',
    'else', 'enum', 'export', 'extends', 'extension', 'factory', 'false',
    'final', 'finally', 'for', 'Function', 'get', 'if', 'implements', 'import',
    'in', 'interface', 'is', 'late', 'library', 'mixin', 'new', 'null',
    'on', 'operator', 'part', 'required', 'return', 'sealed', 'set', 'static',
    'super', 'switch', 'this', 'throw', 'true', 'try', 'typedef', 'var',
    'void', 'when', 'while', 'with', 'yield',
  ];

  static const _dartTypes = [
    'bool', 'double', 'int', 'List', 'Map', 'Never', 'Null', 'num', 'Object',
    'Set', 'String', 'Symbol', 'Type', 'dynamic', 'Future', 'Stream',
    'Iterable', 'Duration', 'DateTime', 'Uri',
  ];

  static const _dartSnippets = [
    ('stless', 'class \${1:Name} extends StatelessWidget {\n  const \${1:Name}({super.key});\n\n  @override\n  Widget build(BuildContext context) {\n    return \${2:Container()};\n  }\n}', 'StatelessWidget'),
    ('stful', 'class \${1:Name} extends StatefulWidget {\n  const \${1:Name}({super.key});\n\n  @override\n  State<\${1:Name}> createState() => _\${1:Name}State();\n}\n\nclass _\${1:Name}State extends State<\${1:Name}> {\n  @override\n  Widget build(BuildContext context) {\n    return \${2:Container()};\n  }\n}', 'StatefulWidget'),
    ('override', '@override\n\${1:void method()} {\n  super.\${1:method}();\n}', '@override method'),
    ('initstate', '@override\nvoid initState() {\n  super.initState();\n  \$0\n}', 'initState'),
    ('dispose', '@override\nvoid dispose() {\n  \$0\n  super.dispose();\n}', 'dispose'),
    ('build', '@override\nWidget build(BuildContext context) {\n  return \${1:Container()};\n}', 'build'),
    ('print', "print('\${1:message}');", 'print'),
    ('setState', 'setState(() {\n  \$0\n});', 'setState'),
    ('asyncfn', 'Future<\${1:void}> \${2:name}() async {\n  \$0\n}', 'async function'),
    ('tryCatch', 'try {\n  \$0\n} catch (e) {\n  debugPrint(e.toString());\n}', 'try/catch'),
    ('ifnull', '\${1:value} ?? \${2:default}', 'null coalescing'),
  ];

  static const _flutterWidgets = [
    'Container', 'Row', 'Column', 'Stack', 'Expanded', 'Flexible', 'Padding',
    'Center', 'SizedBox', 'Text', 'Icon', 'Image', 'Scaffold', 'AppBar',
    'ListView', 'GridView', 'SingleChildScrollView', 'InkWell', 'GestureDetector',
    'Material', 'Card', 'Divider', 'TextField', 'TextFormField', 'ElevatedButton',
    'TextButton', 'IconButton', 'FloatingActionButton', 'Drawer', 'BottomNavigationBar',
    'TabBar', 'TabBarView', 'Dialog', 'AlertDialog', 'SnackBar', 'Tooltip',
    'CircularProgressIndicator', 'LinearProgressIndicator', 'Checkbox', 'Switch',
    'Slider', 'DropdownButton', 'PopupMenuButton', 'Navigator', 'AnimatedContainer',
    'FutureBuilder', 'StreamBuilder', 'Builder', 'LayoutBuilder', 'MediaQuery',
    'Theme', 'DefaultTextStyle', 'Opacity', 'Transform', 'ClipRRect', 'DecoratedBox',
    'CustomPaint', 'RichText', 'TextSpan', 'BorderRadius', 'BoxDecoration',
    'EdgeInsets', 'Colors', 'Icons', 'MaterialApp', 'WidgetsApp',
  ];

  static const _pyKw = [
    'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue',
    'def', 'del', 'elif', 'else', 'except', 'False', 'finally', 'for',
    'from', 'global', 'if', 'import', 'in', 'is', 'lambda', 'None',
    'nonlocal', 'not', 'or', 'pass', 'raise', 'return', 'True', 'try',
    'while', 'with', 'yield', 'print', 'len', 'range', 'enumerate', 'zip',
    'map', 'filter', 'list', 'dict', 'set', 'tuple', 'str', 'int', 'float',
    'bool', 'type', 'isinstance', 'hasattr', 'getattr', 'setattr', 'open',
    'super', 'self', 'cls',
  ];

  static const _jsKw = [
    'async', 'await', 'break', 'case', 'catch', 'class', 'const', 'continue',
    'default', 'delete', 'do', 'else', 'export', 'extends', 'false', 'finally',
    'for', 'from', 'function', 'if', 'import', 'in', 'instanceof', 'let',
    'new', 'null', 'of', 'return', 'static', 'super', 'switch', 'this',
    'throw', 'true', 'try', 'typeof', 'undefined', 'var', 'void', 'while',
    'yield', 'console', 'document', 'window', 'Promise', 'Array', 'Object',
    'JSON', 'Math', 'Date', 'Error', 'setTimeout', 'setInterval', 'fetch',
    'addEventListener', 'querySelector', 'getElementById',
  ];

  static const _ktKw = [
    'abstract', 'as', 'break', 'by', 'catch', 'class', 'companion', 'const',
    'continue', 'data', 'do', 'else', 'enum', 'false', 'final', 'finally',
    'for', 'fun', 'if', 'import', 'in', 'interface', 'internal', 'is',
    'lateinit', 'null', 'object', 'open', 'operator', 'override', 'package',
    'private', 'protected', 'public', 'return', 'sealed', 'super', 'suspend',
    'this', 'throw', 'true', 'try', 'typealias', 'val', 'var', 'when', 'while',
    'Activity', 'Fragment', 'Intent', 'Bundle', 'Context', 'View', 'ViewGroup',
    'RecyclerView', 'TextView', 'Button', 'ImageView', 'ConstraintLayout',
    'LinearLayout', 'FrameLayout', 'Log', 'Toast', 'Snackbar', 'ViewModel',
    'LiveData', 'StateFlow', 'Coroutine', 'launch', 'async', 'withContext',
    'Dispatchers', 'Room', 'Retrofit', 'Hilt', 'Compose',
  ];

  // Cache of loaded custom snippets — refreshed per file open via loadCustomSnippets()
  static List<CustomSnippet> _customSnippets = [];
  static Future<void> loadCustomSnippets() async {
    _customSnippets = await SnippetStorage.load();
  }

  List<CompletionItem> getCompletions(OpenFile file, String prefix, String fullText) {
    if (prefix.isEmpty) return [];
    final lower = prefix.toLowerCase();
    final items = <CompletionItem>[];

    // Language-specific keywords
    final keywords = _keywordsForLang(file.language ?? 'plain');
    for (final kw in keywords) {
      if (kw.toLowerCase().startsWith(lower)) {
        items.add(CompletionItem(label: kw, kind: CompletionKind.keyword));
      }
    }

    // Flutter widgets for Dart
    if (file.language == 'dart') {
      for (final w in _flutterWidgets) {
        if (w.toLowerCase().startsWith(lower)) {
          items.add(CompletionItem(label: w, kind: CompletionKind.type, detail: 'Widget'));
        }
      }
      // Snippets
      for (final (trigger, insert, desc) in _dartSnippets) {
        if (trigger.startsWith(lower)) {
          items.add(CompletionItem(label: trigger, kind: CompletionKind.snippet, detail: desc, insertText: insert));
        }
      }
    }

    // Custom snippets from SnippetStorage
    final lang = file.language ?? 'plain';
    for (final cs in _customSnippets) {
      if (cs.language != 'any' && cs.language != lang) continue;
      if (cs.trigger.toLowerCase().startsWith(lower)) {
        items.add(CompletionItem(label: cs.trigger, kind: CompletionKind.snippet, detail: cs.label, documentation: cs.description.isNotEmpty ? cs.description : null, insertText: cs.body));
      }
    }

    // Symbols from the current file (identifiers)
    final symbolRe = RegExp(r'\b([A-Za-z_][A-Za-z0-9_]{2,})\b');
    final seen = <String>{};
    for (final m in symbolRe.allMatches(fullText)) {
      final sym = m.group(1)!;
      if (sym.toLowerCase().startsWith(lower) && !seen.contains(sym)) {
        seen.add(sym);
        items.add(CompletionItem(label: sym, kind: CompletionKind.variable, detail: 'symbol'));
      }
    }

    // Deduplicate preserving first occurrence
    final deduped = <String, CompletionItem>{};
    for (final item in items) {
      deduped.putIfAbsent(item.label, () => item);
    }
    final result = deduped.values.toList();
    result.sort((a, b) {
      // Exact prefix match first, then kind order
      final aExact = a.label.startsWith(prefix) ? 0 : 1;
      final bExact = b.label.startsWith(prefix) ? 0 : 1;
      if (aExact != bExact) return aExact - bExact;
      return a.label.compareTo(b.label);
    });
    return result.take(12).toList();
  }

  List<String> _keywordsForLang(String lang) => switch (lang) {
        'dart'                        => [..._dartKw, ..._dartTypes],
        'python'                      => _pyKw,
        'javascript' || 'typescript'  => _jsKw,
        'kotlin'                      => _ktKw,
        _                             => [],
      };
}

// ─── Go-to-definition (grep-based) ──────────────────────────────────────────
class DefinitionProvider {
  static Future<(String file, int line)?> findDefinition(String symbol, String? workspacePath) async {
    if (workspacePath == null) return null;
    // Patterns for common definition signatures
    final patterns = [
      RegExp(r'^\s*(class|abstract class|sealed class|mixin|enum)\s+' + RegExp.escape(symbol)),
      RegExp(r'^\s*(void|Future|Stream|String|int|double|bool|List|Map|dynamic|var|final|late|const)\s+' + RegExp.escape(symbol) + r'\s*[\(\{=]'),
      RegExp(r'^\s*' + RegExp.escape(symbol) + r'\s*[\(\{:]'),
      RegExp(r'def\s+' + RegExp.escape(symbol)),
      RegExp(r'fun\s+' + RegExp.escape(symbol)),
      RegExp(r'function\s+' + RegExp.escape(symbol)),
      RegExp(r'const\s+' + RegExp.escape(symbol) + r'\s*='),
      RegExp(r'let\s+' + RegExp.escape(symbol) + r'\s*='),
    ];

    try {
      final result = await Process.run('grep', [
        '-rn', '--include=*.dart', '--include=*.py', '--include=*.js',
        '--include=*.ts', '--include=*.kt', '--include=*.java',
        symbol, workspacePath,
      ]);
      final lines = result.stdout.toString().split('\n').where((l) => l.trim().isNotEmpty);
      for (final line in lines) {
        final colonIdx = line.indexOf(':');
        if (colonIdx < 0) continue;
        final rest = line.substring(colonIdx + 1);
        final lineNumEnd = rest.indexOf(':');
        if (lineNumEnd < 0) continue;
        final lineNum = int.tryParse(rest.substring(0, lineNumEnd)) ?? 0;
        final content = rest.substring(lineNumEnd + 1);
        final filePath = line.substring(0, colonIdx);
        for (final pattern in patterns) {
          if (pattern.hasMatch(content)) {
            return (filePath, lineNum);
          }
        }
      }
    } catch (_) {}
    return null;
  }
}

// ─── Hover Doc Provider ──────────────────────────────────────────────────────
class HoverProvider {
  static final _docs = <String, String>{
    // Dart
    'String':    'A sequence of UTF-16 code units. Dart\'s built-in string type.',
    'int':       'An arbitrary-precision integer. 64-bit on native, arbitrary on web.',
    'double':    'A 64-bit IEEE 754 floating point number.',
    'bool':      'A Boolean value: `true` or `false`.',
    'List':      'An indexable collection of objects with a length.',
    'Map':       'A collection of key/value pairs, from which you retrieve a value using its associated key.',
    'Future':    'An object representing a delayed computation.',
    'Stream':    'A sequence of asynchronous events.',
    'Widget':    'Describes the configuration for an Element. The base class for Flutter widgets.',
    'State':     'The logic and internal state for a StatefulWidget.',
    'BuildContext': 'A handle to the location of a widget in the widget tree.',
    'setState':  'Notify the framework that the internal state of this object has changed.',
    'initState': 'Called when this object is inserted into the tree. Override to perform initialization.',
    'dispose':   'Called when this object is removed from the tree permanently.',
    'build':     'Describes the part of the user interface represented by this widget.',
    // Flutter
    'Container':  'A convenience widget that combines common painting, positioning, and sizing widgets.',
    'Row':        'A widget that displays its children in a horizontal array.',
    'Column':     'A widget that displays its children in a vertical array.',
    'Scaffold':   'Implements the basic Material Design visual layout structure.',
    'Text':       'A run of text with a single style.',
    'Navigator':  'A widget that manages a set of child widgets with a stack discipline.',
    // Python
    'print':      'Print objects to the text stream file, separated by sep and followed by end.',
    'len':        'Return the length (the number of items) of an object.',
    'range':      'Return an immutable sequence of numbers.',
    // Kotlin
    'fun':        'Declares a function in Kotlin.',
    'val':        'Read-only local variable (cannot be reassigned).',
    'var':        'Mutable local variable.',
    'data':       'Generates equals(), hashCode(), toString() and copy() automatically.',
    'suspend':    'Marks a function as suspendable — can be called from a coroutine.',
    'launch':     'Launches a new coroutine concurrently with the rest of the code.',
    'async':      'Creates a coroutine and returns its result as a Deferred.',
  };

  static String? getHover(String symbol) => _docs[symbol];
}
