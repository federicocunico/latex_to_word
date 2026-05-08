import 'dart:io';
import 'package:path/path.dart' as p;

class LatexPreprocessResult {
  final bool affiliationsPreprocessed;
  final int captionsNumbered;

  const LatexPreprocessResult({
    required this.affiliationsPreprocessed,
    required this.captionsNumbered,
  });

  String get log {
    final lines = <String>[];
    if (affiliationsPreprocessed) {
      lines.add(
        'Preprocessor: author affiliations and contribution markers formatted.',
      );
    }
    if (captionsNumbered > 0) {
      lines.add(
        'Preprocessor: added Figure/Table numbering to $captionsNumbered caption(s).',
      );
    }
    return lines.join('\n');
  }
}

class _Author {
  final String originalText;
  final String marks;
  final String cleanName;

  const _Author({
    required this.originalText,
    required this.marks,
    required this.cleanName,
  });
}

class _Affil {
  final String originalText;
  final String index;
  final String text;

  const _Affil({
    required this.originalText,
    required this.index,
    required this.text,
  });
}

/// Preprocesses LaTeX source in-place before pandoc conversion.
///
/// Handles two transformations:
///   1. authblk-style \author[marks]{name}, \affil[n]{text},
///      \correspondingauthor{email} → pandoc-compatible author block.
///   2. Adds explicit "Figure N." / "Table N." prefixes to \caption{} inside
///      figure/table environments (traversing \input{} chains in document order).
class LatexPreprocessor {
  static Future<LatexPreprocessResult> preprocess(File mainTex) async {
    final affiliationsPreprocessed = await _preprocessAffiliations(mainTex);
    final captionsNumbered = await _preprocessCaptions(mainTex);

    return LatexPreprocessResult(
      affiliationsPreprocessed: affiliationsPreprocessed,
      captionsNumbered: captionsNumbered,
    );
  }

  // ----------------------------------------------------------------
  // AFFILIATION PREPROCESSING
  // ----------------------------------------------------------------

  static Future<bool> _preprocessAffiliations(File mainTex) async {
    final content = await mainTex.readAsString();

    if (!_hasAffilCommands(content)) return false;

    final authors = _parseAuthors(content);
    if (authors.isEmpty) return false;

    final affils = _parseAffils(content);
    final corresponding = _parseCorresponding(content);

    // Build pandoc-compatible \author{...} with inline superscripts
    final authorParts = authors.map((a) {
      if (a.marks.isEmpty) return a.cleanName;
      return '${a.cleanName}\\textsuperscript{${a.marks}}';
    }).toList();
    final newAuthorCmd = '\\author{${authorParts.join(', ')}}';

    // Build affiliation block to inject after \maketitle
    final affLines = <String>[];
    for (final af in affils) {
      affLines.add('\\noindent\\textsuperscript{${af.index}}\\,${af.text}');
    }
    if (corresponding != null) {
      affLines.add(
        '\\noindent\\textit{Corresponding author:} $corresponding',
      );
    }
    final affBlock = affLines.isEmpty
        ? ''
        : '\n${affLines.join('\n\n')}\n';

    var newContent = content;

    for (final a in authors) {
      newContent = newContent.replaceFirst(a.originalText, '');
    }
    for (final af in affils) {
      newContent = newContent.replaceFirst(af.originalText, '');
    }
    if (corresponding != null) {
      newContent = newContent.replaceFirst(
        RegExp(r'\\correspondingauthor\{[^}]+\}[ \t]*\r?\n?'),
        '',
      );
    }

    // Remove \runningtitle{...} (unknown to pandoc)
    newContent = newContent.replaceAll(
      RegExp(r'\\runningtitle\{[^}]+\}[ \t]*\r?\n?'),
      '',
    );

    // Insert new \author{...} just before \begin{document}.
    // Use a literal-string match (no RegExp) so that \begin{document} is
    // preserved verbatim in the replacement — Dart's replaceFirst does NOT
    // perform $n back-reference substitution.
    newContent = newContent.replaceFirst(
      r'\begin{document}',
      '$newAuthorCmd\n\\begin{document}',
    );

    // Inject affiliation block right after \maketitle.
    if (affBlock.isNotEmpty) {
      newContent = newContent.replaceFirst(
        r'\maketitle',
        '\\maketitle\n$affBlock',
      );
    }

    await mainTex.writeAsString(newContent);
    return true;
  }

  static bool _hasAffilCommands(String content) =>
      content.contains(r'\affil') || content.contains(r'\correspondingauthor');

