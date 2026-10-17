// ─── Code Folding Engine ──────────────────────────────────────────────────────
// Identifies foldable regions and manages fold state via text-buffer swap.
// Folded regions are replaced with a `{⋯N}` placeholder (where N = hidden lines)
// so the TextEditingController always sees the correct reduced text.

const _foldPlaceholder = '{⋯';

// ─── Fold region ──────────────────────────────────────────────────────────────
class FoldRegion {
  final int startLine; // 0-indexed, the opening line (contains {)
  final int endLine;   // 0-indexed, the closing line (contains })
  const FoldRegion(this.startLine, this.endLine);
}

// ─── Fold manager ─────────────────────────────────────────────────────────────
class FoldManager {
  // Map of display-line-index → hidden lines content
  final Map<int, String> _foldCache = {};

  bool isFolded(int displayLine) => _foldCache.containsKey(displayLine);

  // Parse foldable regions from text (finds matching { } pairs at block level)
  static List<FoldRegion> detectRegions(String text) {
    final lines = text.split('\n');
    final regions = <FoldRegion>[];
    final stack = <int>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      // Opening brace at end of line (class, function, if, etc.)
      if (trimmed.endsWith('{') && !trimmed.startsWith('//')) {
        stack.push(i);
      }
      // Closing brace only line
      else if ((trimmed == '}' || trimmed == '})' || trimmed == '});' || trimmed == '},') && stack.isNotEmpty) {
        final start = stack.removeLast();
        if (i - start >= 2) { // Only fold if 3+ lines
          regions.add(FoldRegion(start, i));
        }
      }
    }
    return regions;
  }

  // Fold a region: remove interior lines from text, store in cache, return new text
  String fold(String text, FoldRegion region) {
    final lines = text.split('\n');
    if (region.endLine >= lines.length || region.startLine >= lines.length) return text;

    // Adjust for already-folded regions above this one
    final displayStart = region.startLine;
    if (_foldCache.containsKey(displayStart)) return text; // already folded

    // Interior = lines[start+1 .. end] (inclusive of closing brace)
    final interior = lines.sublist(displayStart + 1, region.endLine + 1).join('\n');
    _foldCache[displayStart] = interior;

    // Replace interior lines with placeholder on the opening line
    final hiddenCount = region.endLine - region.startLine;
    final openLine = lines[displayStart];
    final placeholderLine = '${openLine.trimRight()} $_foldPlaceholder$hiddenCount}';
    final newLines = [...lines.sublist(0, displayStart + 1), ...lines.sublist(region.endLine + 1)];
    newLines[displayStart] = placeholderLine;
    return newLines.join('\n');
  }

  // Unfold a display line: restore hidden content, return new text
  String unfold(String text, int displayLine) {
    final hidden = _foldCache.remove(displayLine);
    if (hidden == null) return text;

    final lines = text.split('\n');
    if (displayLine >= lines.length) return text;

    // Strip placeholder from opening line
    var openLine = lines[displayLine];
    final phIdx = openLine.indexOf(' $_foldPlaceholder');
    if (phIdx >= 0) openLine = '${openLine.substring(0, phIdx)} {';

    final restored = [
      ...lines.sublist(0, displayLine),
      openLine,
      hidden,
      ...lines.sublist(displayLine + 1),
    ];
    return restored.join('\n');
  }

  // Find what display line (if any) a fold placeholder is on
  static int? foldedLineAt(String text, int displayLine) {
    final lines = text.split('\n');
    if (displayLine >= lines.length) return null;
    return lines[displayLine].contains(_foldPlaceholder) ? displayLine : null;
  }

  // Check if a given display line is the start of a foldable region
  static FoldRegion? regionStartingAt(List<FoldRegion> regions, int displayLine) {
    for (final r in regions) {
      if (r.startLine == displayLine) return r;
    }
    return null;
  }

  void clear() => _foldCache.clear();
}

extension _ListStack<T> on List<T> {
  void push(T item) => add(item);
}
