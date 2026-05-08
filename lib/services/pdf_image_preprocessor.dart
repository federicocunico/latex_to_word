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

// ── Tool abstraction ──────────────────────────────────────────────────────────

enum _ToolType { magick, pdftoppm, mutool, ghostscript }

/// A discovered raster tool with its resolved executable path.
class _RasterTool {
  final _ToolType type;
  final String exe; // full path OR bare command name if found on PATH

  const _RasterTool(this.type, this.exe);
}

// ── Preprocessor ─────────────────────────────────────────────────────────────

class PdfImagePreprocessor {
  static final RegExp _includeGraphicsPattern = RegExp(
    r'\\includegraphics(?:\s*\[[^\]]*\])?\s*\{([^}]+)\}',
    multiLine: true,
  );

  static List<_RasterTool>? _cachedTools;

  /// The `bin/` directory of a downloaded poppler installation (set via
  /// [configure]). When set, the preprocessor will check here for `pdftoppm`
  /// in addition to the system PATH and well-known installation paths.
  static String? _downloadedBinDir;

  /// Call once after [PdfToolDownloader.configure] to tell the preprocessor
  /// where to look for a downloaded PDF tool.
  static void configure(String? downloadedBinDir) {
    _downloadedBinDir = downloadedBinDir;
    _cachedTools = null; // invalidate cache so discovery re-runs
  }

  /// Returns `true` if at least one PDF-to-PNG tool is already cached.
  static bool hasToolsAvailable() => _cachedTools?.isNotEmpty ?? false;

  /// Clears the tool discovery cache, forcing re-discovery on the next run.
  static void clearToolCache() => _cachedTools = null;

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
              'Could not convert ${sourcePdf.path} to PNG — '
              'no PDF rasterizer found or all rasterizers failed. '
              'Install ghostscript, ImageMagick, MuPDF, or poppler for PDF image support.',
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
    if (commandStart <= 0) return false;

    var lineStart = content.lastIndexOf('\n', commandStart - 1);
    lineStart = lineStart == -1 ? 0 : lineStart + 1;
    final prefix = content.substring(lineStart, commandStart);

    for (var i = 0; i < prefix.length; i++) {
      if (prefix[i] == '%' && (i == 0 || prefix[i - 1] != r'\')) {
        return true;
      }
    }
    return false;
  }

  static File? _resolvePdfReference(Directory texDir, String ref) {
    var candidate = ref.trim();
    if (candidate.isEmpty) return null;

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
    if (hasLikelyMacro) return null;

    final ext = p.extension(candidate).toLowerCase();
    if (ext.isNotEmpty && ext != '.pdf') return null;

    if (ext.isEmpty) candidate = '$candidate.pdf';

    final resolvedPath = p.isAbsolute(candidate)
        ? candidate
        : p.normalize(p.join(texDir.path, candidate));
    return File(resolvedPath);
  }

  // ── Tool discovery ──────────────────────────────────────────────────────────

  static Future<bool> _convertPdfToPngWithAvailableTool(
    File inputPdf,
    File outputPng,
  ) async {
    final tools = await _discoverRasterTools();
    for (final tool in tools) {
      if (await _runConversion(tool, inputPdf, outputPng)) return true;
    }
    return false;
  }

  static Future<List<_RasterTool>> _discoverRasterTools() async {
    if (_cachedTools != null) return _cachedTools!;

    final tools = <_RasterTool>[];

    // 1. PATH — try each well-known command
    if (await _isExeAvailable('magick', ['-version'])) {
      tools.add(_RasterTool(_ToolType.magick, 'magick'));
    }
    if (await _isExeAvailable('pdftoppm', ['-v'])) {
      tools.add(_RasterTool(_ToolType.pdftoppm, 'pdftoppm'));
    }
    if (await _isExeAvailable('mutool', ['--version'])) {
      tools.add(_RasterTool(_ToolType.mutool, 'mutool'));
    }
    for (final gs in ['gswin64c', 'gswin32c', 'gs']) {
      if (await _isExeAvailable(gs, ['--version'])) {
        tools.add(_RasterTool(_ToolType.ghostscript, gs));
        break;
      }
    }

    // 2. Extended search in well-known installation directories
    if (tools.isEmpty) {
      final extended = await _searchKnownLocations();
      tools.addAll(extended);
    }

    // 3. Previously downloaded poppler (app-support dir) — always add as
    // fallback even if PATH tools exist, because some PATH tools (e.g. magick
    // without ghostscript) silently fail on PDFs.
    if (_downloadedBinDir != null) {
      final exe = p.join(
        _downloadedBinDir!,
        Platform.isWindows ? 'pdftoppm.exe' : 'pdftoppm',
      );
      if (File(exe).existsSync()) {
        final alreadyHasFullPathPdftoppm = tools.any(
          (t) => t.type == _ToolType.pdftoppm && p.isAbsolute(t.exe),
        );
        if (!alreadyHasFullPathPdftoppm) {
          tools.add(_RasterTool(_ToolType.pdftoppm, exe));
        }
      }
    }

    _cachedTools = tools;
    return tools;
  }

