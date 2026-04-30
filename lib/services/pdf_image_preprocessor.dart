import 'dart:io';
import 'package:path/path.dart' as p;

typedef PdfToPngConverter =
    Future<bool> Function(File inputPdf, File outputPng);

class PdfImagePreparationResult {
  final int convertedImages;
  final int rewrittenFiles;
  final List<String> warnings;

  const PdfImagePreparationResult({
    required this.convertedImages,
    required this.rewrittenFiles,
    required this.warnings,
  });

  String get log {
    if (convertedImages == 0 && warnings.isEmpty) {
      return '';
    }

    final lines = <String>[];
    if (convertedImages > 0) {
      lines.add(
        'PDF image fallback: converted $convertedImages image(s) across '
        '$rewrittenFiles .tex file(s).',
      );
    }
    lines.addAll(warnings.map((w) => 'PDF image fallback warning: $w'));
    return lines.join('\n');
  }
}

class PdfImagePreprocessor {
  static final RegExp _includeGraphicsPattern = RegExp(
    r'\\includegraphics(?:\s*\[[^\]]*\])?\s*\{([^}]+)\}',
    multiLine: true,
  );

  static List<_RasterTool>? _cachedTools;

  /// Rewrites PDF image references in all .tex files under [mainTex.parent]
  /// to PNG paths after converting those PDFs to PNG.
  static Future<PdfImagePreparationResult> prepareForDocx(
    File mainTex, {
    PdfToPngConverter? converter,
  }) async {
    final root = mainTex.parent;
    final texFiles = await _collectTexFiles(root);
    final effectiveConverter = converter ?? _convertPdfToPngWithAvailableTool;

    var convertedImages = 0;
    var rewrittenFiles = 0;
    final warnings = <String>[];

    for (final texFile in texFiles) {
      final outcome = await _rewriteTexFile(texFile, root, effectiveConverter);
      convertedImages += outcome.convertedImages;
      warnings.addAll(outcome.warnings);
      if (outcome.rewritten) {
        rewrittenFiles += 1;
      }
    }

    return PdfImagePreparationResult(
      convertedImages: convertedImages,
      rewrittenFiles: rewrittenFiles,
      warnings: warnings,
    );
  }

