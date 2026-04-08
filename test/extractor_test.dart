import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:latex_to_word_app/services/extractor.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds an in-memory ZIP and writes it to [dest].
File _makeZip(
  Directory dest,
  Map<String, String> entries, {
  required String name,
}) {
  final archive = Archive();
  for (final entry in entries.entries) {
    final bytes = entry.value.codeUnits;
    archive.addFile(
      ArchiveFile(entry.key, bytes.length, Uint8List.fromList(bytes)),
    );
  }
  final zipBytes = ZipEncoder().encode(archive)!;
  final file = File(p.join(dest.path, name));
  file.writeAsBytesSync(zipBytes);
  return file;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('extractor_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('ZipExtractor', () {
    test('finds main.tex in flat ZIP', () async {
      final zip = _makeZip(
        tempDir,
        {'main.tex': r'\documentclass{article}\begin{document}Hi\end{document}'},
        name: 'flat.zip',
      );

      final dest = Directory(p.join(tempDir.path, 'out_flat'));
      final result = await ZipExtractor.extract(zip, dest);

      expect(result.mainTex.existsSync(), isTrue);
      expect(p.basename(result.mainTex.path), 'main.tex');
    });

    test('finds main.tex nested in subdirectory', () async {
      final zip = _makeZip(
        tempDir,
        {
          'project/images/fig.png': 'PNG',
          'project/main.tex': r'\documentclass{article}',
          'project/refs.bib': '@article{a,}',
        },
        name: 'nested.zip',
      );

      final dest = Directory(p.join(tempDir.path, 'out_nested'));
      final result = await ZipExtractor.extract(zip, dest);

      expect(result.mainTex.existsSync(), isTrue);
      expect(p.basename(result.mainTex.path), 'main.tex');
    });

    test('falls back to first .tex when no file named main.tex', () async {
      final zip = _makeZip(
        tempDir,
        {'thesis.tex': r'\documentclass{report}'},
        name: 'fallback.zip',
      );

      final dest = Directory(p.join(tempDir.path, 'out_fallback'));
      final result = await ZipExtractor.extract(zip, dest);

      expect(result.mainTex.existsSync(), isTrue);
      expect(result.mainTex.path, endsWith('thesis.tex'));
    });

    test('throws FileSystemException when no .tex file exists', () async {
      final zip = _makeZip(
        tempDir,
        {'README.md': '# Hello'},
        name: 'notex.zip',
      );

      final dest = Directory(p.join(tempDir.path, 'out_notex'));

      expect(
        () => ZipExtractor.extract(zip, dest),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('rejects ZIP entries with path traversal', () async {
      // Build a ZIP manually with an unsafe entry name.
      final archive = Archive();
      archive.addFile(
        ArchiveFile(
          '../evil.tex',
          4,
          Uint8List.fromList('evil'.codeUnits),
        ),
      );
      final zipBytes = ZipEncoder().encode(archive)!;
      final zip = File(p.join(tempDir.path, 'traversal.zip'));
      zip.writeAsBytesSync(zipBytes);

      final dest = Directory(p.join(tempDir.path, 'out_traversal'));

      expect(
        () => ZipExtractor.extract(zip, dest),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('extracts .bib and image files alongside .tex', () async {
      final zip = _makeZip(
        tempDir,
        {
          'main.tex': r'\documentclass{article}',
          'refs.bib': '@misc{x,}',
          'images/fig1.png': 'PNG',
        },
        name: 'full.zip',
      );

      final dest = Directory(p.join(tempDir.path, 'out_full'));
      final result = await ZipExtractor.extract(zip, dest);

      expect(File(p.join(result.extractRoot.path, 'refs.bib')).existsSync(), isTrue);
      expect(
        File(p.join(result.extractRoot.path, 'images', 'fig1.png')).existsSync(),
        isTrue,
      );
    });
  });
}