  static List<_Author> _parseAuthors(String content) {
    final result = <_Author>[];
    var pos = 0;

    while (pos < content.length) {
      final idx = content.indexOf(r'\author', pos);
      if (idx == -1) break;

      // Must be followed immediately by '[' or '{' (not \authorref, etc.)
      final after = idx + 7;
      if (after >= content.length ||
          (content[after] != '[' && content[after] != '{')) {
        pos = idx + 1;
        continue;
      }

      if (_isCommentedOut(content, idx)) {
        pos = idx + 1;
        continue;
      }

      var cur = after;
      String marks = '';

      if (content[cur] == '[') {
        final closeB = content.indexOf(']', cur);
        if (closeB == -1) {
          pos = idx + 1;
          continue;
        }
        marks = content.substring(cur + 1, closeB).trim();
        cur = closeB + 1;
      }

      while (cur < content.length && content[cur] == ' ') cur++;
      if (cur >= content.length || content[cur] != '{') {
        pos = idx + 1;
        continue;
      }

      final (nameContent, nameEnd) = _extractBraced(content, cur);
      var endPos = nameEnd + 1;
      while (endPos < content.length &&
          (content[endPos] == ' ' || content[endPos] == '\t')) {
        endPos++;
      }
      if (endPos < content.length && content[endPos] == '\r') endPos++;
      if (endPos < content.length && content[endPos] == '\n') endPos++;

      final cleanName =
          nameContent.replaceAll(RegExp(r'\\orcid\{[^}]*\}'), '').trim();

      result.add(_Author(
        originalText: content.substring(idx, endPos),
        marks: marks,
        cleanName: cleanName,
      ));
      pos = endPos;
    }

    return result;
  }

  static List<_Affil> _parseAffils(String content) {
    final result = <_Affil>[];
    var pos = 0;

    while (pos < content.length) {
      final idx = content.indexOf(r'\affil', pos);
      if (idx == -1) break;

      final after = idx + 6;
      if (after >= content.length ||
          (content[after] != '[' && content[after] != '{')) {
        pos = idx + 1;
        continue;
      }

      if (_isCommentedOut(content, idx)) {
        pos = idx + 1;
        continue;
      }

      var cur = after;
      String index = '';

      if (content[cur] == '[') {
        final closeB = content.indexOf(']', cur);
        if (closeB == -1) {
          pos = idx + 1;
          continue;
        }
        index = content.substring(cur + 1, closeB).trim();
        cur = closeB + 1;
      }

      while (cur < content.length && content[cur] == ' ') cur++;
      if (cur >= content.length || content[cur] != '{') {
        pos = idx + 1;
        continue;
      }

      final (text, textEnd) = _extractBraced(content, cur);
      var endPos = textEnd + 1;
      while (endPos < content.length &&
          (content[endPos] == ' ' || content[endPos] == '\t')) {
        endPos++;
      }
      if (endPos < content.length && content[endPos] == '\r') endPos++;
      if (endPos < content.length && content[endPos] == '\n') endPos++;

      result.add(_Affil(
        originalText: content.substring(idx, endPos),
        index: index,
        text: text.trim().replaceAll(RegExp(r'[ \t]+'), ' '),
      ));
      pos = endPos;
    }

    return result;
  }

  static String? _parseCorresponding(String content) {
    final m =
        RegExp(r'\\correspondingauthor\{([^}]+)\}').firstMatch(content);
    return m?.group(1)?.trim();
  }

  // ----------------------------------------------------------------
  // CAPTION NUMBERING
  // ----------------------------------------------------------------

