import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Detects the bibliography/citation style of a LaTeX project and resolves
/// a matching CSL file for pandoc's `--csl` flag.
///
/// Detection order (first match wins):
///   1. `\bibliographystyle{name}` — classic BibTeX
///   2. `\usepackage[style=name]{biblatex}` — BibLaTeX
///   3. Document class (`\documentclass{name}`) — fallback from known classes
///
/// CSL files are cached in `<appSupport>/csl/` and downloaded on demand from
/// the [official CSL styles repository](https://github.com/citation-style-language/styles).
class CitationStyleResolver {
  // ── CSL mapping tables ──────────────────────────────────────────────────

  /// BibTeX `\bibliographystyle{name}` → CSL name
  static const _bibTexMap = <String, String>{
    // IEEE / numeric
    'ieeetr': 'ieee',
    'IEEEtran': 'ieee',
    'ieeetran': 'ieee',
    'plain': 'ieee',
    'unsrt': 'ieee',
    'abbrv': 'ieee',
    'alpha': 'ieee',
    // APA / author-date
    'apalike': 'apa',
    'apa': 'apa',
    'plainnat': 'chicago-author-date',
    'unsrtnat': 'chicago-author-date',
    'abbrvnat': 'apa',
    'humannat': 'chicago-author-date',
    // Publisher-specific
    'nature': 'nature',
    'science': 'science',
    'acm': 'acm-sig-proceedings',
    'vancouver': 'vancouver',
    'chicago': 'chicago-author-date',
    'mla': 'modern-language-association',
    'jmlr2e': 'chicago-author-date',
    // Elsevier
    'elsarticle-num': 'elsevier-vancouver',
    'elsarticle-harv': 'elsevier-harvard',
    'elsarticle-num-names': 'elsevier-with-titles',
  };

  /// BibLaTeX `\usepackage[style=name]{biblatex}` → CSL name
  static const _bibLatexMap = <String, String>{
    // Numeric
    'numeric': 'ieee',
    'numeric-comp': 'ieee',
    'numeric-verb': 'ieee',
    'alphabetic': 'ieee',
    'alphabetic-verb': 'ieee',
    // Author-date
    'authoryear': 'chicago-author-date',
    'authoryear-comp': 'chicago-author-date',
    'authoryear-ibid': 'chicago-author-date',
    'authoryear-icomp': 'chicago-author-date',
    // APA
    'apa': 'apa',
    'apa6': 'apa',
    'apa7': 'apa',
    // Author-title
    'authortitle': 'chicago-fullnote-bibliography',
    'authortitle-comp': 'chicago-fullnote-bibliography',
    'authortitle-ibid': 'chicago-fullnote-bibliography',
    // Chicago
    'chicago-authordate': 'chicago-author-date',
    'chicago-notes': 'chicago-fullnote-bibliography',
    // Publisher
    'ieee': 'ieee',
    'nature': 'nature',
    'science': 'science',
    'mla': 'modern-language-association',
    'vancouver': 'vancouver',
    'verbose': 'chicago-fullnote-bibliography',
  };

  /// Document class → CSL fallback when no explicit bib style found
  static const _classMap = <String, String>{
    // IEEE
    'IEEEtran': 'ieee',
    'ieeetran': 'ieee',
    // ACM
    'acmart': 'acm-sig-proceedings',
    'ACM-Reference-Format': 'acm-sig-proceedings',
    // Elsevier
    'elsarticle': 'elsevier-vancouver',
    // APS / RevTeX
    'revtex4-2': 'aps-physical-review-b',
    'revtex4': 'aps-physical-review-b',
    // Nature Publishing Group
    'nature': 'nature',
    'nature-reviews': 'nature',
    'naturemag': 'nature',
    // Springer / LNCS
    'llncs': 'springer-lecture-notes-in-computer-science',
    'lncs': 'springer-lecture-notes-in-computer-science',
    // PLOS
    'plos2015': 'plos-one',
    // APA template classes
    'apa6': 'apa',
    'apa7': 'apa',
  };

  /// Ordered list of supported citation styles for the UI picker.
  /// Each entry is `(cslName, displayLabel)`.
  static const List<(String, String)> supportedStyles = [
    ('apa', 'APA 7th Edition'),
    ('ieee', 'IEEE'),
    ('nature', 'Nature'),
    ('science', 'Science'),
    ('vancouver', 'Vancouver'),
    ('chicago-author-date', 'Chicago Author-Date'),
    ('chicago-fullnote-bibliography', 'Chicago Fullnote'),
    ('modern-language-association', 'MLA'),
    ('acm-sig-proceedings', 'ACM SIG'),
    ('elsevier-vancouver', 'Elsevier (Vancouver)'),
    ('elsevier-harvard', 'Elsevier (Harvard)'),
    ('elsevier-with-titles', 'Elsevier (with Titles)'),
    ('aps-physical-review-b', 'APS Physical Review B'),
    ('springer-lecture-notes-in-computer-science', 'Springer LNCS'),
    ('plos-one', 'PLOS ONE'),
  ];

  static const _cslBaseUrl =
      'https://raw.githubusercontent.com/citation-style-language/styles/master';

  // ── Public API ──────────────────────────────────────────────────────────

