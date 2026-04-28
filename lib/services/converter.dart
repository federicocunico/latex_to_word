import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'pandoc_resolver.dart';
import 'pdf_image_preprocessor.dart';

class ConversionResult {
  final File docxFile;
  final String log;

  const ConversionResult({required this.docxFile, required this.log});
}

/// Invokes the bundled pandoc binary to convert a LaTeX file to DOCX.
///
/// Ports logic from backend/services/converter.py.
class PandocConverter {
  /// Converts [mainTex] to a DOCX file inside [outputDir].
  ///
  /// Returns [ConversionResult] with the output file and pandoc log.
  /// Throws [ProcessException] if pandoc exits with a non-zero code AND
  /// no DOCX file was produced.
  ///
  /// [cslPath] — optional path to a CSL file; when provided pandoc uses that
  /// citation style instead of its built-in default.
  static Future<ConversionResult> convert(
    File mainTex,
    Directory outputDir, {
    String? cslPath,
  }) async {
    await outputDir.create(recursive: true);

    final imagePrep = await PdfImagePreprocessor.prepareForDocx(mainTex);

    final pandocBin = PandocResolver.resolve();
    final docxPath = p.join(outputDir.path, 'output.docx');
    final sourceDir = mainTex.parent;

    final resourcePaths = await _collectResourcePaths(sourceDir);
    final resourcePathStr = resourcePaths.join(Platform.isWindows ? ';' : ':');

    final bibFiles = await _findBibFiles(sourceDir);
    final bibArgs = bibFiles.map((f) => '--bibliography=${f.path}').toList();

    final cmd = [
      pandocBin,
      mainTex.path,
      '--from=latex',
      '--to=docx',
      '--output=$docxPath',
      '--resource-path=$resourcePathStr',
      '--standalone',
      '--citeproc',
      if (cslPath != null) '--csl=$cslPath',
      ...bibArgs,
    ];

    final result =
        await Process.run(
          cmd.first,
          cmd.sublist(1),
          workingDirectory: sourceDir.path,
          runInShell: false,
        ).timeout(
          const Duration(seconds: 120),
          onTimeout: () => throw TimeoutException(
            'pandoc timed out after 120 seconds',
            const Duration(seconds: 120),
          ),
        );

    final pandocLog = '${result.stdout}${result.stderr}'.trim();
    final logParts = <String>[];
    if (imagePrep.log.isNotEmpty) {
      logParts.add(imagePrep.log);
    }
    if (pandocLog.isNotEmpty) {
      logParts.add(pandocLog);
    }
    final log = logParts.join('\n\n');

    final docxFile = File(docxPath);
    if (!docxFile.existsSync()) {
      throw ProcessException(
        pandocBin,
        cmd.sublist(1),
        'pandoc failed to produce DOCX (exit ${result.exitCode}).\n$log',
        result.exitCode,
      );
    }

    return ConversionResult(docxFile: docxFile, log: log);
  }

  /// Returns the source root plus all subdirectories (for image resolution).
  static Future<List<String>> _collectResourcePaths(Directory root) async {
    final paths = <String>[root.path];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is Directory) {
        paths.add(entity.path);
      }
    }
    return paths;
  }

  /// Recursively finds all .bib files under [root].
  static Future<List<File>> _findBibFiles(Directory root) async {
    final bibs = <File>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.bib')) {
        bibs.add(entity);
      }
    }
    return bibs;
  }
}