  static Future<int> _preprocessCaptions(File mainTex) async {
    var figCounter = 0;
    var tableCounter = 0;
    var totalNumbered = 0;
    final visited = <String>{};

    Future<void> processFile(File f) async {
      final absPath = f.absolute.path;
      if (visited.contains(absPath)) return;
      visited.add(absPath);
      if (!await f.exists()) return;

      final content = await f.readAsString();
      final buffer = StringBuffer();
      var pos = 0;
      var fileModified = false;

      while (pos < content.length) {
        // Find the next event: figure env, table env, or \input{}
        final events = <(int, String)>[];
        for (final tag in [
          r'\begin{figure}',
          r'\begin{figure*}',
          r'\begin{table}',
          r'\begin{table*}',
        ]) {
          final idx = _findNextUncommented(content, tag, pos);
          if (idx != -1) events.add((idx, tag.substring(7))); // strip \begin{
        }
        final inputIdx = _findNextUncommented(content, r'\input{', pos);
        if (inputIdx != -1) events.add((inputIdx, 'input'));

        if (events.isEmpty) break;
        events.sort((a, b) => a.$1.compareTo(b.$1));
        final (nextIdx, nextType) = events.first;

        buffer.write(content.substring(pos, nextIdx));

        if (nextType == 'input') {
          // Locate the {path}
          final braceAt = content.indexOf('{', nextIdx + 6);
          if (braceAt == -1) {
            buffer.write(content.substring(nextIdx));
            pos = content.length;
            continue;
          }
          final (inputPath, braceEnd) = _extractBraced(content, braceAt);
          // Write \input{...} unchanged to buffer
          buffer.write(content.substring(nextIdx, braceEnd + 1));
          pos = braceEnd + 1;

          // Recurse into included file (updates figCounter, tableCounter)
          var rel = inputPath.trim();
          if (!rel.endsWith('.tex')) rel = '$rel.tex';
          final inputFile = File(p.join(f.parent.path, rel));
          await processFile(inputFile);
        } else {
          // It's a figure or table environment
          final endTag = '\\end{$nextType';
          // Find closing \end{figure} or \end{table} etc.
          final envEnd = content.indexOf(endTag, nextIdx);
          if (envEnd == -1) {
            buffer.write(content.substring(nextIdx));
            pos = content.length;
            continue;
          }
          // endTag already includes the closing '}', so the full end is right
          // after the tag itself.
          final fullEndPos = envEnd + endTag.length;

          final envContent = content.substring(nextIdx, fullEndPos);
          final isFigure = nextType.startsWith('figure');
          final label = isFigure ? 'Figure' : 'Table';
          final counter = isFigure ? figCounter + 1 : tableCounter + 1;

          final (numberedEnv, added) =
              _addCaptionPrefix(envContent, label, counter);

          if (added) {
            if (isFigure) {
              figCounter++;
            } else {
              tableCounter++;
            }
            fileModified = true;
            totalNumbered++;
          } else {
            // Caption already prefixed or missing — still count the environment
            if (isFigure) figCounter++;
            else tableCounter++;
          }

          buffer.write(numberedEnv);
          pos = fullEndPos;
        }
      }

      buffer.write(content.substring(pos));

      if (fileModified) {
        await f.writeAsString(buffer.toString());
      }
    }

    await processFile(mainTex);
    return totalNumbered;
  }

  /// Adds "Label N. " prefix to the first \caption{} inside [envContent].
  /// Returns (newEnvContent, wasPrefixAdded).
  static (String, bool) _addCaptionPrefix(
    String envContent,
    String label,
    int number,
  ) {
    final captionIdx = envContent.indexOf(r'\caption');
    if (captionIdx == -1) return (envContent, false);
    if (_isCommentedOut(envContent, captionIdx)) return (envContent, false);

    var cur = captionIdx + 8; // after \caption

    // Skip \caption* (unnumbered — don't touch)
    if (cur < envContent.length && envContent[cur] == '*') {
      return (envContent, false);
    }

    // Skip optional [short caption] — we'll leave it unchanged
    int shortEnd = cur;
    if (cur < envContent.length && envContent[cur] == '[') {
      final closeB = envContent.indexOf(']', cur);
      if (closeB != -1) shortEnd = closeB + 1;
      cur = shortEnd;
    }

    while (cur < envContent.length && envContent[cur] == ' ') cur++;
    if (cur >= envContent.length || envContent[cur] != '{') {
      return (envContent, false);
    }

    final (captionText, captionEnd) = _extractBraced(envContent, cur);

    // Avoid double-prefixing
    final trimmed = captionText.trimLeft();
    if (RegExp(r'^(Figure|Table|FIG\.|TAB\.)\s').hasMatch(trimmed)) {
      return (envContent, false);
    }

    final prefix = '$label $number. ';
    final newContent = envContent.substring(0, cur + 1) +
        prefix +
        captionText +
        envContent.substring(captionEnd);

    return (newContent, true);
  }

  // ----------------------------------------------------------------
  // UTILITIES
  // ----------------------------------------------------------------

  static int _findNextUncommented(String content, String pattern, int start) {
    var pos = start;
    while (true) {
      final idx = content.indexOf(pattern, pos);
      if (idx == -1) return -1;
      if (!_isCommentedOut(content, idx)) return idx;
      pos = idx + 1;
    }
  }

  static bool _isCommentedOut(String content, int pos) {
    if (pos <= 0) return false;
    var lineStart = content.lastIndexOf('\n', pos - 1);
    lineStart = lineStart == -1 ? 0 : lineStart + 1;
    final prefix = content.substring(lineStart, pos);
    for (var i = 0; i < prefix.length; i++) {
      if (prefix[i] == '%' && (i == 0 || prefix[i - 1] != r'\')) return true;
    }
    return false;
  }

  /// Returns (content, endIndex) for the balanced-brace block starting at [start].
  /// [start] must point at '{'.
  static (String, int) _extractBraced(String text, int start) {
    assert(start < text.length && text[start] == '{');
    var depth = 0;
    final sb = StringBuffer();
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (ch == '{') {
        depth++;
        if (depth > 1) sb.write(ch);
      } else if (ch == '}') {
        depth--;
        if (depth == 0) return (sb.toString(), i);
        sb.write(ch);
      } else {
        sb.write(ch);
      }
    }
    return (sb.toString(), text.length - 1);
  }
}