  /// Detects the citation style from [mainTex] (and sibling `.cls` files)
  /// and returns a local path to the matching `.csl` file.
  ///
  /// Downloads and caches the CSL file on first use.
  /// Returns `null` if no style is detected or the download fails, in which
  /// case pandoc will use its built-in default.
  static Future<String?> resolve(File mainTex) async {
    final texContent = await mainTex.readAsString();
    final sourceDir = mainTex.parent;

    final cslName = _detectStyle(texContent, sourceDir);
    if (cslName == null) return null;

    return _fetchCsl(cslName);
  }

  /// Like [resolve] but uses [override] (a CSL name) instead of auto-detection
  /// when it is non-null. Use this when the user has explicitly chosen a style.
  static Future<String?> resolveWithOverride(
    File mainTex,
    String? override,
  ) async {
    if (override != null) return _fetchCsl(override);
    return resolve(mainTex);
  }

  // ── Detection ──────────────────────────────────────────────────────────

  static String? _detectStyle(String texContent, Directory sourceDir) {
    // 1. \bibliographystyle{name}
    final bibStyleMatch =
        RegExp(r'\\bibliographystyle\{([^}]+)\}').firstMatch(texContent);
    if (bibStyleMatch != null) {
      final name = bibStyleMatch.group(1)!.trim();
      final csl = _bibTexMap[name];
      if (csl != null) return csl;
    }

    // 2. \usepackage[..., style=name, ...]{biblatex}
    final bibLatexMatch = RegExp(
      r'\\usepackage\[([^\]]*)\]\{biblatex\}',
      caseSensitive: false,
    ).firstMatch(texContent);
    if (bibLatexMatch != null) {
      final opts = bibLatexMatch.group(1)!;
      final styleMatch =
          RegExp(r'(?:^|,)\s*style\s*=\s*([a-zA-Z0-9_-]+)').firstMatch(opts);
      if (styleMatch != null) {
        final name = styleMatch.group(1)!.trim();
        final csl = _bibLatexMap[name];
        if (csl != null) return csl;
      }
    }

    // 3. Document class → exact lookup
    final classMatch =
        RegExp(r'\\documentclass(?:\[[^\]]*\])?\{([^}]+)\}').firstMatch(texContent);
    final docClass = classMatch?.group(1)?.trim();
    if (docClass != null) {
      final csl = _classMap[docClass];
      if (csl != null) return csl;
    }

    // 4. Scan sibling .cls files — by filename, then by content.
    //    When \bibliography{} is used without \bibliographystyle{}, the style
    //    may be embedded directly inside the .cls file provided by the journal.
    final hasBibCommand = RegExp(r'\\bibliography\{').hasMatch(texContent);
    try {
      for (final entity in sourceDir.listSync(recursive: false)) {
        if (entity is! File || !entity.path.endsWith('.cls')) continue;

        // 4a. Filename-based lookup
        final clsName = p.basenameWithoutExtension(entity.path);
        final cslByName = _classMap[clsName] ?? _bibTexMap[clsName];
        if (cslByName != null) return cslByName;

        // 4b. Content scan — look for \bibliographystyle inside the .cls
        if (hasBibCommand) {
          try {
            final clsContent = entity.readAsStringSync();
            final embedded =
                RegExp(r'\\bibliographystyle\{([^}]+)\}').firstMatch(clsContent);
            if (embedded != null) {
              final name = embedded.group(1)!.trim();
              final csl = _bibTexMap[name];
              if (csl != null) return csl;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 5. Keyword fallback from document class name (handles e.g. "nature-reviews")
    if (docClass != null) {
      final lc = docClass.toLowerCase();
      if (lc.contains('nature')) return 'nature';
      if (lc.contains('ieee')) return 'ieee';
      if (lc.contains('elsevier') || lc.contains('elsarticle')) {
        return 'elsevier-vancouver';
      }
      if (lc.contains('springer') || lc.contains('llncs') || lc.contains('lncs')) {
        return 'springer-lecture-notes-in-computer-science';
      }
      if (lc.contains('aps') || lc.contains('revtex')) return 'aps-physical-review-b';
      if (lc.contains('acm')) return 'acm-sig-proceedings';
      if (lc.contains('plos')) return 'plos-one';
    }

    return null;
  }

  // ── CSL download / cache ───────────────────────────────────────────────

  static Future<String?> _fetchCsl(String cslName) async {
    try {
      final appSupport = await getApplicationSupportDirectory();
      final cslDir = Directory(p.join(appSupport.path, 'csl'));
      await cslDir.create(recursive: true);

      final cslFile = File(p.join(cslDir.path, '$cslName.csl'));
      if (cslFile.existsSync() && cslFile.lengthSync() > 0) {
        return cslFile.path; // cached
      }

      final url = '$_cslBaseUrl/$cslName.csl';
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);

      try {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set('User-Agent', 'latex-to-word-app');
        final response = await request.close();

        if (response.statusCode != 200) return null;

        final sink = cslFile.openWrite();
        await response.pipe(sink);
        return cslFile.path;
      } finally {
        client.close();
      }
    } catch (_) {
      return null; // silently fall back to pandoc default
    }
  }
}
