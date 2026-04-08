import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

class ExtractionResult {
  final Directory extractRoot;
  final File mainTex;

  const ExtractionResult({required this.extractRoot, required this.mainTex});
}

/// Extracts an Overleaf ZIP archive and locates the main .tex entry point.
///
/// Ports logic from backend/services/extractor.py.
class ZipExtractor {
  /// Extracts [zipFile] into [destination].
  ///
  /// Returns the extraction root directory and the path to `main.tex`.
  /// Throws [ArgumentError] on path-traversal attempts.
  /// Throws [FileSystemException] if no .tex file is found.
  static Future<ExtractionResult> extract(
    File zipFile,
    Directory destination,
  ) async {
    await destination.create(recursive: true);

    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      // Security: reject path-traversal entries
      if (file.name.startsWith('..') ||
          file.name.startsWith('/') ||
          file.name.contains('/../')) {
        throw ArgumentError('Unsafe ZIP entry: ${file.name}');
      }

      final outPath = p.join(destination.path, file.name);

      if (file.isFile) {
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }

    final mainTex = await _findMainTex(destination);
    if (mainTex == null) {
      throw FileSystemException(
        'No .tex file found in the uploaded ZIP',
        zipFile.path,
      );
    }

    return ExtractionResult(extractRoot: destination, mainTex: mainTex);
  }

  /// Prefers a file literally named `main.tex`; falls back to the first .tex
  /// file not inside a hidden directory.
  static Future<File?> _findMainTex(Directory root) async {
    final allTex = <File>[];

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.tex')) {
        final parts = p.split(entity.path);
        final inHiddenDir = parts.any((part) => part.startsWith('.'));
        if (!inHiddenDir) {
          allTex.add(entity);
          if (p.basename(entity.path) == 'main.tex') {
            return entity;
          }
        }
      }
    }

    return allTex.isNotEmpty ? allTex.first : null;
  }
}
