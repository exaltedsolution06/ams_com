/// A single "line" of the Rules page: plain text plus line-level
/// formatting (bold / italic / color). Deliberately line-level rather than
/// per-character - Rules content is naturally a numbered/bulleted list of
/// statements, and this keeps the mobile editor achievable without pulling
/// in an unverified third-party rich-text package (this sandbox has no
/// pub.dev access to confirm one's current API - see pubspec.yaml's own
/// note on the same tradeoff for string-similarity matching).
///
/// Stored/exchanged as HTML (one `<p>` per block) so it stays compatible
/// with the web admin panel, which edits the same `content` field with a
/// full Quill editor (see admin/rules/edit.blade.php on the backend).
/// Round-tripping through Quill's richer per-character formatting isn't
/// attempted here - a block just picks up whichever formatting covers
/// most of its text.
class RuleBlock {
  String text;
  bool bold;
  bool italic;
  /// Hex color like '#E53935', or null for the default text color.
  String? colorHex;

  RuleBlock({this.text = '', this.bold = false, this.italic = false, this.colorHex});
}

String _escapeHtml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _stripTags(String html) => html
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .trim();

/// Blocks -> HTML, ready to save to the `content` field.
String encodeRuleBlocksToHtml(List<RuleBlock> blocks) {
  final buffer = StringBuffer();
  for (final b in blocks) {
    if (b.text.trim().isEmpty) continue;
    var inner = _escapeHtml(b.text);
    if (b.bold) inner = '<strong>$inner</strong>';
    if (b.italic) inner = '<em>$inner</em>';
    final styleAttr = b.colorHex != null ? ' style="color:${b.colorHex}"' : '';
    buffer.write('<p$styleAttr>$inner</p>');
  }
  return buffer.toString();
}

/// HTML -> blocks, for editing. Best-effort: reads whichever formatting
/// covers a whole paragraph/line. Content authored on the web with mixed
/// per-character formatting on one line will import as plain text for
/// that line (formatting isn't lost from the *stored* HTML, only from
/// what the in-app editor can re-show/re-edit for that one line - saving
/// again from the app will flatten it to the line-level style you set).
List<RuleBlock> decodeHtmlToRuleBlocks(String html) {
  if (html.trim().isEmpty) return [RuleBlock()];

  final blockPattern = RegExp(r'<(p|div|li|h[1-6])([^>]*)>(.*?)</\1>', dotAll: true, caseSensitive: false);
  final matches = blockPattern.allMatches(html).toList();

  final blocks = <RuleBlock>[];

  if (matches.isEmpty) {
    // No paragraph-like wrapper tags found - fall back to splitting on
    // <br> (or plain newlines if this wasn't HTML at all).
    final parts = html.split(RegExp(r'<br\s*/?>|\n', caseSensitive: false));
    for (final p in parts) {
      final text = _stripTags(p);
      if (text.isNotEmpty) blocks.add(RuleBlock(text: text));
    }
    return blocks.isEmpty ? [RuleBlock()] : blocks;
  }

  for (final m in matches) {
    final attrs = m.group(2) ?? '';
    final innerHtml = m.group(3) ?? '';
    final text = _stripTags(innerHtml);
    if (text.isEmpty) continue;

    final bold = RegExp(r'<(strong|b)[ >]', caseSensitive: false).hasMatch(innerHtml) ||
        RegExp(r'font-weight\s*:\s*(bold|[6-9]00)', caseSensitive: false).hasMatch(attrs);
    final italic = RegExp(r'<(em|i)[ >]', caseSensitive: false).hasMatch(innerHtml) ||
        RegExp(r'font-style\s*:\s*italic', caseSensitive: false).hasMatch(attrs);

    String? color;
    final colorMatch = RegExp(r'color\s*:\s*(#[0-9a-fA-F]{3,8})', caseSensitive: false)
        .firstMatch('$attrs $innerHtml');
    if (colorMatch != null) color = colorMatch.group(1);

    blocks.add(RuleBlock(text: text, bold: bold, italic: italic, colorHex: color));
  }

  return blocks.isEmpty ? [RuleBlock()] : blocks;
}

/// A small, fixed color palette for the in-app editor - avoids pulling in
/// a full color-picker package for what's meant to be a lightweight tool.
const List<String> ruleBlockColorPalette = [
  '#111111', // default/near-black
  '#E53935', // red
  '#FB8C00', // orange
  '#43A047', // green
  '#1E88E5', // blue
  '#8E24AA', // purple
];