  static Future<List<File>> _collectTexFiles(Directory root) async {
    final files = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.tex')) {
        files.add(entity);
      }
    }
    return files;
  }

  static Future<_RewriteOutcome> _rewriteTexFile(
    File texFile,
    Directory projectRoot,
    PdfToPngConverter converter,
  ) async {
    final content = await texFile.readAsString();
    final matches = _includeGraphicsPattern.allMatches(content).toList();
    if (matches.isEmpty) {
      return const _RewriteOutcome(
        rewritten: false,
        convertedImages: 0,
        warnings: <String>[],
      );
    }

    final out = StringBuffer();
    var cursor = 0;
    var rewritten = false;
    var convertedImages = 0;
    final warnings = <String>[];

    for (final match in matches) {
      out.write(content.substring(cursor, match.start));

      final originalSnippet = content.substring(match.start, match.end);
      var replacementSnippet = originalSnippet;

      if (!_isCommentedOut(content, match.start)) {
        final rawRef = match.group(1)!;

        // LaTeX resolves image paths from the project root (compile directory).
        // Fall back to the tex file's own directory for paths that use relative
        // navigation (e.g. ../images/fig.pdf written relative to the .tex file).
        File? sourcePdf;
        Directory resolveBase = projectRoot;

        final fromRoot = _resolvePdfReference(projectRoot, rawRef);
        if (fromRoot != null && await fromRoot.exists()) {
          sourcePdf = fromRoot;
        } else {
          final fromTexDir = _resolvePdfReference(texFile.parent, rawRef);
          if (fromTexDir != null && await fromTexDir.exists()) {
            sourcePdf = fromTexDir;
            resolveBase = texFile.parent;
          }
        }

        if (sourcePdf != null) {
          final outputPng = File(
            p.join(
              sourcePdf.parent.path,
              '${p.basenameWithoutExtension(sourcePdf.path)}__pandoc.png',
            ),
          );

          var converted = false;
          if (await outputPng.exists()) {
            converted = true;
          } else {
            converted = await converter(sourcePdf, outputPng);
          }

          if (converted && await outputPng.exists()) {
            final relativePngPath = p
                .relative(outputPng.path, from: resolveBase.path)
                .replaceAll('\\', '/');
            replacementSnippet = originalSnippet.replaceFirst(
              rawRef,
              relativePngPath,
            );
            if (replacementSnippet != originalSnippet) {
              rewritten = true;
              convertedImages += 1;
            }
          } else {
            warnings.add(
              'Could not convert ${sourcePdf.path} to PNG. '
              'Install ImageMagick (magick), poppler (pdftoppm), or mutool.',
            );
          }
        }
      }

      out.write(replacementSnippet);
      cursor = match.end;
    }

    out.write(content.substring(cursor));

    if (rewritten) {
      await texFile.writeAsString(out.toString());
    }

    return _RewriteOutcome(
      rewritten: rewritten,
      convertedImages: convertedImages,
      warnings: warnings,
    );
  }

  static bool _isCommentedOut(String content, int commandStart) {
    if (commandStart <= 0) {
      return false;
    }

    var lineStart = content.lastIndexOf('\n', commandStart - 1);
    lineStart = lineStart == -1 ? 0 : lineStart + 1;
    final prefix = content.substring(lineStart, commandStart);

    for (var i = 0; i < prefix.length; i += 1) {
      if (prefix[i] == '%' && (i == 0 || prefix[i - 1] != r'\\')) {
        return true;
      }
    }
    return false;
  }

  static File? _resolvePdfReference(Directory texDir, String ref) {
    var candidate = ref.trim();
    if (candidate.isEmpty) {
      return null;
    }

    if ((candidate.startsWith('"') && candidate.endsWith('"')) ||
        (candidate.startsWith("'") && candidate.endsWith("'"))) {
      candidate = candidate.substring(1, candidate.length - 1).trim();
    }

    if (candidate.startsWith('http://') ||
        candidate.startsWith('https://') ||
        candidate.startsWith('data:')) {
      return null;
    }

    final hasLikelyMacro =
        candidate.contains(r'\') &&
        !RegExp(r'^[A-Za-z]:\\').hasMatch(candidate);
    if (hasLikelyMacro) {
      return null;
    }

    final ext = p.extension(candidate).toLowerCase();
    if (ext.isNotEmpty && ext != '.pdf') {
      return null;
    }

    if (ext.isEmpty) {
      candidate = '$candidate.pdf';
    }

    final resolvedPath = p.isAbsolute(candidate)
        ? candidate
        : p.normalize(p.join(texDir.path, candidate));
    return File(resolvedPath);
  }

  static Future<bool> _convertPdfToPngWithAvailableTool(
    File inputPdf,
    File outputPng,
  ) async {
    final tools = await _discoverRasterTools();
    for (final tool in tools) {
      final converted = await _runConversion(tool, inputPdf, outputPng);
      if (converted) {
        return true;
      }
    }
    return false;
  }

  static Future<List<_RasterTool>> _discoverRasterTools() async {
    if (_cachedTools != null) {
      return _cachedTools!;
    }

    final tools = <_RasterTool>[];
    if (await _isCommandAvailable('magick', const ['-version'])) {
      tools.add(_RasterTool.magick);
    }
    if (await _isCommandAvailable('pdftoppm', const ['-v'])) {
      tools.add(_RasterTool.pdftoppm);
    }
    if (await _isCommandAvailable('mutool', const ['--version'])) {
      tools.add(_RasterTool.mutool);
    }

    _cachedTools = tools;
    return tools;
  }

  static Future<bool> _isCommandAvailable(
    String command,
    List<String> args,
  ) async {
    try {
      final result = await Process.run(command, args, runInShell: false);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  static Future<bool> _runConversion(
    _RasterTool tool,
    File inputPdf,
    File outputPng,
  ) async {
    try {
      await outputPng.parent.create(recursive: true);

      ProcessResult result;
      switch (tool) {
        case _RasterTool.magick:
          result = await Process.run('magick', <String>[
            '-density',
            '300',
            '${inputPdf.path}[0]',
            '-background',
            'white',
            '-alpha',
            'remove',
            '-alpha',
            'off',
            outputPng.path,
          ], runInShell: false);
          break;
        case _RasterTool.pdftoppm:
          final outputBase = p.withoutExtension(outputPng.path);
          result = await Process.run('pdftoppm', <String>[
            '-f',
            '1',
            '-l',
            '1',
            '-singlefile',
            '-png',
            inputPdf.path,
            outputBase,
          ], runInShell: false);
          break;
        case _RasterTool.mutool:
          result = await Process.run('mutool', <String>[
            'draw',
            '-F',
            'png',
            '-r',
            '300',
            '-o',
            outputPng.path,
            inputPdf.path,
            '1',
          ], runInShell: false);
          break;
      }

      return result.exitCode == 0 && await outputPng.exists();
    } on ProcessException {
      return false;
    }
  }
}

class _RewriteOutcome {
  final bool rewritten;
  final int convertedImages;
  final List<String> warnings;

  const _RewriteOutcome({
    required this.rewritten,
    required this.convertedImages,
    required this.warnings,
  });
}

enum _RasterTool { magick, pdftoppm, mutool }