  /// Searches well-known installation paths on Windows (Ghostscript,
  /// MiKTeX, TeX Live, poppler-windows).
  static Future<List<_RasterTool>> _searchKnownLocations() async {
    if (!Platform.isWindows) return [];

    final found = <_RasterTool>[];

    // Ghostscript
    final gs = await _findGhostscriptExe();
    if (gs != null) found.add(_RasterTool(_ToolType.ghostscript, gs));
    if (found.isNotEmpty) return found;

    // pdftoppm from MiKTeX
    final miktex = await _findMiKTeXPdftoppm();
    if (miktex != null) found.add(_RasterTool(_ToolType.pdftoppm, miktex));
    if (found.isNotEmpty) return found;

    // pdftoppm from TeX Live
    final texlive = await _findTexLivePdftoppm();
    if (texlive != null) found.add(_RasterTool(_ToolType.pdftoppm, texlive));

    return found;
  }

  static Future<String?> _findGhostscriptExe() async {
    for (final root in [
      r'C:\Program Files\gs',
      r'C:\Program Files (x86)\gs',
    ]) {
      final rootDir = Directory(root);
      if (!rootDir.existsSync()) continue;
      try {
        await for (final sub in rootDir.list()) {
          if (sub is! Directory) continue;
          for (final name in ['gswin64c.exe', 'gswin32c.exe']) {
            final exe = File(p.join(sub.path, 'bin', name));
            if (exe.existsSync()) return exe.path;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<String?> _findMiKTeXPdftoppm() async {
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    final programFiles =
        Platform.environment['ProgramFiles'] ?? r'C:\Program Files';

    final candidates = [
      p.join(localAppData, 'Programs', 'MiKTeX', 'miktex', 'bin', 'x64', 'pdftoppm.exe'),
      p.join(localAppData, 'Programs', 'MiKTeX', 'miktex', 'bin', 'pdftoppm.exe'),
      p.join(programFiles, 'MiKTeX', 'miktex', 'bin', 'x64', 'pdftoppm.exe'),
      p.join(programFiles, 'MiKTeX', 'miktex', 'bin', 'pdftoppm.exe'),
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  static Future<String?> _findTexLivePdftoppm() async {
    final rootDir = Directory(r'C:\texlive');
    if (!rootDir.existsSync()) return null;
    try {
      final years = <String>[];
      await for (final e in rootDir.list()) {
        if (e is Directory) years.add(e.path);
      }
      years.sort();
      for (final yearDir in years.reversed) {
        final exe = File(p.join(yearDir, 'bin', 'windows', 'pdftoppm.exe'));
        if (exe.existsSync()) return exe.path;
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> _isExeAvailable(
    String command,
    List<String> args,
  ) async {
    try {
      final result = await Process.run(command, args, runInShell: false);
      return result.exitCode == 0 || result.exitCode == 1;
    } on ProcessException {
      return false;
    }
  }

  // ── Conversion ──────────────────────────────────────────────────────────────

  static Future<bool> _runConversion(
    _RasterTool tool,
    File inputPdf,
    File outputPng,
  ) async {
    try {
      await outputPng.parent.create(recursive: true);

      ProcessResult result;
      switch (tool.type) {
        case _ToolType.magick:
          result = await Process.run(tool.exe, <String>[
            '-density', '300',
            '${inputPdf.path}[0]',
            '-background', 'white',
            '-alpha', 'remove',
            '-alpha', 'off',
            outputPng.path,
          ], runInShell: false);

        case _ToolType.pdftoppm:
          final outputBase = p.withoutExtension(outputPng.path);
          result = await Process.run(tool.exe, <String>[
            '-f', '1', '-l', '1',
            '-singlefile', '-png',
            inputPdf.path,
            outputBase,
          ], runInShell: false);

        case _ToolType.mutool:
          result = await Process.run(tool.exe, <String>[
            'draw', '-F', 'png', '-r', '300',
            '-o', outputPng.path,
            inputPdf.path, '1',
          ], runInShell: false);

        case _ToolType.ghostscript:
          result = await Process.run(tool.exe, <String>[
            '-dNOPAUSE', '-dBATCH', '-dQUIET',
            '-sDEVICE=pngalpha',
            '-r300',
            '-dFirstPage=1', '-dLastPage=1',
            '-sOutputFile=${outputPng.path}',
            inputPdf.path,
          ], runInShell: false);
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
